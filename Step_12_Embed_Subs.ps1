# ─── Bescherm tegen herhaald laden ─────────────────────────────────────
if ($Global:EmbedAllLoaded) { return }
$Global:EmbedAllLoaded = $true

function Get-VideoType {
    param ([string]$videoName)
    
    # Detect if video is series (has S##E## or ##x## pattern) or movie (has year)
    if ($videoName -match 'S\d{2}E\d{2}' -or $videoName -match '\d+x\d{2}') {
        return "Series"
    } elseif ($videoName -match '\d{4}') {
        return "Movies"
    }
    return "Unknown"
}

function Rename-ForFinal {
    param (
        [string]$baseName,
        [string]$videoType
    )
    
    # Clean filename by removing quality tags and release info
    $cleanName = $baseName
    
    # For series: Normalize episode format from ##x## to S##E## (e.g., 1x01 -> S01E01)
    if ($videoType -eq "Series" -and $cleanName -match '^(.+?[\.\ s])((\d+)x(\d{2}))') {
        $seasonNum = $matches[3].PadLeft(2, '0')
        $episodeNum = $matches[4]
        # Replace ##x## with S##E##
        $cleanName = $cleanName -replace "^(.+?[\.\s])(\d+x\d{2})", "`${1}S${seasonNum}E${episodeNum}"
    }
    
    # Remove common quality and release tags
    $cleanName = $cleanName -replace '\.(720p|1080p|2160p|4K|HD|UHD|SDR|HDR|HDR10|DV|DoVi).*$', ''
    $cleanName = $cleanName -replace '\.(BluRay|BRRip|BDRip|WEB-DL|WEBRip|WEB|AMZN|NF|DSNP|HMAX|ATVP|PMTP).*$', ''
    $cleanName = $cleanName -replace '\.(x264|x265|H264|H265|HEVC|AVC|10bit|8bit).*$', ''
    $cleanName = $cleanName -replace '\.(AAC|AC3|DDP|DDP5\.1|DTS|TrueHD|Atmos|DD5\.1).*$', ''
    $cleanName = $cleanName -replace '\[.*?\]', ''  # Remove [brackets]
    $cleanName = $cleanName -replace '\((?!.*\d{4})\).*$', ''  # Remove (parentheses) but keep (year)
    
    # For series: strip episode title - everything after S##E## code
    # Must happen AFTER quality tag removal to also catch episode titles without quality tags
    if ($videoType -eq "Series") {
        $cleanName = $cleanName -replace '(S\d{2}E\d{2})[\.\ s\-].*$', '$1'
    }
    
    # Clean up multiple dots and trailing dots
    $cleanName = $cleanName -replace '\.+', '.'
    $cleanName = $cleanName.TrimEnd('.')
    
    # Veiligheidscheck: als cleanName leeg is, gebruik originele naam
    if ([string]::IsNullOrWhiteSpace($cleanName)) {
        $cleanName = $baseName
    }
    
    return $cleanName
}

