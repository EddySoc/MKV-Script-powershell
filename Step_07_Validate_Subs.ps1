# ─── Bescherm tegen herhaald laden ─────────────────────────────────────
if ($Global:ValidateSubsLoaded) { return }
$Global:ValidateSubsLoaded = $true

function Validate-SubtitleFormat {
    param ([string]$filePath)
    
    try {
        # Use -LiteralPath to avoid wildcard issues with [ ] in filenames
        $content = Get-Content -LiteralPath $filePath -ErrorAction Stop
        if (-not $content) { return $false }
        
        # Check for SRT timecode pattern
        $hasTimecodes = $false
        foreach ($line in $content) {
            if ($line -match '^\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}$') {
                $hasTimecodes = $true
                break
            }
        }
        
        return $hasTimecodes
    } catch {
        return $false
    }
}

function Clean-SubtitleFile {
    param([string]$SubtitlePath)
    
    try {
        # Read content
        $content = Get-Content -LiteralPath $SubtitlePath -Raw -Encoding UTF8
        if (-not $content) { return $false }
        
        $originalContent = $content
        
        # 1. Remove HTML tags (common in downloaded subs)
        $content = $content -replace '<[^>]+>', ''
        
        # 2. Remove SDH markers (sound effects, speaker names, etc.)
        $sdhPatterns = @(
            '\[.*?\]',           # [Door slams], [Music playing]
            '\(.*?\)',           # (LAUGHS), (door opens)
            '♪.*?♪',             # ♪ music ♪
            '^\*.*?\*$',         # *sound effect*
            '^\-\s*\[.*?\]',     # - [GASPS]
            '^[\(\[].*?[\)\]]:' # (NARRATOR): or [JOHN]:
        )
        
        foreach ($pattern in $sdhPatterns) {
            $content = $content -replace $pattern, ''
        }
        
        # 3. Clean up excessive whitespace
        $content = $content -replace '[ \t]+', ' '          # Multiple spaces to single
        $content = $content -replace '(?m)^\s+', ''         # Leading whitespace
        $content = $content -replace '(?m)\s+$', ''         # Trailing whitespace
        $content = $content -replace '(?m)^\r?\n\r?\n\r?\n+', "`r`n`r`n"  # Max 2 consecutive newlines
        
        # 4. Rebuild subtitle structure properly
        $lines = $content -split "`r?`n"
        $blocks = @()
        $currentBlock = @()
        
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            
            # Skip completely empty lines
            if ($trimmed.Length -eq 0) {
                # End of block - save it if it has content
                if ($currentBlock.Count -gt 0) {
                    $blocks += ,@($currentBlock)
                    $currentBlock = @()
                }
                continue
            }
            
            # Add non-empty line to current block
            $currentBlock += $trimmed
        }
        
        # Don't forget the last block
        if ($currentBlock.Count -gt 0) {
            $blocks += ,@($currentBlock)
        }
        
        # 5. Rebuild SRT with proper structure: number, timestamp, text(s), blank line
        $cleanedLines = @()
        foreach ($block in $blocks) {
            if ($block.Count -ge 3) {
                # Valid block has at least: number, timestamp, text
                foreach ($line in $block) {
                    $cleanedLines += $line
                }
                # Add blank line after each block
                $cleanedLines += ''
            }
        }
        
        # Remove trailing empty line(s) at end of file
        while ($cleanedLines.Count -gt 0 -and $cleanedLines[-1] -eq '') {
            $cleanedLines = $cleanedLines[0..($cleanedLines.Count-2)]
        }
        
        $content = $cleanedLines -join "`r`n"
        
        # Save if changes were made
        if ($content -ne $originalContent) {
            Set-Content -LiteralPath $SubtitlePath -Value $content -Encoding UTF8 -NoNewline -Force
            return $true
        }
        
        return $false
        
    } catch {
        Show-Format "ERROR" "Clean failed" "$SubtitlePath : $_" -NameColor "Red"
        return $false
    }
}

function Get-VideoForSubtitle {
    param (
        [string]$subFileName,
        [System.IO.FileInfo[]]$allVideos
    )
    
    # Extract base name without language/suffix codes
    $baseName = $subFileName -replace '\.(dut|nld|ned|eng|en|fra|fr|ita|spa|por|deu|pla|ces|slk|pol|ron|tur|rus|ara|heb|jpn|kor|zho|tha|vie|ind)(\.\d{2})?(\.(EXT|INT|SYN))?\.srt$', ''
    
    # Try direct match
    $match = $allVideos | Where-Object { $_.BaseName -eq $baseName } | Select-Object -First 1
    if ($match) { return $match }
    
    # Try episode code match
    if ($baseName -match 'S\d{2}E\d{2}') {
        $episodeCode = $matches[0]
        $match = $allVideos | Where-Object { $_.BaseName -match $episodeCode } | Select-Object -First 1
        if ($match) { return $match }
    }
    
    # Try year match
    if ($baseName -match '\d{4}') {
        $year = $matches[0]
        $match = $allVideos | Where-Object { $_.BaseName -match $year } | Select-Object -First 1
        if ($match) { return $match }
    }
    
    return $null
}

