# ─── Bescherm tegen herhaald laden ─────────────────────────────────────
if ($Global:DownloadSubsLoaded) { return }
$Global:DownloadSubsLoaded = $true

# ─── Module: DownloadSubs.ps1 ───────────────────────────────────────
# Doel: Download subs met filebot
# Aanroep: via hoofdscript dat Config.ps1 en Utils.ps1 al heeft geladen


$SettingsFile = $Global:FBSettingsFile
$AuthFile     = $Global:AuthFile

# --- FUNCTIE: FileBot-config controleren
function Check-FileBotConfig {
    DrawBanner -Text "CHECK FILEBOT CONFIG"

    $SettingsPath = Join-Path $Global:ToolsDir $SettingsFile
    
    if (-not (Test-Path $SettingsPath)) {
        Show-Format "ERROR" "Settings file not found: $SettingsPath" "" -NameColor "Red"
        return
    }

    $hasUser = Select-String -Path $SettingsPath -Pattern '^osdb\.user=' -Quiet
    if (-not $hasUser) {
        Load-Credentials
    } else {
        Show-Format "INFO" "OpenSubtitles credentials already configured." "" -NameColor "Green"
    }
}

# --- FUNCTIE: Credentials laden uit OpenSubtitles.auth
function Load-Credentials {
    $AuthPath = Join-Path $ScriptDir $AuthFile

    if (Test-Path $AuthPath) {
        Get-Content $AuthFile | ForEach-Object {
            if ($_ -match '^\s*([^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $val = $matches[2].Trim()
                Set-Variable -Name $key -Value $val -Scope Script
            }
        }
        Show-Format "INFO" "Credentials loaded from OpenSubtitles.auth" "" -NameColor "Green"
    } else {
        Show-Format "ERROR" "OpenSubtitles.auth file not found in $PSScriptRoot" "" -NameColor "Red"
    }
}

# --- FUNCTIE: Score subtitles to find best existing one
function Score-ExistingSub {
    param([string]$srtPath)
    if (-not (Test-Path -LiteralPath $srtPath)) { 
        if ($Global:DEBUGMode) {
            Show-Format "DEBUG" "Score-ExistingSub" "File not found: $srtPath" -NameColor "Red"
        }
        return 0 
    }
    
    try {
        $lines = @(Get-Content -LiteralPath $srtPath -ErrorAction Stop)
        if (-not $lines -or $lines.Count -eq 0) { 
            if ($Global:DEBUGMode) {
                Show-Format "DEBUG" "Score-ExistingSub" "File is empty: $srtPath" -NameColor "Yellow"
            }
            return 0 
        }
        
        if ($Global:DEBUGMode) {
            Show-Format "DEBUG" "Score-ExistingSub" "File has $($lines.Count) lines" -NameColor "DarkGray"
        }
        
        # Match timing lines with flexible spacing: HH:MM:SS,mmm --> HH:MM:SS,mmm
        $timingLines = @($lines | Where-Object { $_ -match '\d{2}:\d{2}:\d{2},\d{3}\s*-->\s*\d{2}:\d{2}:\d{2},\d{3}' })
        $textLines = @($lines | Where-Object { $_ -match '^[^\d].*\w' })
        
        if ($Global:DEBUGMode) {
            Show-Format "DEBUG" "Score-ExistingSub" "TimingLines: $($timingLines.Count), TextLines: $($textLines.Count)" -NameColor "DarkGray"
        }
        
        if ($timingLines.Count -lt 1) { 
            if ($Global:DEBUGMode) {
                Show-Format "DEBUG" "Score-ExistingSub" "No timing lines found - file may be corrupted" -NameColor "Yellow"
            }
            return 0 
        }
        
        $ratio = if ($timingLines.Count -gt 0) { $textLines.Count / $timingLines.Count } else { 0 }
        $score = $timingLines.Count + ($textLines.Count * 0.1) + ($ratio * 10)
        
        if ($Global:DEBUGMode) {
            Show-Format "DEBUG" "Score-ExistingSub" "Ratio: $([Math]::Round($ratio, 2)), FinalScore: $([int]$score)" -NameColor "DarkGray"
        }
        
        return $score
    } catch {
        if ($Global:DEBUGMode) {
            Show-Format "DEBUG" "Score-ExistingSub ERROR" "$_" -NameColor "Red"
        }
        return 0
    }
}

