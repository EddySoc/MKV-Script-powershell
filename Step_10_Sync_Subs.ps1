function Sync-AndScore {
    # Load config if not already loaded (for standalone execution)
    if (-not $Global:ConfigLoaded) {
        . (Join-Path $PSScriptRoot "Config.ps1")
    }

    DrawBanner "STEP 10 SYNC AND SELECT BEST SUBTITLES"

    $syncModeName = if ($Global:SyncMode) { $Global:SyncMode.ToUpper() } else { "ALWAYS" }
    $forceSyncText = if ($syncModeName -eq "ALWAYS") { " (Force sync)" } else { "" }
    Show-Format "CONFIG" "SyncMode=$syncModeName$forceSyncText" "" -NameColor "Cyan"

    # Get all videos
    $tempDir = $Global:TempDir
    $allVideos = @(Get-ChildItem -LiteralPath $tempDir -Recurse -Filter "*.mkv" -File)
    $syncSuccess = 0
    $syncFailed = 0
    $syncFailedItems = @()

    foreach ($video in $allVideos) {
        $videoName = $video.BaseName
        $videoPath = $video.FullName
        $videoDir = $video.DirectoryName

        # Extract title prefix for fuzzy matching so manually downloaded subs are found
        # even when codec/releasegroup differs. Priority:
        #   1. Title + year:    "28.Years.Later.2025"
        #   2. Title + episode: "Game.of.Thrones.S01E01"
        #   3. Fallback:        full basename (original behaviour)
        $titlePrefix = if ($videoName -match '^(.+?\.\d{4})\.') {
            $matches[1]
        } elseif ($videoName -match '^(.+?\.S\d{2}E\d{2})[\.\s]') {
            $matches[1]
        } else {
            $videoName
        }

        # Find subtitles for this specific video (exclude already synced ones)
        # Match on title prefix so manually downloaded subs with different codec/group names are found
        $videoSubs = @(Get-ChildItem -LiteralPath $videoDir -File -Filter "*.srt" | Where-Object { 
            $_.Name -like "$titlePrefix*.srt" -and
            $_.Name -notmatch '\.alass\.synced\.srt$' -and 
            $_.Name -notmatch '\.ffsubsync\.synced\.srt$' -and
            $_.Name -notmatch '\.synced\.'
        })

        # Filter to only subtitles in the target language
        if ($Global:Lang) {
            $videoSubs = @($videoSubs | Where-Object {
                (Get-SubtitleLanguage $_.Name) -eq $Global:Lang
            })
        }

        if ($videoSubs.Count -eq 0) {
            # Geen doeltaal-sub: pre-sync fallback-taal sub als vertaling actief is,
            # zodat Step_08b de gesyncde versie kan vertalen (timestamps al correct).
            $translateMode = if ($Global:TranslateMode) { $Global:TranslateMode.ToLower() } else { "fallback" }
            $canPreSync = ($translateMode -ne "off") -and $Global:LangFallback -and $Global:TranslatorExe -and (Test-Path $Global:TranslatorExe)
            if ($canPreSync) {
                $fallbackLang = if ($Global:LangFallback -is [string]) { $Global:LangFallback.ToLower() } else { $Global:LangFallback[0].ToLower() }
                $fbCandidates = @(Get-ChildItem -LiteralPath $videoDir -File -Filter "*.srt" -ErrorAction SilentlyContinue | Where-Object {
                    $_.Name -like "$titlePrefix*.srt" -and
                    $_.Name -notmatch '\.synced\.' -and
                    $_.Name -notmatch '\.translated\.srt$' -and
                    (Get-SubtitleLanguage $_.Name) -eq $fallbackLang
                })
                if ($fbCandidates.Count -gt 0) {
                    $fbSub = $fbCandidates[0]
                    Show-Format "PRE-SYNC" "$($fbSub.Name)" "Sync brontaal ($fallbackLang) voor vertaling" -NameColor "DarkCyan"
                    $syncResult = Invoke-SyncChain -VideoPath $videoPath -SubtitleInfo @{
                        Name     = $fbSub.Name
                        Path     = $fbSub.FullName
                        Language = $fallbackLang
                    } -VideoDir $videoDir
                    if ($syncResult) {
                        Show-Format "PRE-SYNC" "$([System.IO.Path]::GetFileName($syncResult.Path))" "Geslaagd via $($syncResult.Chain)" -NameColor "Green"
                        $syncSuccess++
                    } else {
                        Show-Format "PRE-SYNC" "$($fbSub.Name)" "Mislukt, 08b gebruikt originele timing" -NameColor "Yellow"
                        $syncFailed++
                        $syncFailedItems += "$videoName :: $($fbSub.Name)"
                    }
                } else {
                    Show-Format "SKIP" "$videoName" "Geen sub gevonden (ook geen $fallbackLang voor vertaling)" -NameColor "Yellow"
                }
            } else {
                Show-Format "SKIP" "$videoName" "No subtitles found" -NameColor "Yellow"
            }
            continue
        }

        # Sorteer kandidaten op kwaliteit en kies de beste voor sync/embed
        $videoSubs = @($videoSubs | Sort-Object -Property @{ Expression = { Score-Subtitle -filePath $_.FullName -language (Get-SubtitleLanguage $_.Name) }; Descending = $true })
        if ($videoSubs.Count -gt 1) {
            Show-Format "SELECT" "$videoName" "Best subtitle: $($videoSubs[0].Name)" -NameColor "Green"
            $videoSubs = @($videoSubs[0])
        }

        DrawBar "*"
        Show-Format "PROCESS" "$videoName" "$($videoSubs.Count) subtitles"

        # Process each subtitle
        foreach ($sub in $videoSubs) {
            $subPath = $sub.FullName
            $subName = $sub.Name

            # Check if sync is needed
            $needsSync = Test-SubtitleNeedsSync -VideoPath $videoPath -SubtitlePath $subPath -VideoName $videoName

            if ($needsSync) {
                
                # Show separator between subtitles if there are multiple
                if ($videoSubs.Count -gt 1) {
                    Show-Format "DEBUG" "Trying ALASS + FFSubSync chain" "" -NameColor "Cyan"
                }

                $syncResult = Invoke-SyncChain -VideoPath $videoPath -SubtitleInfo @{
                    Name = $subName
                    Path = $subPath
                    Language = "unknown"
                } -VideoDir $videoDir
                
                if ($syncResult -and (Test-SyncedSubtitleLooksSafe -OriginalPath $subPath -CandidatePath $syncResult.Path)) {
                    Show-Format "SYNC" "$subName" "$($syncResult.Chain) sync successful" -NameColor "Green"
                    $syncSuccess++
                    
                    # Update metadata to use the synced subtitle
                    Update-SubtitleMetadata -VideoBaseName $videoName -SyncedSubtitlePath $syncResult.Path -OriginalSubtitleName $subName -SyncChain $syncResult.Chain
                } else {
                    if ($syncResult) {
                        Show-Format "WARNING" "$subName" "Sync result rejected: subtitle starts too late or looks incomplete" -NameColor "Yellow"
                    } else {
                        Show-Format "SYNC" "$subName" "Sync failed — using original" -NameColor "Yellow"
                    }
                    $syncFailed++
                    $syncFailedItems += "$videoName :: $subName"
                    # Fall back to original subtitle so Step 09 can still embed it
                    Update-SubtitleMetadata -VideoBaseName $videoName -SyncedSubtitlePath $subPath -OriginalSubtitleName $subName -SyncChain "Original"
                }
            } else {
                Show-Format "SKIP" "$subName" "Sync not needed" -NameColor "Cyan"
                $syncSuccess++
                # Still write metadata so Step 09 can embed the subtitle
                Update-SubtitleMetadata -VideoBaseName $videoName -SyncedSubtitlePath $subPath -OriginalSubtitleName $subName
            }
            
            # Add separator between subtitles if there are multiple
            if ($videoSubs.Count -gt 1 -and $sub -ne $videoSubs[-1]) {
                DrawBar "*"
            }
        }
    }

    Set-StepRunResult -Step "10" -Success $syncSuccess -Failed $syncFailed -FailedItems $syncFailedItems -Note "subtitle sync stage"
}

