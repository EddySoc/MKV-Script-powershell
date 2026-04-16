# --- Bescherm tegen herhaald laden -------------------------------------
if ($Global:StoreAndStripLoaded) { return }
$Global:StoreAndStripLoaded = $true

# --- Module: StoreAndStrip.ps1 ---------------------------------------
# Doel: Extract alle subs uit de mkv (subs blijven in mkv voor betere sync-referentie)
# De subs worden uit de mkv verwijderd in Step_11 (Embed), net voor het embedden van de nieuwe subs
# Aanroep: via hoofdscript dat Config.ps1 en Utils.ps1 al heeft geladen

# --- Begin taakcode ----------------------------------------------------

# Extracted subtitles go directly in TempDir alongside videos (no separate SubsDir)

# ----- Audio Filter Function -----
function Filter-AudioTracks {
    param([string]$mkvFile)
    
    if (-not $Global:AudioFilterEnabled) {
        return $true
    }
    
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($mkvFile)
    $audioKeepList = if ($Global:AudioLangKeep) { @($Global:AudioLangKeep -split ',' | ForEach-Object { $_.Trim() }) } else { @() }
    
    if ($audioKeepList.Count -eq 0) {
        return $true  # No filter configured
    }
    
    # Get audio track info using ffprobe
    try {
        $ffprobeOutput = & $Global:FFprobeExe -v error -select_streams a -show_entries stream=index:stream_tags=language -of csv=p=0 "$mkvFile" 2>&1
        if ($LASTEXITCODE -ne 0 -or -not $ffprobeOutput) {
            Show-Format "WARNING" "Could not detect audio tracks" "$baseName" -NameColor "Yellow"
            return $true
        }
        
        $audioTracks = @()
        foreach ($line in $ffprobeOutput) {
            if ($line -match '^(\d+),(.*)$') {
                $audioTracks += @{
                    Index = [int]$matches[1]
                    Language = if ($matches[2]) { $matches[2].Trim() } else { "und" }
                }
            }
        }
        
        if ($audioTracks.Count -eq 0) {
            Show-Format "INFO" "No audio tracks found" "$baseName" -NameColor "DarkGray"
            return $true
        }
        
        # Find tracks to keep
        $tracksToKeep = @()
        foreach ($track in $audioTracks) {
            if ($audioKeepList -contains $track.Language) {
                $tracksToKeep += $track.Index
            }
        }
        
        # Fallback: keep first track if no match
        if ($tracksToKeep.Count -eq 0 -and $Global:AudioFallbackFirst) {
            $tracksToKeep += $audioTracks[0].Index
            Show-Format "AUDIO FILTER" "$baseName" "No match found, keeping first track ($($audioTracks[0].Language))" -NameColor "Yellow"
        } elseif ($tracksToKeep.Count -eq 0) {
            Show-Format "REJECT" "$baseName" "No matching audio language found" -NameColor "Red"
            return $false
        }
        
        # Check if filtering is needed
        if ($tracksToKeep.Count -eq $audioTracks.Count) {
            if ($Global:DEBUGMode) {
                Show-Format "AUDIO FILTER" "$baseName" "All tracks match, no filtering needed" -NameColor "Green"
            }
            return $true
        }
        
        # Build ffmpeg command to keep only selected audio tracks
        $tempFile = "$mkvFile.audiofiltered.mkv"
        $ffmpegArgs = @("-i", "$mkvFile", "-map", "0:v", "-map", "0:s?")
        foreach ($trackIndex in $tracksToKeep) {
            $ffmpegArgs += "-map"
            $ffmpegArgs += "0:$trackIndex"
        }
        $ffmpegArgs += "-c"
        $ffmpegArgs += "copy"
        $ffmpegArgs += "$tempFile"
        
        $removedCount = $audioTracks.Count - $tracksToKeep.Count
        $keptLangs = ($audioTracks | Where-Object { $tracksToKeep -contains $_.Index } | ForEach-Object { $_.Language }) -join ","
        Show-Format "AUDIO FILTER" "$baseName" "Keeping $($tracksToKeep.Count) track(s) [$keptLangs], removing $removedCount" -NameColor "Cyan"
        
        & ffmpeg -loglevel error @ffmpegArgs 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tempFile)) {
            Remove-Item -LiteralPath $mkvFile -Force
            Rename-Item -LiteralPath $tempFile -NewName ([System.IO.Path]::GetFileName($mkvFile)) -Force
            return $true
        } else {
            Show-Format "ERROR" "Audio filtering failed" "$baseName" -NameColor "Red"
            if (Test-Path -LiteralPath $tempFile) {
                Remove-Item -LiteralPath $tempFile -Force
            }
            return $true  # Continue anyway
        }
        
    } catch {
        Show-Format "ERROR" "Audio filter error" "$baseName : $_" -NameColor "Red"
        return $true  # Continue anyway
    }
}