# --- FUNCTIE: Subs controleren en lijst opbouwen
function Get-MissingSubtitles {
    DrawBanner -Text "CHECK FOR MISSING SUBTITLES"
    if (Test-Path $NoSubList) { Remove-Item $NoSubList -Force }

    # Find all video files (both mkv and mp4) in TempDir
    # Exclude .h264.mkv files (temporary conversion outputs)
    $allVideos = @()
    $allVideos += Get-ChildItem -Path $Global:TempDir -Recurse -Filter "*.mkv" -File | Where-Object { $_.Name -notlike "*.h264.mkv" }
    $allVideos += Get-ChildItem -Path $Global:TempDir -Recurse -Filter "*.mp4" -File
    
    $allVideos | ForEach-Object {
        $videoPath  = $_.FullName
        $baseName   = $_.BaseName
        $videoDir   = Split-Path $videoPath -Parent

        # Extract title from video filename (before quality markers like BluRay, 1080p, x264, etc.)
        # This allows matching subtitles with shorter names like "Dark.City.1998.dut.srt"
        $titlePattern = $baseName -replace '\.(BluRay|BRRip|WEBRip|WEB-DL|DVDRip|HDTV|1080p|720p|2160p|4K|x264|x265|h264|h265|HEVC|AAC|AC3|DTS|5\.1|7\.1|PROPER|REPACK).*$', ''
        
        if ($Global:DEBUGMode) {
            Show-Format "DEBUG" "Checking video: $baseName" "Dir: $videoDir" -NameColor "Cyan"
            Show-Format "DEBUG" "TitlePattern: $titlePattern" "" -NameColor "DarkGray"
        }
        
        # Look for subtitle files that match either:
        # 1. Exact basename (strict match)
        # 2. Title portion only (flexible match for subtitles with different release names)
        $allSrtsInDir = Get-ChildItem -LiteralPath $videoDir -Filter "*.srt" -ErrorAction SilentlyContinue
        
        if ($Global:DEBUGMode -and $allSrtsInDir.Count -gt 0) {
            Show-Format "DEBUG" "Found $($allSrtsInDir.Count) .srt file(s) in directory" "" -NameColor "DarkGray"
        }
        
        $matchingSubs = $allSrtsInDir | Where-Object { 
            # Strict match: exact basename + extension
            $_.BaseName -match "^$([regex]::Escape($baseName))(\.|$)" -or
            # Flexible match: starts with title pattern (allows for different year/release names)
            ($titlePattern -and $_.BaseName -match "^$([regex]::Escape($titlePattern))(\.|$)")
        }
        
        # Filter for primary language subs only
        $primaryLangSubs = @()
        $langKeepArray = @($Global:LangKeep -split ',')
        $primaryLang = $langKeepArray[0].Trim()
        
        # Debug: show all matching subtitles found
        if ($matchingSubs.Count -gt 0 -and $Global:DEBUGMode) {
            Show-Format "DEBUG" "Found $($matchingSubs.Count) matching subtitle(s)" "for $baseName" -NameColor "DarkGray"
            foreach ($sub in $matchingSubs) {
                $subLang = Get-SubtitleLanguage $sub.Name
                Show-Format "DEBUG" "  - $($sub.Name)" "Lang: $subLang" -NameColor "DarkGray"
            }
        }
        
        foreach ($sub in $matchingSubs) {
            $subLang = Get-SubtitleLanguage $sub.Name
            # Accept if:
            # 1. Language matches the primary language
            # 2. Language is unknown BUT the subtitle already matched our flexible pattern above
            #    (meaning it's already paired with this video by name)
            if ($subLang -eq $primaryLang -or $subLang -eq "unknown") {
                $primaryLangSubs += $sub
                if ($Global:DEBUGMode) {
                    Show-Format "DEBUG" "  ✓ Accepted: $($sub.Name)" "Lang: $subLang" -NameColor "Green"
                }
            } else {
                if ($Global:DEBUGMode) {
                    Show-Format "DEBUG" "  ✗ Rejected: $($sub.Name)" "Lang: $subLang (want: $primaryLang)" -NameColor "Red"
                }
            }
        }
        
        if ($primaryLangSubs.Count -gt 0) {
            # Found existing primary language subs for THIS video - score them
            $bestScore = 0
            $bestSub = $null
            
            foreach ($sub in $primaryLangSubs) {
                if ($Global:DEBUGMode) {
                    Show-Format "DEBUG" "  Scoring file:" "$($sub.FullName)" -NameColor "Cyan"
                }
                $score = Score-ExistingSub $sub.FullName
                if ($Global:DEBUGMode) {
                    Show-Format "DEBUG" "  Score: $($sub.Name)" "= $([int]$score)" -NameColor "DarkGray"
                }
                if ($score -gt $bestScore) {
                    $bestScore = $score
                    $bestSub = $sub.Name
                }
            }
            
            # Dynamic threshold based on score (allow lower scores for short videos)
            # If score > 20 (has at least some valid timing lines), accept it
            $minAcceptableScore = 20
            
            if ($bestScore -gt $minAcceptableScore) {
                # Good quality existing sub found
                $subLang = Get-SubtitleLanguage $bestSub
                $langInfo = if ($subLang -eq "unknown") { "no lang tag" } else { $subLang }
                Show-Format "SKIP" "$($_.Name)" "Has sub: $bestSub ($langInfo, score: $([int]$bestScore))" -NameColor "DarkGray"
            } else {
                # Existing subs are poor quality - mark for download
                Show-Format "ADD 2 LIST" "$($_.Name)" "Existing subs too low quality ($([int]$bestScore)) - will download" -NameColor "Yellow"
                Add-Content -Path $NoSubList -Value $videoPath
            }
        } else {
            # No primary language subs found - mark for download
            Show-Format "ADD 2 LIST" "$($_.Name)" "No $primaryLang subtitles found" -NameColor "Green"
            Add-Content -Path $NoSubList -Value $videoPath
        }
    }
}