function Test-SubtitleNeedsSync {
    param(
        [string]$VideoPath,
        [string]$SubtitlePath,
        [string]$VideoName
    )

    # Volg alleen SyncMode dropdown: 'always' = altijd syncen, 'none' = nooit syncen
    $syncMode = if ($Global:SyncMode) { $Global:SyncMode.ToLower() } else { "always" }
    if ($syncMode -eq "always") {
        return $true
    }
    if ($syncMode -eq "none") {
        return $false
    }
    # Als het niet always of none is, sync dan toch (voor compatibiliteit)
    return $true
}

function Test-TrueValue {
    param($Value)

    if ($null -eq $Value) { return $false }
    return @('1', 'true', 'yes', 'on') -contains "$Value".Trim().ToLower()
}

function Convert-SrtTimeToMs {
    param([string]$Timecode)

    if (-not $Timecode -or $Timecode -notmatch '^(\d{2}):(\d{2}):(\d{2}),(\d{3})$') {
        return $null
    }

    return (([int]$matches[1] * 3600 + [int]$matches[2] * 60 + [int]$matches[3]) * 1000 + [int]$matches[4])
}

function Get-SubtitleTimingInfo {
    param([string]$SubtitlePath)

    if (-not (Test-Path -LiteralPath $SubtitlePath)) {
        return $null
    }

    $pattern = '(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})'
    $matchesFound = [regex]::Matches((Get-Content -LiteralPath $SubtitlePath -Raw -ErrorAction SilentlyContinue), $pattern)
    if (-not $matchesFound -or $matchesFound.Count -eq 0) {
        return $null
    }

    $firstStart = Convert-SrtTimeToMs -Timecode $matchesFound[0].Groups[1].Value
    $lastEnd = Convert-SrtTimeToMs -Timecode $matchesFound[$matchesFound.Count - 1].Groups[2].Value

    return @{
        CueCount = $matchesFound.Count
        FirstStartMs = $firstStart
        LastEndMs = $lastEnd
    }
}

