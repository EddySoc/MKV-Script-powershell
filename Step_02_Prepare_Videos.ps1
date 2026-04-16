# ___ Bescherm tegen herhaald laden _____________________________________
if ($Global:PrepareVideosLoaded) { return }
$Global:PrepareVideosLoaded = $true

# ___ Helper: verwijder lege mappen ______________________________________
function Remove-EmptyParentDirs {
    param ([string]$startDir, [string]$stopAt)
    $current = Get-Item $startDir
    while ($current.FullName -ne $stopAt -and (Test-Path $current.FullName)) {
        if ((Get-ChildItem -Path $current.FullName -Force).Count -eq 0) {
            Remove-Item -Path $current.FullName -Force
            $current = $current.Parent
        } else {
            break
        }
    }
}

# ___ Stap 1: Copy/Transform ALL videos _____________________________________
function Copy-And-Transform {
    DrawBanner -Text "STEP 02 PREPARE VIDEOS & SUBTITLES"

    if (-not $SourceDir -or -not $TempDir) {
        Show-Format "ERROR" "SourceDir or TempDir not set in environment" "" -NameColor "Red"
        exit 1
    }

    $videoExts = @(".mkv", ".mp4", ".avi", ".mov", ".wmv", ".flv", ".webm")
    $sourceRoot = (Resolve-Path $SourceDir).Path

    # Collect all videos
    $allVideos = @()
    
    # Suppress automatic progress from Get-ChildItem
    $ProgressPreference = 'SilentlyContinue'
    Get-ChildItem -Path $sourceRoot -Recurse -File | ForEach-Object {
        if ($videoExts -contains $_.Extension.ToLower() -and $_.DirectoryName -notmatch '\\_temp($|\\)') {
            $allVideos += $_
        }
    }
    
    if ($allVideos.Count -eq 0) {
        Show-Format "WARNING" "No videos found in $sourceRoot" "" -NameColor "Yellow"
        return
    }

    # Use global metadata directory
    $metaDir = $Global:MetaDir
    if (-not (Test-Path $metaDir)) {
        New-Item -ItemType Directory -Path $metaDir -Force | Out-Null
    }
    
    # Process each video
    foreach ($vidFile in $allVideos) {
        $src = $vidFile.FullName
        $baseName = Sanitize-PathName $vidFile.BaseName  # Remove brackets from filename
        $ext = $vidFile.Extension.ToLower()
        
        # Get original source folder (direct parent of video file)
        $originalSourceFolder = $vidFile.DirectoryName
        
        # Get relative path from source root and sanitize folder names only
        $relPath = $src.Substring($sourceRoot.Length).TrimStart('\\')
        $relDir = [System.IO.Path]::GetDirectoryName($relPath)
        
        # Show-Format "DEBUG" "Video: $baseName$ext" "relPath: '$relPath' | relDir: '$relDir'" -NameColor "Yellow"
        
        # Sanitize folder names in path but keep directory structure
        if ($relDir) {
            $pathParts = $relDir -split '\\'
            # Show-Format "DEBUG" "Path parts" "Count: $($pathParts.Count) | Parts: $($pathParts -join ' | ')" -NameColor "Yellow"
            $sanitizedParts = @($pathParts | ForEach-Object { Sanitize-PathName $_ })
            # Show-Format "DEBUG" "Sanitized parts" "Count: $($sanitizedParts.Count) | Parts: $($sanitizedParts -join ' | ')" -NameColor "Yellow"
            $sanitizedRelDir = $sanitizedParts -join '\'
            # Show-Format "DEBUG" "Sanitized relDir" "'$sanitizedRelDir' | Length: $($sanitizedRelDir.Length)" -NameColor "Yellow"
        } else {
            $sanitizedRelDir = ""
        }
        
        $targetVidDir = if ($sanitizedRelDir) { Join-Path $TempDir $sanitizedRelDir } else { $TempDir }
        $targetFile = Join-Path $targetVidDir "$baseName.mkv"

        # Show-Format "DEBUG" "Target" "Dir: $targetVidDir | File: $baseName.mkv" -NameColor "Magenta"

        # Create target directory - MUST exist before copying/converting
        if (-not (Test-Path -LiteralPath $targetVidDir)) {
            try {
                New-Item -ItemType Directory -Path $targetVidDir -Force -ErrorAction Stop | Out-Null
                Show-Format "CREATE DIR" "$targetVidDir" -NameColor "Cyan"
            } catch {
                Show-Format "ERROR" "Failed to create directory: $_" "$targetVidDir" -NameColor "Red"
                continue
            }
        }

        # Save original source folder to metadata
        $metaFile = Join-Path $metaDir "$baseName.meta.json"
        @{
            VideoName = "$baseName.mkv"
            SourceFolder = $originalSourceFolder
        } | ConvertTo-Json | Set-Content -LiteralPath $metaFile -Force
        
        # Video: copy or convert
        if ($ext -eq ".mkv") {
            Show-Format "COPY" "$baseName$ext" "" -NameColor "Green"
            try {
                # Use ffmpeg to preserve all streams including unknown codecs
                # -map 0 ensures ALL streams are copied (video, audio, all subtitles)
                $verbosity = if ($DebugLevel -eq 0) { "quiet" } else { "error" }
                & ffmpeg -y -v $verbosity -i $src -map 0 -c copy $targetFile 2>&1 | Out-Null
                if (Test-Path -LiteralPath $targetFile) {
                    # Show-Format "OK" "MKV copied successfully" "" -NameColor "Green"                    
                } else {
                    Show-Format "ERROR" "MKV copy failed: file not found after copy - $baseName" "" -NameColor "Red"
                }
            } catch {
                Show-Format "ERROR" "Failed to copy MKV: $_ - $baseName" "" -NameColor "Red"
            }
        } else {
            Show-Format "CONVERT" "$baseName$ext → .mkv" "" -NameColor "Green"
            $verbosity = if ($DebugLevel -eq 0) { "quiet" } else { "error" }
            # Skip subtitles during conversion (will copy as separate .srt files)
            # For nested directories, use system temp to avoid path issues, then move
            $tempFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.mkv'
            $errorLog = [System.IO.Path]::GetTempFileName()
            $ffCmd = "ffmpeg -y -fflags +genpts -v error -i `"$src`" -c:v copy -c:a copy -sn `"$tempFile`" 2>`"$errorLog`""
            try {
                # Execute via cmd.exe to ensure proper argument parsing
                $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $ffCmd -NoNewWindow -PassThru -Wait
                if ($proc.ExitCode -eq 0 -and (Test-Path $tempFile)) {
                    Move-Item -Path $tempFile -Destination $targetFile -Force -ErrorAction SilentlyContinue
                    Remove-Item $errorLog -ErrorAction SilentlyContinue
                } elseif ($proc.ExitCode -ne 0) {
                    # Read error details
                    $errorDetails = ""
                    if (Test-Path $errorLog) {
                        $errorContent = Get-Content $errorLog -Raw -ErrorAction SilentlyContinue
                        $errorLines = $errorContent -split "`n" | Where-Object { $_ -match "error|Error|failed|Failed|Invalid|invalid" } | Select-Object -First 3
                        if ($errorLines) {
                            $errorDetails = " | " + ($errorLines -join " | ")
                        }
                    }
                    Show-Format "ERROR" "Conversion failed: $baseName$ext (exit code: $($proc.ExitCode))$errorDetails" "" -NameColor "Red"
                    if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
                    Remove-Item $errorLog -ErrorAction SilentlyContinue
                }
            } catch {
                Show-Format "ERROR" "FFmpeg error: $_" "" -NameColor "Red"
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
                Remove-Item $errorLog -ErrorAction SilentlyContinue
            }
        }
    }

    # Copy ALL .srt files to same folder structure in TempDir - NO MATCHING
    $subCount = 0
    Get-ChildItem -Path $sourceRoot -Recurse -Filter "*.srt" -File | ForEach-Object {
        $subPath = $_.FullName
        $subBaseName = Sanitize-PathName $_.BaseName  # Sanitize filename (remove brackets)
        $subName = "$subBaseName$($_.Extension)"

        # Remove existing language tags from filename to avoid double tagging
        $subName = $subName -replace '\.([a-z]{2,3})\.EXT\.srt$', '.srt'

        # Get relative path from source root and sanitize folder names only
        $relPath = $subPath.Substring($sourceRoot.Length).TrimStart('\')
        $relDir = [System.IO.Path]::GetDirectoryName($relPath)

        # Sanitize folder names in path but keep directory structure
        if ($relDir) {
            $pathParts = $relDir -split '\\'
            $sanitizedParts = @($pathParts | ForEach-Object { Sanitize-PathName $_ })
            $sanitizedRelDir = $sanitizedParts -join '\'
        } else {
            $sanitizedRelDir = ""
        }

        $targetSubDir = if ($sanitizedRelDir) { Join-Path $TempDir $sanitizedRelDir } else { $TempDir }
        $targetSubPath = Join-Path $targetSubDir $subName

        # Show-Format "DEBUG" "Sub: $subName" "Target: $targetSubDir" -NameColor "Cyan"

        if (-not (Test-Path -LiteralPath $targetSubDir)) {
            try {
                New-Item -ItemType Directory -Path $targetSubDir -Force -ErrorAction Stop | Out-Null
            } catch {
                Show-Format "ERROR" "Failed to create sub directory: $_" "$targetSubDir" -NameColor "Red"
                continue
            }
        }

        try {
            Copy-Item -LiteralPath $subPath -Destination $targetSubPath -Force
            if (Test-Path -LiteralPath $targetSubPath) {
                Show-Format "COPY SUB" $subName "" -NameColor "Cyan"
                $subCount++
            } else {
                Show-Format "ERROR" "Sub copied but not found: $subName" "" -NameColor "Red"
            }
        } catch {
            Show-Format "ERROR" "Failed to copy sub $subName - $_" "" -NameColor "Red"
        }
    }
    Show-Format "INFO" "Total subs copied: $subCount" "" -NameColor "Yellow"

    Write-Host ""
    DrawBanner -Text "LANGUAGE DETECTION FOR SUBTITLES"
    
    # Remove duplicate subtitles before language detection
    Show-Format "INFO" "Checking for duplicate subtitle files..." "" -NameColor "Cyan"
    $duplicatesRemoved = 0
    
    # Group subtitles by base name (removing language codes) to find duplicates
    Get-ChildItem -Path $TempDir -Recurse -Filter "*.srt" -File | Group-Object {
        $name = $_.BaseName
        # Remove language codes: .dut, .eng, .nld, etc.
        $name = $name -replace '\.(dut|eng|fra|nld|nl|en|fr)$', ''
        $name
    } | Where-Object { $_.Count -gt 1 } | ForEach-Object {
        $group = $_.Group
        # Keep the first file (usually the one with language tag), remove the rest
        $toKeep = $group | Where-Object { $_.Name -match '\.(dut|eng|fra|nld|nl|en|fr)\.' } | Select-Object -First 1
        if (-not $toKeep) {
            $toKeep = $group | Select-Object -First 1
        }
        
        $group | Where-Object { $_.FullName -ne $toKeep.FullName } | ForEach-Object {
            Show-Format "DUPLICATE" "$($_.Name)" "Removing (keeping $($toKeep.Name))" -NameColor "Yellow"
            Remove-Item -LiteralPath $_.FullName -Force
            $duplicatesRemoved++
        }
    }
    
    if ($duplicatesRemoved -gt 0) {
        Show-Format "INFO" "Removed $duplicatesRemoved duplicate subtitle file(s)" "" -NameColor "Yellow"
    }
    
    # Run checklang on all subtitles in TempDir
    if (Test-Path $CheckLangExe) {
        Show-Format "INFO" "Running language detection on all subtitles..." "" -NameColor "Cyan"
        try {
            $proc = Start-Process -FilePath $CheckLangExe -ArgumentList "`"$TempDir`"", "EXT" -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -ne 0) {
                Show-Format "WARNING" "Language detection completed with exit code $($proc.ExitCode)" "" -NameColor "Yellow"
            }
        } catch {
            Show-Format "WARNING" "Could not run checklang.exe: $_" "" -NameColor "Yellow"
        }
    } else {
        Show-Format "WARNING" "CheckLangExe not found at $CheckLangExe" "" -NameColor "Yellow"
    }

    Show-Format "COMPLETE" "Videos and subtitles prepared in TempDir" "" -NameColor "Yellow"
}

# ___ Wrapper ____________________________________________________________
function Rename-VideosWithFileBot {
    DrawBanner -Text "STEP 02b FILEBOT RENAME"

    if (-not (Get-Command filebot -ErrorAction SilentlyContinue)) {
        Show-Format "SKIP" "FileBot niet gevonden in PATH" "Rename stap overgeslagen" -NameColor "Yellow"
        return
    }

    $tempDir = $Global:TempDir
    $metaDir = $Global:MetaDir

    # Bouw het format-string op uit de geconfigureerde MFormat/SFormat
    # SFormat bevat een pad zoals {n}.{y}/S{s.pad(2)}/{n} S{s00e00} — neem alleen het laatste deel (bestandsnaam)
    $sFormatFile = if ($Global:SFormat) {
        (($Global:SFormat -split '/') | Select-Object -Last 1).Trim()
    } else { '{n} S{s00e00}' }

    $mFormatFile = if ($Global:MFormat) { $Global:MFormat } else { '{n}.{y}' }

    # Gecombineerd FileBot Groovy-formaat: series krijgt episode-nummer, films krijgen jaar
    $combinedFormat = "{if (episode) $sFormatFile else $mFormatFile}"
    Show-Format "CONFIG" "FileBot format: $combinedFormat" "" -NameColor "Cyan"

    try {
        # --action test: hernoem NIET, geef alleen voorgestelde namen terug
        $fbArgs = @('-rename', $tempDir, '--format', $combinedFormat, '--action', 'test', '-non-strict', '-r')
        $fbOutput = & filebot $fbArgs 2>&1

        # Parseer output: "Rename [oudepad] to [nieuwepad]" (FileBot 4.x/5.x formaat)
        $renameMap = @{}
        foreach ($line in $fbOutput) {
            if ($line -match 'Rename \[([^\[\]]+\.mkv)\] to \[([^\[\]]+\.mkv)\]') {
                $renameMap[$matches[1]] = $matches[2]
            }
        }

        if ($renameMap.Count -eq 0) {
            Show-Format "INFO" "FileBot: geen hernoemingen voorgesteld" "Bestanden behouden originele naam" -NameColor "DarkGray"
            return
        }

        Show-Format "INFO" "FileBot stelt $($renameMap.Count) hernoeming(en) voor" "" -NameColor "Yellow"

        foreach ($oldPath in $renameMap.Keys) {
            $newPath  = $renameMap[$oldPath]
            $oldBase  = [IO.Path]::GetFileNameWithoutExtension($oldPath)
            $newBase  = [IO.Path]::GetFileNameWithoutExtension($newPath)

            if ($oldBase -eq $newBase) { continue }

            Show-Format "RENAME" $oldBase "→ $newBase" -NameColor "Green"

            # Hernoem video-bestand
            if (Test-Path -LiteralPath $oldPath) {
                Move-Item -LiteralPath $oldPath -Destination $newPath -Force
            }

            # Hernoem bijbehorende meta.json en update VideoName veld
            $oldMeta = Join-Path $metaDir "$oldBase.meta.json"
            $newMeta = Join-Path $metaDir "$newBase.meta.json"
            if (Test-Path -LiteralPath $oldMeta) {
                try {
                    $meta = Get-Content -LiteralPath $oldMeta -Raw | ConvertFrom-Json
                    $metaHash = @{}
                    $meta.PSObject.Properties | ForEach-Object { $metaHash[$_.Name] = $_.Value }
                    $metaHash['VideoName'] = "$newBase.mkv"
                    $metaHash | ConvertTo-Json | Set-Content -LiteralPath $newMeta -Encoding UTF8 -Force
                    if ($oldMeta -ne $newMeta) { Remove-Item -LiteralPath $oldMeta -Force }
                } catch {
                    Show-Format "WARNING" "meta.json update mislukt voor $oldBase" "$_" -NameColor "Yellow"
                }
            }
        }

        Show-Format "COMPLETE" "FileBot rename afgerond" "" -NameColor "Green"

    } catch {
        Show-Format "WARNING" "FileBot rename mislukt: $_" "Verdergaan met originele namen" -NameColor "Yellow"
    }
}

function Start-Prep {
    Start-StepLog -StepNumber "02" -StepName "Prepare_Videos"
    Copy-And-Transform
    Rename-VideosWithFileBot
    Stop-StepLog
}