function Validate-subs {
    DrawBanner "STEP 07 VALIDATE SUBTITLES"

    $allVideos = @(Get-ChildItem -LiteralPath $Global:TempDir -Recurse -Filter "*.mkv" -File -ErrorAction SilentlyContinue)
    
    # Try multiple methods to find .srt files using LiteralPath to avoid wildcard issues
    $allSubs = @()
    
    # Method 1: Recursive search with filter
    $subs1 = @(Get-ChildItem -LiteralPath $Global:TempDir -Recurse -Filter "*.srt" -File -ErrorAction SilentlyContinue)
    
    # Method 2: Explicit extension check
    $subs2 = @(Get-ChildItem -LiteralPath $Global:TempDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".srt" })
    
    # Use whichever found more
    if ($subs2.Count -gt $subs1.Count) {
        $allSubs = $subs2
        Show-Format "INFO" "Found subs via extension filter" "$($allSubs.Count)" -NameColor "DarkGray"
    } else {
        $allSubs = $subs1
        Show-Format "INFO" "Found subs via -Filter" "$($allSubs.Count)" -NameColor "DarkGray"
    }
    
    # Show-Format "INFO" "TempDir" "$TempDir" -NameColor "DarkGray"
    Show-Format "INFO" "Found videos: $($allVideos.Count)    Found subtitles: $($allSubs.Count)" -NameColor "Yellow"
    
    if ($allSubs.Count -eq 0) {
        Show-Format "WARNING" "No subtitles found in $Global:TempDir" "" -NameColor "Yellow"
        
        # Last resort: list what's actually in TempDir
        $allFiles = @(Get-ChildItem -LiteralPath $Global:TempDir -Recurse -File -ErrorAction SilentlyContinue)
        Show-Format "DEBUG" "Total files in TempDir" "$($allFiles.Count)" -NameColor "DarkGray"
        $allFiles | Select-Object -First 10 | ForEach-Object {
            Show-Format "DEBUG" "File" "$($_.Name)" -NameColor "DarkGray"
        }
        Set-StepRunResult -Step "07" -Success 0 -Failed 0 -FailedItems @() -Note "no subtitles found"
        return
    }
    
    $logPath = Join-Path $Global:LogDir "validate_subs.log"
    
    $stats = @{
        TOTAL       = 0
        VALID       = 0
        REJECTED    = 0
    }
    $rejectedFiles = @()
    
    Set-Content -Path $logPath -Value "SubtitleFile`tLanguage`tFormatOK`tStatus"

    foreach ($sub in $allSubs) {
        $subPath = $sub.FullName
        $fileName = $sub.Name
        $stats.TOTAL++
        
        # Show-Format "CHECK" $fileName ""
        
        # 1. Check language (try to extract, but don't reject if missing)
        $lang = Get-SubtitleLanguage $fileName
        if (-not $lang) {
            # No language code in filename - use default from config
            $lang = $Global:Lang
        }
        
        # 2. Check format (must be valid SRT)
        $formatOK = if (Validate-SubtitleFormat $subPath) { "YES" } else { "NO" }
        
        # Accept all valid SRT files, regardless of language code in filename
        # Language validation will happen later in Score stage
        if ($formatOK -eq "YES") {
            # Clean the subtitle file (remove HTML/SDH, fix structure)
            $wasCleaned = Clean-SubtitleFile -SubtitlePath $subPath
            $cleanMsg = if ($wasCleaned) { ", cleaned" } else { "" }
            Show-Format "VALID" "$fileName" "lang=$lang, format=OK$cleanMsg" -NameColor "Green"
            $stats.VALID++
            Add-Content -Path $logPath -Value "$fileName`t$lang`tYES`tVALID"
        } else {
            Show-Format "INVALID" "$fileName" "Bad SRT format" -NameColor "Red"
            $stats.REJECTED++
            $rejectedFiles += $fileName
            Add-Content -Path $logPath -Value "$fileName`t$lang`tNO`tINVALID"
        }
    }

    Show-Format "SUMMARY" "Subtitles: Total=$($stats.TOTAL), Valid=$($stats.VALID), Invalid=$($stats.REJECTED)" -NameColor "Yellow"
    Set-StepRunResult -Step "07" -Success $stats.VALID -Failed $stats.REJECTED -FailedItems $rejectedFiles -Note "total=$($stats.TOTAL)"
}


# ─── Begin taakcode ────────────────────────────────────────────────────
function Start-Validate {
    Start-StepLog -StepNumber "07" -StepName "Validate_Subtitles"
    Validate-subs
    Stop-StepLog
}