function Test-SyncedSubtitleLooksSafe {
    param(
        [string]$OriginalPath,
        [string]$CandidatePath
    )

    $original = Get-SubtitleTimingInfo -SubtitlePath $OriginalPath
    $candidate = Get-SubtitleTimingInfo -SubtitlePath $CandidatePath

    if (-not $original -or -not $candidate) {
        return $true
    }

    $minimumCueCount = [Math]::Max(10, [int][Math]::Floor($original.CueCount * 0.6))
    if ($candidate.CueCount -lt $minimumCueCount) {
        return $false
    }

    $shiftMs = $candidate.FirstStartMs - $original.FirstStartMs
    if ($original.FirstStartMs -lt 300000 -and $candidate.FirstStartMs -gt 900000 -and $shiftMs -gt 600000) {
        return $false
    }

    return $true
}

function Invoke-SyncChain {
    param(
        [string]$VideoPath,
        [hashtable]$SubtitleInfo,
        [string]$VideoDir
    )

    $syncSteps = @()
    $workingPath = $SubtitleInfo.Path
    $workingName = $SubtitleInfo.Name

    $alassResult = Sync-WithAlass -VideoPath $VideoPath -SubtitleInfo $SubtitleInfo -VideoDir $VideoDir
    if ($alassResult) {
        $workingPath = $alassResult
        $workingName = [System.IO.Path]::GetFileName($alassResult)
        $syncSteps += 'ALASS'
    }

    $ffsubsyncResult = Sync-WithFFSubSync -VideoPath $VideoPath -SubtitleInfo @{
        Name = $workingName
        Path = $workingPath
        Language = $SubtitleInfo.Language
    } -VideoDir $VideoDir

    if ($ffsubsyncResult) {
        $syncSteps += 'FFSubSync'
        return @{
            Path = $ffsubsyncResult
            Chain = ($syncSteps -join ' + ')
        }
    }

    if ($alassResult) {
        return @{
            Path = $alassResult
            Chain = 'ALASS'
        }
    }

    return $null
}