function Embed-Subtitle {
    param (
        [string]$mkvPath,
        [string]$srtPath,
        [string]$language
    )
    
    $mkvBase = [System.IO.Path]::GetFileNameWithoutExtension($mkvPath)
    $mkvDir = Split-Path $mkvPath -Parent
    $tempMkv = Join-Path $mkvDir "$mkvBase.embedded.mkv"
    $logFile = [System.IO.Path]::GetTempFileName()  # Use temp file instead of Logs dir with special chars
    
    # Validate and correct language code
    $validLanguages = @('dut', 'nld', 'ned', 'eng', 'en', 'fra', 'fr', 'deu', 'ger', 'spa', 'es', 'por', 'pt', 'ita', 'it', 'pol', 'pl', 'swe', 'sv', 'nor', 'no', 'dan', 'da', 'fin', 'fi', 'est', 'et', 'lav', 'lv', 'lit', 'lt', 'cze', 'cs', 'slv', 'sl', 'slk', 'sk', 'rus', 'ru', 'ukr', 'uk', 'bul', 'bg', 'gre', 'el', 'tur', 'tr', 'ara', 'ar', 'heb', 'he', 'hin', 'hi', 'jpn', 'ja', 'kor', 'ko', 'chi', 'zh', 'vie', 'vi', 'may', 'ms', 'msa', 'ind', 'id', 'tam', 'ta', 'tel', 'te', 'tha', 'th')
    
    if ([string]::IsNullOrWhiteSpace($language) -or $language -eq 'und' -or -not $validLanguages.Contains($language.ToLower())) {
        # Use primary language from config as fallback
        $primaryLang = if ($Global:LangKeep -and $Global:LangKeep.Count -gt 0) { $Global:LangKeep[0] } else { 'dut' }
        Show-Format "WARNING" "$mkvBase" "Invalid language '$language', using '$primaryLang' instead" -NameColor "Yellow"
        $language = $primaryLang
    }
    
    # FFmpeg command to embed subtitle via cmd.exe for proper argument handling
    # -map 0:v -map 0:a: kopieer video en audio, maar GEEN bestaande subtitle tracks
    # -map 1: voeg enkel de nieuwe srt toe (vervangt alle oude embedded subs)
    $ffCmd = "ffmpeg -i `"$mkvPath`" -i `"$srtPath`" -map 0:v -map 0:a -map 1 -c copy -c:s:0 srt -disposition:s:0 default -metadata:s:s:0 language=$language -y `"$tempMkv`""
    
    try {
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $ffCmd -NoNewWindow -PassThru -Wait -RedirectStandardError $logFile
        
        if ($proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $tempMkv)) {
            Remove-Item -LiteralPath $mkvPath -Force
            Rename-Item -LiteralPath $tempMkv -NewName "$mkvBase.mkv" -Force
            Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
            return $true
        } else {
            Show-Format "ERROR" "$mkvBase" "Embed failed (exit code: $($proc.ExitCode))" -NameColor "Red"
            if (Test-Path -LiteralPath $tempMkv) { Remove-Item -LiteralPath $tempMkv -Force }
            Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
            return $false
        }
    } catch {
        Show-Format "ERROR" "$mkvBase" "FFmpeg error: $_" -NameColor "Red"
        if (Test-Path -LiteralPath $tempMkv) { Remove-Item -LiteralPath $tempMkv -Force }
        Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Sync-PostEmbed {
    param (
        [string]$mkvPath,
        [string]$srtPath,
        [string]$videoName
    )
    
    $mkvDir = Split-Path $mkvPath -Parent
    $mkvBase = [System.IO.Path]::GetFileNameWithoutExtension($mkvPath)
    $postEmbedSrt = Join-Path $mkvDir "$mkvBase.postembed.synced.srt"
    
    # Use FFSubSync to re-sync against the embedded video
    $ffsubsyncExe = if ($Global:FFSubSyncExe -and (Test-Path $Global:FFSubSyncExe)) { $Global:FFSubSyncExe } else { Join-Path $PSScriptRoot 'ffsubsync.exe' }
    if (-not (Test-Path $ffsubsyncExe)) {
        Show-Format "SKIP RESYNC" "$videoName" "ffsubsync.exe niet gevonden" -NameColor "Yellow"
        return $null
    }
    
    # Force ffsubsync to use audio only, not embedded subtitles
    $commandLine = "`"$ffsubsyncExe`" `"$mkvPath`" -i `"$srtPath`" -o `"$postEmbedSrt`" --no-fix-framerate"
    Write-Host "[CMD Test] $commandLine" -ForegroundColor Magenta
    
    $args = @(
        "`"$mkvPath`"",
        "-i", "`"$srtPath`"",
        "-o", "`"$postEmbedSrt`"",
        "--no-fix-framerate"
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ffsubsyncExe
    $psi.Arguments = $args -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false  # Toon venster zodat progressbar zichtbaar is
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()
    $proc.WaitForExit()
    
    if ($proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $postEmbedSrt)) {
        Show-Format "RESYNC" "$videoName" "Post-embed sync successful" -NameColor "Green"
        return $postEmbedSrt
    } else {
        Show-Format "RESYNC" "$videoName" "Post-embed sync failed (exit code: $($proc.ExitCode))" -NameColor "Yellow"
        return $null
    }
}