# --- FUNCTIE: Build query hint from filename for safer subtitle lookup
function Get-SearchQueryFromVideoName {
    param([string]$VideoName)

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($VideoName)
    if (-not $baseName) { return $null }

    $query = $baseName
    $query = $query -replace '[._\-]+', ' '
    $query = $query -replace '\b(BluRay|BRRip|WEBRip|WEB-DL|DVDRip|HDTV|1080p|720p|2160p|4K|x264|x265|h264|h265|HEVC|AAC|AC3|DTS|PROPER|REPACK|YTS|AM|RARBG)\b', ''
    $query = $query -replace '\s+', ' '
    $query = $query.Trim()

    # Convert "Title 2018 ..." into "Title (2018)" for better metadata matching.
    if ($query -match '^(.*?)(19\d{2}|20\d{2})\b') {
        $title = $matches[1].Trim()
        $year = $matches[2]
        if ($title) {
            return "$title ($year)"
        }
    }

    return $query
}

# --- FUNCTIE: Validate that fetched subtitle release resembles target video title
function Test-SubtitleTitleMatch {
    param(
        [string]$VideoName,
        [string]$FetchedRelease
    )

    if (-not $FetchedRelease) { return $true }

    $query = Get-SearchQueryFromVideoName -VideoName $VideoName
    if (-not $query) { return $true }

    $videoTokens = @($query.ToLower() -split '[^a-z0-9]+' | Where-Object { $_ -and $_.Length -ge 3 })
    $releaseTokens = @($FetchedRelease.ToLower() -split '[^a-z0-9]+' | Where-Object { $_ -and $_.Length -ge 3 })

    if ($videoTokens.Count -eq 0 -or $releaseTokens.Count -eq 0) { return $true }

    $overlap = @($videoTokens | Where-Object { $releaseTokens -contains $_ } | Select-Object -Unique).Count
    $required = [Math]::Max(1, [Math]::Ceiling($videoTokens.Count * 0.4))
    return ($overlap -ge $required)
}