function Sync-WithAlass {
    param(
        [string]$VideoPath,
        [hashtable]$SubtitleInfo,
        [string]$VideoDir
    )
    $alassExe = if ($Global:AlassExe -and (Test-Path $Global:AlassExe)) { $Global:AlassExe } else { Join-Path $PSScriptRoot 'alass.exe' }
    if (-not (Test-Path $alassExe)) {
        return $null
    }
    $syncOutput = Join-Path $VideoDir "$([System.IO.Path]::GetFileNameWithoutExtension($SubtitleInfo.Name)).alass.synced.srt"
    $args = @(
        "`"$VideoPath`"",
        "`"$($SubtitleInfo.Path)`"",
        "`"$syncOutput`""
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $alassExe
    $psi.Arguments = $args -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()
    $proc.WaitForExit()
    if ($proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $syncOutput)) {
        return $syncOutput
    }
    return $null
}

function Sync-WithFFSubSync {
    param(
        [string]$VideoPath,
        [hashtable]$SubtitleInfo,
        [string]$VideoDir
    )
    $ffsubsyncExe = if ($Global:FFSubSyncExe -and (Test-Path $Global:FFSubSyncExe)) { $Global:FFSubSyncExe } else { Join-Path $PSScriptRoot 'ffsubsync.exe' }
    if (-not (Test-Path $ffsubsyncExe)) {
        Show-Format "SKIP SYNC" "$($SubtitleInfo.Name)" "ffsubsync.exe niet gevonden: $ffsubsyncExe" -NameColor "Yellow"
        return $false
    }
    $syncOutput = Join-Path $VideoDir "$([System.IO.Path]::GetFileNameWithoutExtension($SubtitleInfo.Name)).ffsubsync.synced.srt"

    $args = @(
        "`"$VideoPath`"",
        "-i", "`"$($SubtitleInfo.Path)`"",
        "-o", "`"$syncOutput`""
    )

    if ($Global:FFSubSyncMaxSubtitleSeconds) {
        $args += @("--max-subtitle-seconds", "$($Global:FFSubSyncMaxSubtitleSeconds)")
    }
    if ($Global:FFSubSyncStartSeconds -and "$($Global:FFSubSyncStartSeconds)" -ne '0') {
        $args += @("--start-seconds", "$($Global:FFSubSyncStartSeconds)")
    }
    if ($Global:FFSubSyncMaxOffset) {
        $args += @("--max-offset-seconds", "$($Global:FFSubSyncMaxOffset)")
    } else {
        $args += @("--max-offset-seconds", "600")
    }
    if ($Global:FFSubSyncVAD) {
        $args += @("--vad", "$($Global:FFSubSyncVAD)")
    }
    if ($Global:FFSubSyncFrameRate) {
        $args += @("--frame-rate", "$($Global:FFSubSyncFrameRate)")
    }
    if (Test-TrueValue $Global:FFSubSyncNoFixFramerate) {
        $args += "--no-fix-framerate"
    }
    if ($Global:FFSubSyncEncoding) {
        $args += @("--encoding", "$($Global:FFSubSyncEncoding)")
    }
    if ($Global:FFSubSyncOutputEncoding) {
        $args += @("--output-encoding", "$($Global:FFSubSyncOutputEncoding)")
    }
    if ($Global:FFmpegExe -and (Test-Path $Global:FFmpegExe)) {
        $args += @("--ffmpeg-path", "`"$([System.IO.Path]::GetDirectoryName($Global:FFmpegExe))`"")
    }
    if ($Global:LogDir -and (Test-Path $Global:LogDir)) {
        $args += @("--log-dir-path", "`"$Global:LogDir`"")
    }

    $commandLine = "`"$ffsubsyncExe`" " + ($args -join ' ')
    Write-Host "[CMD Test] $commandLine" -ForegroundColor Magenta
    if (Test-TrueValue $Global:SyncDebug) {
        Show-Format "DEBUG" "FFSubSync args" ($args -join ' ') -NameColor "DarkGray"
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ffsubsyncExe
    $psi.Arguments = $args -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()
    $proc.WaitForExit()

    if ($proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $syncOutput)) {
        return $syncOutput
    } else {
        Show-Format "DEBUG" "FFSubSync output file not found or exit code != 0" "" -NameColor "Red"
        return $null
    }
}

function Update-SubtitleMetadata {
    param(
        [string]$VideoBaseName,
        [string]$SyncedSubtitlePath,
        [string]$OriginalSubtitleName,
        [string]$SyncChain = "FFSubSync"
    )
    
    $metaDir = $Global:MetaDir
    if (-not (Test-Path $metaDir)) {
        New-Item -ItemType Directory -Path $metaDir -Force | Out-Null
    }
    
    $metaFile = Join-Path $metaDir "$VideoBaseName.meta.json"
    
    # Extract language from synced subtitle filename
    $syncedFileName = [System.IO.Path]::GetFileName($SyncedSubtitlePath)
    $extractedLang = Get-SubtitleLanguage $syncedFileName
    
    # Create or load metadata
    if (Test-Path -LiteralPath $metaFile) {
        $existingMeta = Get-Content -LiteralPath $metaFile | ConvertFrom-Json
        # Convert to hashtable for modification
        $meta = @{
            VideoName = $existingMeta.VideoName
            SourceFolder = $existingMeta.SourceFolder
            SubtitleFile = $existingMeta.SubtitleFile
            SubtitlePath = $existingMeta.SubtitlePath
            Language = $existingMeta.Language
            Score = $existingMeta.Score
        }
    } else {
        # Create basic metadata structure
        $meta = @{
            VideoName = $VideoBaseName
            SourceFolder = ""
            SubtitleFile = [System.IO.Path]::GetFileName($SyncedSubtitlePath)
            SubtitlePath = $SyncedSubtitlePath
            Language = $extractedLang
            Score = 0
        }
    }
    
    # Update the subtitle path to the synced version
    $meta.SubtitlePath = $SyncedSubtitlePath
    $meta.SubtitleFile = [System.IO.Path]::GetFileName($SyncedSubtitlePath)
    
    # Update language if it was extracted from the filename (and is valid)
    if ($extractedLang -and $extractedLang -ne "unknown") {
        $meta.Language = $extractedLang
    }
    
    # Add sync info
    $meta | Add-Member -MemberType NoteProperty -Name "SyncedFrom" -Value $OriginalSubtitleName -Force
    $meta | Add-Member -MemberType NoteProperty -Name "SyncChain" -Value $SyncChain -Force
    
    $meta | ConvertTo-Json | Set-Content -LiteralPath $metaFile -Force
    Show-Format "UPDATE" "$VideoBaseName" "Metadata updated with synced subtitle" -NameColor "Green"
}

function Start-Sync {
    Start-StepLog -StepNumber "10" -StepName "Sync_Subs"
    Sync-AndScore
    Stop-StepLog
}