# ─── Bescherm tegen herhaald laden ─────────────────────────────────────
if ($Global:CleanSubsLoaded) { return }
$Global:CleanSubsLoaded = $true

function Clean-SubtitleFile {
    param(
        [string]$SubtitlePath
    )
    
    try {
        # Try to detect and read with correct encoding
        $content = $null
        $encoding = $null
        
        # Try UTF8 first (most common for subtitles)
        try {
            $content = Get-Content -LiteralPath $SubtitlePath -Raw -Encoding UTF8
            # Check for UTF8 BOM or valid UTF8 characters
            if ($content -match '[à-ÿ]' -or [System.Text.Encoding]::UTF8.GetByteCount($content) -eq (Get-Item -LiteralPath $SubtitlePath).Length) {
                $encoding = [System.Text.Encoding]::UTF8
            }
        } catch {}
        
        # If UTF8 didn't work or contains mojibake, try Windows-1252 (Western European)
        if (-not $content -or $content -match '�|�') {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($SubtitlePath)
                $content = [System.Text.Encoding]::GetEncoding(1252).GetString($bytes)
                $encoding = [System.Text.Encoding]::GetEncoding(1252)
            } catch {
                # Fall back to default
                $content = Get-Content -LiteralPath $SubtitlePath -Raw -Encoding Default
                $encoding = [System.Text.Encoding]::Default
            }
        }
        
        if (-not $content) { return $false }
        
        $originalContent = $content
        $changes = 0
        
        # 1. Remove HTML tags (common in downloaded subs)
        $htmlPattern = '<[^>]+>'
        if ($content -match $htmlPattern) {
            $content = $content -replace $htmlPattern, ' '
            $changes++
        }
        
        # 2. Remove SDH markers (sound effects, speaker names, etc.)
        # Pattern: [text], (text), ♪text♪, *text*
        $sdhPatterns = @(
            '\[.*?\]',           # [Door slams], [Music playing]
            '\(.*?\)',           # (LAUGHS), (door opens)
            '♪.*?♪',             # ♪ music ♪
            '^\*.*?\*$',         # *sound effect*
            '^\-\s*\[.*?\]',     # - [GASPS]
            '^[\(\[].*?[\)\]]:' # (NARRATOR): or [JOHN]:
        )
        
        foreach ($pattern in $sdhPatterns) {
            $beforeCount = ($content -split "`n").Count
            $content = $content -replace $pattern, ' '
            $afterCount = ($content -split "`n").Count
            if ($beforeCount -ne $afterCount) { $changes++ }
        }
        
        # 3. Remove control characters and null bytes that might cause empty boxes
        $content = $content -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
        
        # 4. Clean up excessive whitespace
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
        
        # Save if changes were made - always save as UTF8 with BOM for maximum compatibility
        if ($content -ne $originalContent) {
            # Use UTF8 with BOM to ensure accented characters are preserved
            $utf8BOM = New-Object System.Text.UTF8Encoding $true
            [System.IO.File]::WriteAllText($SubtitlePath, $content, $utf8BOM)
            return $true
        }
        
        return $false
        
    } catch {
        Show-Format "ERROR" "Clean failed" "$SubtitlePath : $_" -NameColor "Red"
        return $false
    }
}

function Clean-AllSubtitles {
    DrawBanner "STEP 08 CLEAN SUBTITLES"
    
    $tempDir = $Global:TempDir
    $logPath = Join-Path $Global:LogDir "clean_subs.log"
    
    # Find all subtitle files
    $allSubs = @(Get-ChildItem -LiteralPath $tempDir -Recurse -Filter "*.srt" -File)
    
    if ($allSubs.Count -eq 0) {
        Show-Format "INFO" "No subtitles to clean" "" -NameColor "Yellow"
        return
    }
    
    Show-Format "INFO" "Found $($allSubs.Count) subtitle files to clean" "" -NameColor "Cyan"
    
    Set-Content -Path $logPath -Value "SubtitleFile`tCleaned`tTimestamp"
    
    $cleanedCount = 0
    $skippedCount = 0
    
    foreach ($sub in $allSubs) {
        $wasCleaned = Clean-SubtitleFile -SubtitlePath $sub.FullName
        
        if ($wasCleaned) {
            Show-Format "CLEANED" "$($sub.Name)" "Removed HTML/SDH markers" -NameColor "Green"
            Add-Content -Path $logPath -Value "$($sub.Name)`tYes`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $cleanedCount++
        } else {
            Show-Format "SKIP" "$($sub.Name)" "Already clean or no changes needed" -NameColor "DarkGray"
            Add-Content -Path $logPath -Value "$($sub.Name)`tNo`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $skippedCount++
        }
    }
    
    Show-Format "SUMMARY" "Subtitle cleaning complete" "Cleaned: $cleanedCount, Skipped: $skippedCount" -NameColor "Yellow"
}

# ─── Begin taakcode ────────────────────────────────────────────────────
function Start-CleanSubs {
    Start-StepLog -StepNumber "08" -StepName "Clean_Subtitles"
    $runClean = $Global:RunClean
    if ($runClean -eq $false -or $runClean -eq "false") {
        Show-Format "SKIP" "Subtitle cleaning overgeslagen" "RunClean=false" -NameColor "DarkGray"
        Stop-StepLog
        return
    }
    Clean-AllSubtitles
    Stop-StepLog
}