# --- FUNCTIE: Subs downloaden via FileBot
function Download-Subtitles {
    DrawBanner -Text "STEP 05 DOWNLOADING SUBS"
    
    # Get OpenSubtitles credentials
    $authPath = Join-Path $Global:ScriptDir $AuthFile
    $osdbUser = ""
    $osdbPwd = ""
    
    if (Test-Path $authPath) {
        Get-Content $authPath | ForEach-Object {
            # Support both formats: osdbuser= and osdb.user=
            if ($_ -match '^\s*osdb\.?user\s*=\s*(.+)$') {
                $osdbUser = $matches[1].Trim()
            }
            if ($_ -match '^\s*osdb\.?[pP]wd\s*=\s*(.+)$') {
                $osdbPwd = $matches[1].Trim()
            }
        }
    }
    
    if (-not $osdbUser -or -not $osdbPwd) {
        Show-Format "ERROR" "OpenSubtitles credentials not found in $authPath" "" -NameColor "Red"
        Show-Format "INFO" "Please configure osdb.user and osdb.pwd in $AuthFile" "" -NameColor "Yellow"
        Set-StepRunResult -Step "05" -Success 0 -Failed 1 -FailedItems @("OpenSubtitles credentials missing") -Note "configuration error"
        return
    }
    
    Show-Format "INFO" "Using OpenSubtitles credentials: $osdbUser" "" -NameColor "Cyan"

    # Sync credentials from auth file into FileBot settings.properties so FileBot uses the latest values
    $fbSettingsPath = Join-Path $Global:ToolsDir $SettingsFile
    if (Test-Path $fbSettingsPath) {
        $credLine = "net/filebot/login/OpenSubtitles=$osdbUser`t$osdbPwd"
        $settingsContent = @(Get-Content $fbSettingsPath)
        $hasEntry = $settingsContent | Where-Object { $_ -match '^net/filebot/login/OpenSubtitles=' }
        if ($hasEntry) {
            $newContent = $settingsContent | ForEach-Object {
                if ($_ -match '^net/filebot/login/OpenSubtitles=') { $credLine } else { $_ }
            }
        } else {
            $newContent = $settingsContent + $credLine
        }
        Set-Content -Path $fbSettingsPath -Value $newContent -Encoding UTF8 -NoNewline:$false
        Show-Format "INFO" "Credentials synced to FileBot settings" "" -NameColor "DarkGray"
    } else {
        Show-Format "WARNING" "FileBot settings.properties not found: $fbSettingsPath" "Credentials not synced" -NameColor "Yellow"
    }
    
    # Clean up orphaned subtitle folders (folders with .srt but no video files)
    Show-Format "INFO" "Cleaning up orphaned subtitle folders..." "" -NameColor "Cyan"
    $orphanedCount = 0
    Get-ChildItem -Path $Global:TempDir -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $folder = $_
        $hasVideos = @(Get-ChildItem -LiteralPath $folder.FullName -Include "*.mkv","*.mp4","*.avi" -File -ErrorAction SilentlyContinue).Count
        $hasSubs = @(Get-ChildItem -LiteralPath $folder.FullName -Filter "*.srt" -File -ErrorAction SilentlyContinue).Count
        
        if ($hasSubs -gt 0 -and $hasVideos -eq 0) {
            # Folder has subtitles but no video files - likely already processed
            try {
                Remove-Item -LiteralPath $folder.FullName -Recurse -Force -ErrorAction Stop
                Show-Format "CLEANUP" "$($folder.Name)" "Removed orphaned subtitle folder" -NameColor "DarkGray"
                $orphanedCount++
            } catch {
                Show-Format "WARNING" "$($folder.Name)" "Could not remove: $_" -NameColor "Yellow"
            }
        }
    }
    if ($orphanedCount -gt 0) {
        Show-Format "INFO" "Cleaned up $orphanedCount orphaned folder(s)" "" -NameColor "Yellow"
    }
    
    # Build exclude list - videos that already have primary language subtitles
    $excludeList = Join-Path $Global:LogDir "exclude_download.txt"
    $excludeContent = @()
    
    # Find all video files in TempDir (where videos are located after Step 2)
    # Exclude .h264.mkv files (those are temporary conversion outputs)
    $allVideos = @()
    $allVideos += Get-ChildItem -Path $Global:TempDir -Recurse -Filter "*.mkv" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*.h264.mkv" }
    $allVideos += Get-ChildItem -Path $Global:TempDir -Recurse -Filter "*.mp4" -File -ErrorAction SilentlyContinue
    
    Show-Format "INFO" "Building exclude list (videos with $($Global:LangKeep) subs)..." "" -NameColor "Cyan"
    
    $langKeepArray = @($Global:LangKeep -split ',')
    $primaryLang = $langKeepArray[0].Trim()
    
    foreach ($video in $allVideos) {
        $videoDir = $video.DirectoryName
        $baseName = $video.BaseName
        
        # Use same matching logic as Get-MissingSubtitles
        $titlePattern = $baseName -replace '\.(BluRay|BRRip|WEBRip|WEB-DL|DVDRip|HDTV|1080p|720p|2160p|4K|x264|x265|h264|h265|HEVC|AAC|AC3|DTS|5\.1|7\.1|PROPER|REPACK).*$', ''
        
        $allSrtsInDir = Get-ChildItem -LiteralPath $videoDir -Filter "*.srt" -ErrorAction SilentlyContinue
        $matchingSubs = $allSrtsInDir | Where-Object { 
            $_.BaseName -match "^$([regex]::Escape($baseName))(\.|$)" -or
            ($titlePattern -and $_.BaseName -match "^$([regex]::Escape($titlePattern))(\.|$)")
        }
        
        # Check if any matching subtitle is in primary language
        $hasPrimaryLangSub = $false
        foreach ($sub in $matchingSubs) {
            $subLang = Get-SubtitleLanguage $sub.Name
            if ($subLang -eq $primaryLang -or $subLang -eq "unknown") {
                # Check if it's a valid subtitle (score > threshold)
                $score = Score-ExistingSub $sub.FullName
                if ($score -gt 20) {
                    $hasPrimaryLangSub = $true
                    break
                }
            }
        }
        
        if ($hasPrimaryLangSub) {
            # Has valid external subtitle, add to exclude list
            $excludeContent += $video.FullName
        }
    }
    
    # Write exclude list
    if ($excludeContent.Count -gt 0) {
        Set-Content -Path $excludeList -Value $excludeContent -Encoding UTF8
        Show-Format "INFO" "Exclude list created" "$($excludeContent.Count) videos already have $($Global:Lang) subs" -NameColor "Yellow"
    } else {
        # Create empty file if no excludes
        Set-Content -Path $excludeList -Value "" -Encoding UTF8
        Show-Format "INFO" "No videos to exclude" "All videos need $($Global:Lang) subs" -NameColor "Yellow"
    }
    
    # Download only primary language subtitles
    Show-Format "INFO" "Downloading $($Global:LangKeep) subtitles from TempDir..." "" -NameColor "Green"
    
    # Check if there are actually videos that need subtitles
    if (-not (Test-Path $NoSubList) -or (Get-Content $NoSubList -ErrorAction SilentlyContinue).Count -eq 0) {
        Show-Format "INFO" "No subtitles to download" "All videos already have subtitles" -NameColor "Green"
        Set-StepRunResult -Step "05" -Success 0 -Failed 0 -FailedItems @() -Note "nothing to download"
        return
    }
    
    Show-Format "INFO" "This may take a while, please wait..." "" -NameColor "Yellow"
    $filebotLog = Join-Path $Global:LogDir "filebot_download.log"
    $downloadLog = Join-Path $Global:LogDir "download_subtitles.log"

    # Reset FileBot log each run so success parsing reflects only current downloads.
    Set-Content -Path $filebotLog -Value "" -Encoding UTF8
    
    # Create download log header
    Set-Content -Path $downloadLog -Value "VideoFile`tSubtitleDownloaded`tLanguage`tTimestamp"
    
    # Read videos that need subtitles
    $videosNeedingSubs = @(Get-Content $NoSubList | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    
    if ($videosNeedingSubs.Count -eq 0) {
        Show-Format "INFO" "No valid videos in download list" "All videos already have subtitles" -NameColor "Green"
        Set-StepRunResult -Step "05" -Success 0 -Failed 0 -FailedItems @() -Note "no valid videos in list"
        return
    }
    
    Show-Format "INFO" "Downloading subtitles for $($videosNeedingSubs.Count) video(s)" "" -NameColor "Cyan"
    
    # Use FileBot to download subtitles - process each video individually
    # This gives us precise control over which videos to download for
    $startTime = Get-Date
    $processedCount = 0
    $acceptedCount = 0
    $failedVideos = @()
    
    foreach ($videoPath in $videosNeedingSubs) {
        $videoName = [System.IO.Path]::GetFileName($videoPath)
        
        if ($Global:DEBUGMode) {
            Show-Format "DEBUG" "FileBot downloading for:" "$videoName" -NameColor "DarkGray"
        }
        
        # Build a title query for all videos so hash mismatches are less likely.
        $queryHint = Get-SearchQueryFromVideoName -VideoName $videoName
        
        # Download subtitle for this specific video
        # Note: credentials are supplied via FileBot settings.properties (synced above)
        # --def is only valid for -script calls and is ignored here
        # Try databases in order: OpenSubtitles first, then Subdl as fallback (free, no auth)
        $databases = @('OpenSubtitles', 'Subdl')
        $subDownloaded = $false

        foreach ($db in $databases) {
            if ($subDownloaded) { break }

            $filebotParams = @(
                '-get-subtitles', $videoPath,
                '--lang', $Global:LangKeep,
                '--db', $db,
                '-non-strict',
                '--output', 'srt',
                '--encoding', 'UTF-8',
                '--log-file', $filebotLog
            )

            # Add query hint if detected to help FileBot identify the series
            if ($queryHint) {
                if ($Global:DEBUGMode) {
                    Show-Format "DEBUG" "Using query hint ($db):" "$queryHint" -NameColor "DarkGray"
                }
                $filebotParams = @('-get-subtitles', $videoPath, '--q', $queryHint) + $filebotParams[2..($filebotParams.Length-1)]
            }

            $videoDir = Split-Path $videoPath -Parent
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($videoPath)
            $existingSubs = @(Get-ChildItem -LiteralPath $videoDir -Filter "*.srt" -ErrorAction SilentlyContinue |
                Where-Object { $_.BaseName -match "^$([regex]::Escape($baseName))" })
            $existingSubPaths = @($existingSubs | ForEach-Object { $_.FullName })

            # Run provider download and capture output so we can detect auth/token failures.
            $fbOutput = & filebot $filebotParams 2>&1

            # OpenSubtitles can fail with a stale cached token even when credentials are valid.
            # In that case clear FileBot cache and retry this provider once.
            if ($db -eq 'OpenSubtitles' -and (($fbOutput | Out-String) -match 'invalid token')) {
                Show-Format "WARNING" "OpenSubtitles token invalid" "Clearing FileBot cache and retrying once" -NameColor "Yellow"
                & filebot -clear-cache 2>&1 | Out-Null
                $fbOutput = & filebot $filebotParams 2>&1
            }

            # Check if a subtitle appeared after this attempt
            $allSubsAfterAttempt = @(Get-ChildItem -LiteralPath $videoDir -Filter "*.srt" -ErrorAction SilentlyContinue |
                Where-Object { $_.BaseName -match "^$([regex]::Escape($baseName))" })
            $newSubs = @($allSubsAfterAttempt | Where-Object { $_.FullName -notin $existingSubPaths })

            $fetchedRelease = $null
            $fetchMatch = [regex]::Match(($fbOutput | Out-String), 'Fetching \[[^\]]+\] subtitles \[([^\]]+)\]')
            if ($fetchMatch.Success) {
                $fetchedRelease = $fetchMatch.Groups[1].Value
            }

            $isMismatch = $false
            if ($newSubs.Count -gt 0 -and $fetchedRelease) {
                $isMismatch = -not (Test-SubtitleTitleMatch -VideoName $videoName -FetchedRelease $fetchedRelease)
            }

            if ($isMismatch) {
                foreach ($sub in $newSubs) {
                    Remove-Item -LiteralPath $sub.FullName -Force -ErrorAction SilentlyContinue
                }

                # Remove existing subtitles for this video as well to avoid keeping stale mismatched files.
                $staleSubs = @(Get-ChildItem -LiteralPath $videoDir -Filter "*.srt" -ErrorAction SilentlyContinue |
                    Where-Object { $_.BaseName -match "^$([regex]::Escape($baseName))(\.|$)" })
                foreach ($staleSub in $staleSubs) {
                    Remove-Item -LiteralPath $staleSub.FullName -Force -ErrorAction SilentlyContinue
                }

                Show-Format "WARNING" "Subtitle mismatch rejected" "$videoName <= $fetchedRelease" -NameColor "Yellow"

                # Retry OpenSubtitles once with forced title query.
                $forcedQuery = if ($queryHint) { $queryHint } else { Get-SearchQueryFromVideoName -VideoName $videoName }
                if ($forcedQuery) {
                    $retryParams = @('-get-subtitles', $videoPath, '--q', $forcedQuery) + $filebotParams[2..($filebotParams.Length-1)]
                    Show-Format "INFO" "Retry with forced query" "$forcedQuery" -NameColor "Cyan"
                    $retryOutput = & filebot $retryParams 2>&1

                    $subsAfterRetry = @(Get-ChildItem -LiteralPath $videoDir -Filter "*.srt" -ErrorAction SilentlyContinue |
                        Where-Object { $_.BaseName -match "^$([regex]::Escape($baseName))" })
                    $newSubs = @($subsAfterRetry | Where-Object { $_.FullName -notin $existingSubPaths })

                    $retryFetchedRelease = $null
                    $retryFetchMatch = [regex]::Match(($retryOutput | Out-String), 'Fetching \[[^\]]+\] subtitles \[([^\]]+)\]')
                    if ($retryFetchMatch.Success) {
                        $retryFetchedRelease = $retryFetchMatch.Groups[1].Value
                    }

                    if ($newSubs.Count -gt 0 -and $retryFetchedRelease -and -not (Test-SubtitleTitleMatch -VideoName $videoName -FetchedRelease $retryFetchedRelease)) {
                        foreach ($sub in $newSubs) {
                            Remove-Item -LiteralPath $sub.FullName -Force -ErrorAction SilentlyContinue
                        }

                        $retryStaleSubs = @(Get-ChildItem -LiteralPath $videoDir -Filter "*.srt" -ErrorAction SilentlyContinue |
                            Where-Object { $_.BaseName -match "^$([regex]::Escape($baseName))(\.|$)" })
                        foreach ($retryStaleSub in $retryStaleSubs) {
                            Remove-Item -LiteralPath $retryStaleSub.FullName -Force -ErrorAction SilentlyContinue
                        }

                        Show-Format "WARNING" "Retry mismatch rejected" "$videoName <= $retryFetchedRelease" -NameColor "Yellow"
                        $newSubs = @()
                    }
                }
            }

            if ($newSubs.Count -gt 0) {
                $subDownloaded = $true
                $acceptedCount++
                if ($Global:DEBUGMode) {
                    Show-Format "DEBUG" "$db succeeded for:" "$videoName" -NameColor "Green"
                }
            } elseif ($Global:DEBUGMode) {
                if ($db -eq 'OpenSubtitles' -and (($fbOutput | Out-String) -match 'invalid token')) {
                    Show-Format "DEBUG" "OpenSubtitles auth issue for:" "$videoName (invalid token after retry)" -NameColor "Yellow"
                }
                Show-Format "DEBUG" "$db found nothing for:" "$videoName" -NameColor "DarkGray"
            }
        }

        if (-not $subDownloaded) {
            $failedVideos += $videoName
        }

        $processedCount++
    }
    
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    Show-Format "INFO" "FileBot download completed" "Took $elapsed seconds" -NameColor "Green"
    
    # Build summary details from accepted results in this run.
    $downloadDetails = @()
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $downloadDetails += "accepted_subtitles`t$acceptedCount`t$($Global:Lang)`t$timestamp"
    
    # Write download details to log
    if ($acceptedCount -gt 0) {
        Add-Content -Path $downloadLog -Value $downloadDetails
        Show-Format "SUCCESS" "$($Global:Lang) subtitles" "Downloaded $acceptedCount subtitle(s)" -NameColor "Green"
    } else {
        Show-Format "INFO" "$($Global:Lang) subtitles" "No new subtitles found (may already exist)" -NameColor "Yellow"
    }
    
    Show-Format "SUMMARY" "Download process complete" "Check logs: $filebotLog and $downloadLog" -NameColor "Yellow"
    
    # Normalize subtitle filenames - fix double dots
    Show-Format "INFO" "Normalizing subtitle filenames..." "" -NameColor "Cyan"
    $normalizedCount = 0
    Get-ChildItem -Path $Global:TempDir -Recurse -Filter "*.srt" -File | ForEach-Object {
        $sub = $_
        $oldName = $sub.Name
        
        # Replace multiple consecutive dots with single dot
        if ($oldName -match '\.\.+') {
            $newName = $oldName -replace '\.\.+', '.'
            $newPath = Join-Path $sub.DirectoryName $newName
            
            try {
                Rename-Item -LiteralPath $sub.FullName -NewName $newName -Force -ErrorAction Stop
                Show-Format "NORMALIZE" "$oldName" "→ $newName" -NameColor "Cyan"
                $normalizedCount++
            } catch {
                Show-Format "WARNING" "Failed to rename $oldName" "$_" -NameColor "Yellow"
            }
        }
    }
    
    if ($normalizedCount -gt 0) {
        Show-Format "INFO" "Normalized $normalizedCount subtitle filename(s)" "" -NameColor "Green"
    }
    
    # FileBot downloaded subtitles directly to TempDir where videos are located
    Show-Format "INFO" "Subtitle download complete" "Subtitles are in TempDir with videos" -NameColor "Green"

    Set-StepRunResult -Step "05" -Success $acceptedCount -Failed ($processedCount - $acceptedCount) -FailedItems $failedVideos -Note "processed=$processedCount"
    
    # Copy subtitles back to source folders
    Copy-SubtitlesToSource
}

