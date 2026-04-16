# ─── Bescherm tegen herhaald laden ─────────────────────────────────────
if ($Global:ScoreSubsLoaded) { return }
$Global:ScoreSubsLoaded = $true

function Score-Subtitle {
    param (
        [string]$filePath,
        [string]$language = "unknown"
    )
    
    $score = 0
    
    try {
        if (-not (Test-Path -LiteralPath $filePath)) {
            return 0
        }
        
        $content = @(Get-Content -LiteralPath $filePath -ErrorAction Stop)
        if (-not $content -or $content.Count -eq 0) { 
            return 0 
        }
        
        # 1. Timecode completeness (how many valid subtitle lines)
        $timecodes = @($content | Where-Object { $_ -match '\d{2}:\d{2}:\d{2},\d{3}\s*-->\s*\d{2}:\d{2}:\d{2},\d{3}' })
        if ($timecodes.Count -gt 0) {
            $score += [Math]::Min(($timecodes.Count / 10), 30)  # Max 30 points
        }
        
        # 2. File size (more content = better coverage)
        $fileSize = (Get-Item -LiteralPath $filePath).Length
        $score += [Math]::Min(($fileSize / 10000), 20)  # Max 20 points
        
        # 3. Filename simplicity (no extra suffixes = better quality)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
        $dots = ($baseName -split '\.').Count
        $simplicity = [Math]::Max(0, 30 - ($dots * 3))  # Fewer dots = more points (max 30)
        $score += $simplicity
        
        # 4. Timing quality (first sub starts near beginning, last sub ends near end)
        if ($timecodes.Count -gt 1) {
            try {
                $first = $timecodes[0] -split '\s*-->\s*'
                $last = $timecodes[-1] -split '\s*-->\s*'
                
                $startTime = $first[0].Trim().Replace(',', '.')
                $endTime = $last[1].Trim().Replace(',', '.')
                
                $start = [TimeSpan]::ParseExact($startTime, 'hh\:mm\:ss\.fff', $null).TotalSeconds
                $end = [TimeSpan]::ParseExact($endTime, 'hh\:mm\:ss\.fff', $null).TotalSeconds
                
                # Good if starts shortly and covers most of duration
                $startScore = [Math]::Max(0, 10 - ($start / 60))  # Penalize late starts
                $score += [Math]::Max(0, $startScore)
            } catch {
                # Silently skip timing score if parsing fails
            }
        }
        
        # 5. BONUS: Internal subtitles (.INT.srt) get high priority
        if ($filePath -match '\.INT\.srt$') {
            $score += 50  # Good bonus for internal subs
        }
        
        # 6. LANGUAGE PRIORITY: Primary language gets highest bonus
        if ($language -ne "unknown" -and $Global:LangKeep -and $Global:LangKeep.Count -gt 0) {
            # Expand language codes to include all variants
            $langList = Expand-LangKeep -LangKeep $Global:LangKeep -LangMap $Global:LangMap
            
            # Primary language (first in LangKeep) gets maximum bonus
            $primaryLang = $Global:LangKeep[0]
            $primaryVariants = $Global:LangMap[$primaryLang]
            
            if ($primaryVariants -contains $language) {
                $score += 150  # Primary language gets top priority
            } elseif ($langList -contains $language) {
                $score += 75  # Secondary kept languages get moderate bonus
            }
        }
        
    } catch {
        return 0
    }
    
    return [Math]::Round($score, 1)
}

function Score-Subtitles {
    DrawBanner "STEP 09 SCORE SUBTITLES"

    $logPath = Join-Path $Global:LogDir "score_subs.log"
    $metaDir = $Global:MetaDir
    
    if (-not (Test-Path -LiteralPath $metaDir)) {
        New-Item -ItemType Directory -Path $metaDir -Force | Out-Null
    }
    
    Set-Content -Path $logPath -Value "VideoName`tSubtitleFile`tLanguage`tScore"

    # Group subtitles by video
    $videos = @{}
    Get-ChildItem -LiteralPath $TempDir -Recurse -Filter "*.srt" -File | ForEach-Object {
        $subName = $_.Name
        $subPath = $_.FullName
        
        # Try to read language from validation metadata first (saved as .lang file)
        $langFile = "$($_.FullName).lang"
        $subLang = $null
        
        if (Test-Path -LiteralPath $langFile) {
            try {
                $subLang = Get-Content -LiteralPath $langFile -ErrorAction Stop
                $subLang = $subLang.Trim()
            } catch {
                # If metadata read fails, fall back to extraction
                $subLang = $null
            }
        }
        
        # If still no language, extract from filename
        if (-not $subLang) {
            $subLang = Get-SubtitleLanguage $subName
        }
        
        # Extract base name for grouping - remove language code suffix and extensions
        # Match pattern like: Name.eng.srt or Name.EXT.eng.srt or Name.INT.srt
        $baseName = $subName -replace '\.(dut|nld|ned|eng|en|fra|fr|ita|spa|por|deu|pla|ces|slk|pol|ron|tur|rus|ara|heb|jpn|kor|zho|tha|vie|ind)(\.\d{2})?(\.(EXT|INT|SYN))?\.srt$', ''
        
        # Fallback: if above doesn't match, just remove .srt extension
        if ($baseName -eq $subName) {
            $baseName = $subName -replace '\.srt$', ''
        }
        
        if (-not $videos[$baseName]) {
            $videos[$baseName] = @()
        }
        
        $videos[$baseName] += @{
            Name     = $subName
            Path     = $subPath
            Language = $subLang
        }
    }

    # Score each video's subtitles
    $processedVideos = 0
    foreach ($videoBase in $videos.Keys) {
        $subs = $videos[$videoBase]
        $processedVideos++
        
        Show-Format "PROCESS" "$videoBase" "$($subs.Count) subs found"
        
        # Score each subtitle
        $scoredSubs = @()
        foreach ($sub in $subs) {
            $score = Score-Subtitle -filePath $sub.Path -language $sub.Language
            Add-Content -Path $logPath -Value "$videoBase`t$($sub.Name)`t$($sub.Language)`t$score"
            
            $scoredSubs += @{
                Name     = $sub.Name
                Path     = $sub.Path
                Language = $sub.Language
                Score    = $score
            }
            
            Show-Format "SCORE" "$($sub.Name)" "lang=$($sub.Language), score=$score" -NameColor "Cyan"
        }
        
        # Find best subtitle for this video
        if ($scoredSubs.Count -gt 0) {
            $bestSub = $scoredSubs | Sort-Object -Property Score -Descending | Select-Object -First 1
            Show-Format "BEST" "$videoBase" "$($bestSub.Name) (score=$($bestSub.Score))" -NameColor "Green"
        }
        DrawBar "*"
    }

    Show-Format "SUMMARY" "Scored all subtitles" "See $logPath for details" -NameColor "Yellow"
    Set-StepRunResult -Step "09" -Success $processedVideos -Failed 0 -FailedItems @() -Note "videos scored"
}

# ─── Begin taakcode ────────────────────────────────────────────────────
function Start-Score {
    Start-StepLog -StepNumber "09" -StepName "Score_Subs"
    Score-Subtitles
    Stop-StepLog
}