function Embed-All {
    DrawBanner "STEP 12 EMBED SUBTITLES"

    $metaDir = $Global:MetaDir
    $logPath = Join-Path $LogDir "embed_all.log"
    
    Set-Content -Path $logPath -Value "VideoName`tSubtitle`tEmbedStatus`tMoveStatus"
    
    $stats = @{
        TOTAL = 0
        EMBEDDED = 0
        MOVED = 0
        FAILED = 0
    }
    $failedItems = @()
    
    $metaFilesToProcess = @()
    
    # Process each video
    Get-ChildItem -LiteralPath $TempDir -Recurse -Filter *.mkv | ForEach-Object {
        $mkvFile = $_
        $mkvName = $mkvFile.Name
        $mkvBase = $mkvFile.BaseName
        $mkvPath = $mkvFile.FullName
        $mkvDir = $mkvFile.DirectoryName
        
        $stats.TOTAL++
        
        # Read metadata
        $metaFile = Join-Path $metaDir "$mkvBase.meta.json"
        
        if (-not (Test-Path -LiteralPath $metaFile)) {
            Show-Format "SKIP" "$mkvName" "No metadata found" -NameColor "Yellow"
            Add-Content -Path $logPath -Value "$mkvBase`t-`tSKIPPED`tN/A"
            return
        }
        
        $meta = Get-Content -LiteralPath $metaFile | ConvertFrom-Json
        
        # Check if subtitle info exists
        if (-not $meta.SubtitleFile) {
            Show-Format "SKIP" "$mkvName" "No subtitle selected" -NameColor "Yellow"
            Add-Content -Path $logPath -Value "$mkvBase`t-`tSKIPPED`tN/A"
            return
        }
        $subPath = $meta.SubtitlePath
        $subLang = $meta.Language
        
        # If language is empty or invalid, extract from subtitle filename
        if ([string]::IsNullOrWhiteSpace($subLang) -or $subLang -eq "unknown") {
            $subLang = Get-SubtitleLanguage $meta.SubtitleFile
            if ($Global:DEBUGMode) {
                Show-Format "DEBUG" "Extracted language from filename" "$($meta.SubtitleFile) → $subLang" -NameColor "DarkGray"
            }
            
            # Update metadata with extracted language
            $meta.Language = $subLang
            $meta | ConvertTo-Json | Set-Content -LiteralPath $metaFile -Force
        }
        
        Show-Format "EMBED" "$mkvName" "with $($meta.SubtitleFile)"
        
        # Embed subtitle
        $embedOK = Embed-Subtitle -mkvPath $mkvPath -srtPath $subPath -language $subLang
        
        if ($embedOK) {
            Show-Format "EMBED OK" "$mkvName" "Subtitle embedded" -NameColor "Green"
            $stats.EMBEDDED++
            $embedStatus = "OK"
            
            # Update metadata with embed status - create new hashtable with all properties
            $updatedMeta = @{
                VideoName = $meta.VideoName
                SourceFolder = $meta.SourceFolder
                SubtitleFile = $meta.SubtitleFile
                SubtitlePath = $meta.SubtitlePath
                Language = $meta.Language
                Score = $meta.Score
                EmbedStatus = "OK"
            }
            $updatedMeta | ConvertTo-Json | Set-Content -LiteralPath $metaFile -Force
            
            # Delete external subtitle file (it's now embedded)
            if (Test-Path -LiteralPath $subPath) {
                Remove-Item -LiteralPath $subPath -Force
            }
            
            # Delete all other .srt files for this video
            Get-ChildItem -LiteralPath $mkvDir -File -Filter "*.srt" | Where-Object {
                $_.Name -like "$mkvBase*.srt"
            } | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force
            }
        } else {
            Show-Format "ERROR" "$mkvName" "Embed failed" -NameColor "Red"
            $stats.FAILED++
            $failedItems += $mkvName
            $embedStatus = "FAILED"
            return
        }
        
        # Determine destination and clean filename
        $videoType = Get-VideoType -videoName $mkvBase
        $cleanMkvBase = Rename-ForFinal -baseName $mkvBase -videoType $videoType
        $cleanMkvName = "$cleanMkvBase.mkv"
        
        if ($videoType -eq "Series") {
            # Extract series name and season from filename
            # Pattern: Show.Name.S##E## or Show Name S##E## or Show.Name.1x01
            if ($mkvBase -match '^(.+?)[\s\.]S(\d{2})E\d{2}') {
                # Standard S##E## format
                $seriesName = $matches[1] -replace '\.', ' '  # Convert dots to spaces
                $seriesName = $seriesName.Trim()  # Remove extra whitespace
                $seasonNum = $matches[2]
                $seasonFolder = "S$seasonNum"
                
                # Create: Series\ShowName\S##\
                $destDir = Join-Path $MediaDir "Series"
                $destDir = Join-Path $destDir $seriesName
                $destDir = Join-Path $destDir $seasonFolder
            } elseif ($mkvBase -match '^(.+?)[\s\.](\d+)x\d{2}') {
                # Alternative ##x## format (e.g., 1x01, 2x03)
                $seriesName = $matches[1] -replace '\.', ' '  # Convert dots to spaces
                $seriesName = $seriesName.Trim()  # Remove extra whitespace
                $seasonNum = $matches[2].PadLeft(2, '0')  # Ensure 2-digit season
                $seasonFolder = "S$seasonNum"
                
                # Create: Series\ShowName\S##\
                $destDir = Join-Path $MediaDir "Series"
                $destDir = Join-Path $destDir $seriesName
                $destDir = Join-Path $destDir $seasonFolder
            } else {
                # Fallback if pattern doesn't match
                $destDir = Join-Path $MediaDir "Series"
            }
        } else {
            $destDir = Join-Path $MediaDir "Movies"
        }
        
        # Create directory structure recursively if it doesn't exist
        if (-not (Test-Path $destDir)) {
            try {
                New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop | Out-Null
            } catch {
                Show-Format "ERROR" "Failed to create directory: $destDir" "$_" -NameColor "Red"
                return
            }
        }
        
        # Kopieer naar de definitieve locatie met schone naam
        $finalPath = Join-Path $destDir $cleanMkvName
        
        try {
            # Voor series, controleer op duplicaat in de root Series map (van eerdere runs met platte structuur)
            if ($videoType -eq "Series" -and $destDir -notmatch '\\Series$' -and -not [string]::IsNullOrWhiteSpace($cleanMkvName)) {
                $rootSeriesPath = Join-Path (Join-Path $MediaDir "Series") $cleanMkvName
                # Extra veiligheidscheck: mag geen directory zijn en niet de Series folder zelf
                if ((Test-Path -LiteralPath $rootSeriesPath -PathType Leaf) -and ($rootSeriesPath -ne $finalPath)) {
                    Remove-Item -LiteralPath $rootSeriesPath -Force
                    Show-Format "CLEANUP" "$cleanMkvName" "Duplicaat uit root Series map verwijderd" -NameColor "Yellow"
                }
            }
            
            # If destination exists with same clean name, remove it first to avoid duplicates
            if ((Test-Path -LiteralPath $finalPath) -and ($mkvName -ne $cleanMkvName)) {
                Remove-Item -LiteralPath $finalPath -Force
                Show-Format "REPLACE" "$cleanMkvName" "Removing old version in destination" -NameColor "Yellow"
            }
            
            # Ensure parent directory exists before copying
            $parentDir = Split-Path -Parent $finalPath
            if (-not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            
            # Kopieer (niet verplaatsen) zodat temp folder intact blijft voor verificatie
            Copy-Item -LiteralPath $mkvPath -Destination $finalPath -Force
            if ($mkvName -ne $cleanMkvName) {
                Show-Format "COPY" "$mkvName → $cleanMkvName" "→ $videoType" -NameColor "Green"
            } else {
                Show-Format "COPY" "$mkvName" "→ $videoType" -NameColor "Green"
            }
            $stats.MOVED++
            $moveStatus = "OK"
        } catch {
            Show-Format "ERROR" "$mkvName" "Copy failed: $_" -NameColor "Red"
            $stats.FAILED++
            $failedItems += $mkvName
            $moveStatus = "FAILED"
        }
        DrawBar "*"
        Add-Content -Path $logPath -Value "$mkvBase`t$($meta.SubtitleFile)`t$embedStatus`t$moveStatus"
    }
    
    # Process source folders: read all metadata files and handle those with EmbedStatus=OK
    DrawBanner "PROCESS SOURCE FOLDERS"
    $originalsAction = $Global:Originals
    $tempFolderAction = if ($Global:TempFolder) { $Global:TempFolder.ToLower() } else { "remove" }
    
    Show-Format "DEBUG" "Originals setting" "$originalsAction" -NameColor "Cyan"
    Show-Format "DEBUG" "TempFolder setting" "$tempFolderAction" -NameColor "Cyan"
    
    if (-not $originalsAction -or ($originalsAction -ne "keep" -and $originalsAction -ne "remove")) {
        Show-Format "WARNING" "Originals setting invalid" "Use 'keep' or 'remove' (current: $originalsAction)" -NameColor "Yellow"
        return
    }
    
    # Collect all metadata files with successful embeds
    $allMetaFiles = Get-ChildItem -LiteralPath $metaDir -Filter "*.meta.json" -File -ErrorAction SilentlyContinue
    Show-Format "DEBUG" "Found metadata files" "$($allMetaFiles.Count) meta.json files" -NameColor "Cyan"
    
    $successfulEmbeds = @()
    $sourceFoldersToProcess = @()
    
    foreach ($metaFile in $allMetaFiles) {
        try {
            $meta = Get-Content -LiteralPath $metaFile.FullName | ConvertFrom-Json
            Show-Format "DEBUG" "Checking $($metaFile.Name)" "EmbedStatus=$($meta.EmbedStatus), HasSourceFolder=$($null -ne $meta.SourceFolder)" -NameColor "DarkGray"
            
            if ($meta.EmbedStatus -eq "OK" -and $meta.SourceFolder) {
                $successfulEmbeds += $meta
                if ($sourceFoldersToProcess -notcontains $meta.SourceFolder) {
                    $sourceFoldersToProcess += $meta.SourceFolder
                    Show-Format "DEBUG" "Added source folder" "$($meta.SourceFolder)" -NameColor "DarkGray"
                }
            }
        } catch {
            Show-Format "WARNING" "Failed to read metadata" "$($metaFile.Name): $_" -NameColor "Yellow"
        }
    }
    
    if ($sourceFoldersToProcess.Count -eq 0) {
        Show-Format "INFO" "No source folders to process" "All embeds may have failed or no SourceFolder in metadata" -NameColor "Yellow"
        return
    }
    
    Show-Format "INFO" "Found $($successfulEmbeds.Count) successful embed(s)" "Processing $($sourceFoldersToProcess.Count) unique source folder(s)" -NameColor "Cyan"
    
    if ($originalsAction -eq "keep") {
        # Move source folders to Done
        $DoneDir = Join-Path $RootDir "Done"
        if (-not (Test-Path $DoneDir)) {
            New-Item -ItemType Directory -Path $DoneDir -Force | Out-Null
        }
        
        # Get normalized SourceDir path for comparison
        $normalizedSourceDir = [System.IO.Path]::GetFullPath($Global:SourceDir)
        
        foreach ($sourceFolder in $sourceFoldersToProcess) {
            if (Test-Path -LiteralPath $sourceFolder) {
                # NEVER move/remove the SourceDir itself (when files are directly in SourceDir, not in subfolders)
                $normalizedSource = [System.IO.Path]::GetFullPath($sourceFolder)
                if ($normalizedSource -eq $normalizedSourceDir) {
                    Show-Format "PROTECTED" "SourceDir" "SourceDir preserved (files directly in SourceDir were processed individually)" -NameColor "Cyan"
                    continue
                }
                
                try {
                    # Preserve relative path structure from SourceDir
                    $relativePath = $sourceFolder.Substring($Global:SourceDir.Length).TrimStart('\', '/')
                    $donePath = Join-Path $DoneDir $relativePath
                    
                    # Create parent directory structure in Done if needed
                    $doneParent = Split-Path $donePath -Parent
                    if (-not (Test-Path $doneParent)) {
                        New-Item -ItemType Directory -Path $doneParent -Force | Out-Null
                    }
                    
                    # Als doelmap al bestaat, verwijder deze eerst
                    if (Test-Path -LiteralPath $donePath) {
                        Remove-Item -LiteralPath $donePath -Recurse -Force
                    }
                    
                    Move-Item -LiteralPath $sourceFolder -Destination $donePath -Force
                    Show-Format "MOVE" "$relativePath" "→ Done/ (originals kept)" -NameColor "Cyan"
                } catch {
                    Show-Format "ERROR" "Failed to move $relativePath to Done" "$_" -NameColor "Red"
                }
            } else {
                Show-Format "WARNING" "Source folder not found" "$sourceFolder" -NameColor "Yellow"
            }
        }
    } elseif ($originalsAction -eq "remove") {
        # Get normalized SourceDir path for comparison
        $normalizedSourceDir = [System.IO.Path]::GetFullPath($Global:SourceDir)
        
        # Delete source folders
        foreach ($sourceFolder in $sourceFoldersToProcess) {
            if (Test-Path -LiteralPath $sourceFolder) {
                # NEVER remove the SourceDir itself (when files are directly in SourceDir, not in subfolders)
                $normalizedSource = [System.IO.Path]::GetFullPath($sourceFolder)
                if ($normalizedSource -eq $normalizedSourceDir) {
                    Show-Format "PROTECTED" "SourceDir" "SourceDir preserved (files directly in SourceDir were processed individually)" -NameColor "Cyan"
                    continue
                }
                
                try {
                    $folderName = Split-Path $sourceFolder -Leaf
                    Remove-Item -LiteralPath $sourceFolder -Recurse -Force
                    Show-Format "DELETE" "$folderName" "Originals removed" -NameColor "DarkGray"
                } catch {
                    Show-Format "ERROR" "Failed to delete $folderName" "$_" -NameColor "Red"
                }
            } else {
                Show-Format "WARNING" "Source folder not found" "$sourceFolder" -NameColor "Yellow"
            }
        }
    }
    
    # Ruim temp folder op als TempFolder=remove
    if ($tempFolderAction -eq "remove") {
        DrawBanner "CLEANUP TEMP FOLDER"
        $tempDir = $Global:TempDir
        
        if (Test-Path -LiteralPath $tempDir) {
            try {
                # Verwijder alle subdirectories in temp (maar niet temp zelf)
                Get-ChildItem -LiteralPath $tempDir -Directory | ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force
                    Show-Format "CLEANUP" "Temp/$($_.Name)" "Verwijderd" -NameColor "DarkGray"
                }
                
                # Verwijder losse bestanden in temp root
                Get-ChildItem -LiteralPath $tempDir -File | ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Force
                    Show-Format "CLEANUP" "Temp/$($_.Name)" "Verwijderd" -NameColor "DarkGray"
                }
                
                Show-Format "CLEANUP" "Temp folder" "Opgeruimd" -NameColor "Green"
            } catch {
                Show-Format "ERROR" "Failed to cleanup temp folder" "$_" -NameColor "Red"
            }
        }
    } else {
        Show-Format "KEEP" "Temp folder" "Behouden voor verificatie" -NameColor "Cyan"
    }
    
    Show-Format "SUMMARY" "Embed & Move complete" "Total=$($stats.TOTAL), Embedded=$($stats.EMBEDDED), Moved=$($stats.MOVED), Failed=$($stats.FAILED)" -NameColor "Yellow"
    Set-StepRunResult -Step "12" -Success $stats.EMBEDDED -Failed $stats.FAILED -FailedItems $failedItems -Note "moved=$($stats.MOVED), total=$($stats.TOTAL)"
}

# ─── Begin taakcode ────────────────────────────────────────────────────
function Start-Embed {
    Start-StepLog -StepNumber "12" -StepName "Embed_Subs"
    Embed-All
    Stop-StepLog
}