# --- FUNCTIE: Kopieer subtitles naar originele bronmappen
function Copy-SubtitlesToSource {
    DrawBanner -Text "COPY SUBTITLES TO SOURCE FOLDERS"
    
    # Check if metadata directory exists
    $metaDir = $Global:MetaDir
    if (-not (Test-Path $metaDir)) {
        Show-Format "WARNING" "Metadata directory not found: $metaDir" "Cannot copy subs to source" -NameColor "Yellow"
        return
    }
    
    # Find all subtitle files in TempDir
    $allSubs = Get-ChildItem -Path $Global:TempDir -Recurse -Filter "*.srt" -File -ErrorAction SilentlyContinue
    
    if ($allSubs.Count -eq 0) {
        Show-Format "INFO" "No subtitles found to copy" "" -NameColor "Yellow"
        return
    }
    
    $copiedCount = 0
    $skippedCount = 0
    
    foreach ($sub in $allSubs) {
        # Get base video name from subtitle filename
        # Subtitles are in format: videoname.lang.srt or videoname.nl.srt
        $subName = $sub.Name
        $videoBaseName = $subName -replace '\.(dut|nl|en|eng|fr|de|es)\.srt$', ''
        
        # Look for metadata file
        $metaFile = Join-Path $metaDir "$videoBaseName.meta.json"
        
        if (-not (Test-Path $metaFile)) {
            Show-Format "SKIP" "$subName" "No metadata found" -NameColor "DarkGray"
            $skippedCount++
            continue
        }
        
        # Read metadata to get source folder
        try {
            $metadata = Get-Content $metaFile -Raw | ConvertFrom-Json
            $sourceFolder = $metadata.SourceFolder
            
            if (-not $sourceFolder -or -not (Test-Path $sourceFolder)) {
                Show-Format "SKIP" "$subName" "Source folder not found: $sourceFolder" -NameColor "Yellow"
                $skippedCount++
                continue
            }
            
            # Copy subtitle to source folder
            $targetSubPath = Join-Path $sourceFolder $subName
            
            # Check if subtitle already exists in source
            if (Test-Path $targetSubPath) {
                # Compare file sizes to see if it's different
                $sourceSize = (Get-Item $sub.FullName).Length
                $targetSize = (Get-Item $targetSubPath).Length
                
                if ($sourceSize -eq $targetSize) {
                    Show-Format "SKIP" "$subName" "Already exists in source (same size)" -NameColor "DarkGray"
                    $skippedCount++
                    continue
                }
            }
            
            # Copy the subtitle
            Copy-Item -LiteralPath $sub.FullName -Destination $targetSubPath -Force -ErrorAction Stop
            Show-Format "COPY" "$subName" "→ $sourceFolder" -NameColor "Green"
            $copiedCount++
            
        } catch {
            Show-Format "ERROR" "$subName" "Failed to copy: $_" -NameColor "Red"
        }
    }
    
    Show-Format "SUMMARY" "Subtitle copy complete" "Copied: $copiedCount | Skipped: $skippedCount" -NameColor "Cyan"
}

function Start-DownloadSubs {
    Start-StepLog -StepNumber "05" -StepName "DownloadSubs"
# ─── Begin taakcode ────────────────────────────────────────────────────
    $skipDownload = ($Global:DownloadSubs -eq $false -or "$($Global:DownloadSubs)".ToLower() -eq 'false')
    if ($skipDownload) {
        DrawBanner -Text "STEP 05 DOWNLOAD SUBS"
        Show-Format "SKIP" "DownloadSubs=false" "Download overgeslagen via config" -NameColor "Yellow"
        Set-StepRunResult -Step "05" -Success 0 -Failed 0 -FailedItems @() -Note "step skipped (DownloadSubs=false)"
        Stop-StepLog
        return
    }
# --- Dynamisch afgeleide paden
$NoSubList    = Join-Path $LogDir "nosub_list.txt"
$ExcludeList  = Join-Path $LogDir "amc.txt"
# --- Uitvoering
Check-FileBotConfig
Get-MissingSubtitles
Download-Subtitles
    Stop-StepLog
}