# ----- Hoofdfunctie -----
function Process-Subtitles {
    $SubsExt = ".subs.txt"
    $FFmpeg  = "ffmpeg.exe"

    DrawBanner -Text "STEP 04 EXTRACT INTERNAL SUBS"
   
    Get-ChildItem -Path $Global:TempDir -Recurse -Filter *.mkv | ForEach-Object {
        $mkvFile   = $_.FullName
        $baseName  = $_.BaseName
        $fileDir   = Split-Path $mkvFile -Parent
        
        # Filter audio tracks first (before subtitle extraction)
        $audioFilterSuccess = Filter-AudioTracks -mkvFile $mkvFile
        if (-not $audioFilterSuccess) {
            Show-Format "SKIP" "$baseName" "Audio filtering failed" -NameColor "Red"
            return
        }

        # Read from centralized meta.json in MetaDir
        $metaJsonFile = Join-Path $Global:MetaDir "$baseName.meta.json"
        $subsFile = Join-Path $fileDir "$baseName$SubsExt"

        if ($Global:DEBUGMode) {
            Show-Format "DEBUG" "Looking for metadata" "json: $metaJsonFile" -NameColor "DarkGray"
            Show-Format "DEBUG" "File existence" "json exists: $(Test-Path -LiteralPath $metaJsonFile), subs exists: $(Test-Path -LiteralPath $subsFile)" -NameColor "DarkGray"
        }

        $SubCount = 0
        if (Test-Path -LiteralPath $metaJsonFile) {
            try {
                $meta = Get-Content -LiteralPath $metaJsonFile -Raw | ConvertFrom-Json
                $SubCount = $meta.SubCount
            } catch {
                Show-Format "ERROR" "Failed to read metadata JSON" "$metaJsonFile" -NameColor "Red"
            }
        } else {
            if ($Global:DEBUGMode) {
                Show-Format "DEBUG" "Meta JSON not found" "$metaJsonFile does not exist!" -NameColor "Red"
            }
        }

        if ($Global:DEBUGMode) {
            Show-Format "DEBUG" "$baseName" "SubCount=$SubCount, subsFile exists: $(Test-Path $subsFile)" -NameColor "DarkGray"
        }

        if ($SubCount -eq 0) {
            Show-Format "SKIP" "$baseName" "No subs" "" -NameColor "DarkGray"
            return
        }
        # Subs alway 2 digits
        $Info = "$($SubCount.ToString().PadLeft(2,'0')) subs"
        Show-Format "STORE" "$baseName" "$Info" -NameColor "Cyan"
        
        if (Test-Path -LiteralPath $subsFile) {
            $validLines = Get-Content -LiteralPath $subsFile | Where-Object { $_ -match '^\s*\d+\s*,\s*\w{2,3}\s*$' }

            foreach ($line in $validLines) {
                $parts = $line -split "," | ForEach-Object { $_.Trim() }

                $rawIndex = if ($parts.Count -ge 1 -and $parts[0]) { $parts[0] } else { "" }
                $lang     = if ($parts.Count -ge 2 -and $parts[1]) { $parts[1] } else { "und" }

                if (-not ($rawIndex -match "^\d+$")) {
                    Show-Format "WARNING" "Ongeldige regel: '$line' ? index niet geldig" "" -NameColor "Yellow"
                    continue
                }

                # Check if language is in LangKeep list
                $langList = Expand-LangKeep -LangKeep $Global:LangKeep -LangMap $Global:LangMap
                if ($langList -notcontains $lang) {
                    # Show-Format "SKIP" "$baseName.$lang (not in LangKeep)" "" -NameColor "DarkGray"
                    continue
                }

                $track    = [int]$rawIndex
                $trackPad = $track.ToString("D2")
                $rawSrt   = Join-Path $fileDir "$baseName.$lang.$trackPad.INT.srt"

                # Extract subtitle - ffmpeg will auto-convert WebVTT/ASS/etc to SRT
                # PowerShell automatically handles brackets when passing arguments
                $ffmpegOutput = & $FFmpeg -y -loglevel warning -i $mkvFile -map "0:$track" -c:s srt $rawSrt 2>&1
                
                if ($LASTEXITCODE -ne 0) {
                    if ($Global:DEBUGMode) {
                        Show-Format "ERROR" "ffmpeg failed for track $track" "$ffmpegOutput" -NameColor "Red"
                    } else {
                        Show-Format "ERROR" "ffmpeg fout bij $baseName (track $track)" "" -NameColor "Red"
                    }
                    continue
                }

                if (Test-Path $rawSrt) {
                    # File already has correct name, no need to rename
                    # Always Rewrite this line without CRLF
                    Write-ColoredSegments "[EXTRACT   ][  ] " "$baseName." "$lang.$trackPad" ".INT.srt" 
                } else {
                    Show-Format "WARNING" "Subs niet gevonden: $rawSrt" "" -NameColor "Red"
                }
            }
        }

        # Subs worden NIET meer gestript in Step_04 - ze blijven in de MKV zodat
        # FFSubSync/Alass ze kunnen gebruiken als referentie tijdens sync (Step_09/10).
        # De oude embedded subs worden pas verwijderd in Step_11 tijdens het embedden.
    }
}
# ----- Uitvoeren -----
function Start-Store {
    Start-StepLog -StepNumber "04" -StepName "Extract_Subs"
    Process-Subtitles
    Stop-StepLog
}
