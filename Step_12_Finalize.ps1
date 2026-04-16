# ______ Bescherm tegen herhaald laden __________________________________________________________________________________
if ($Global:FinalizeLoaded) { return }
$Global:FinalizeLoaded = $true

# ______ Module: Finalize.ps1 ___________________________________________________________________________________________
# Doel: Verwijder alle werkdirectories na succesvolle verwerking
# Files zijn al verplaatst naar MediaDir via Embed_All.ps1
# Aanroep: via hoofdscript dat Config.ps1 en Utils.ps1 al heeft geladen

# Load config if not already loaded (for standalone execution)
if (-not $Global:ConfigLoaded) {
    . (Join-Path $PSScriptRoot "Step_0A_Load_Config.ps1")
}


function Cleanup-WorkingDirectories {
    DrawBanner -Text "CLEANING UP WORKING DIRECTORIES"
    
    # Clear any lingering progress display
    Write-Progress -Activity "Cleanup" -Completed

    # Check config settings for folder cleanup
    $tempFolderAction = if ($Global:TempFolder) { $Global:TempFolder.ToLower() } else { "remove" }
    $mediaFolderAction = if ($Global:MediaFolder) { $Global:MediaFolder.ToLower() } else { "keep" }
    $metadataFolderAction = if ($Global:MetadataFolder) { $Global:MetadataFolder.ToLower() } else { "remove" }
    $rejectedAction = if ($Global:Rejected) { $Global:Rejected.ToLower() } else { "keep" }

    # Build list of folders to remove based on config
    $foldersToRemove = @()
    
    # MediaDir is NEVER removed - contains finished processed videos
    
    # TempDir: only remove if TempFolder=remove
    if ($Global:TempDir -and $tempFolderAction -eq "remove") {
        $foldersToRemove += $Global:TempDir
    }
    
    # MetaDir: only remove if DEBUGMode is false AND MetadataFolder=remove
    if ($Global:MetaDir -and -not $Global:DEBUGMode -and $metadataFolderAction -eq "remove") {
        $foldersToRemove += $Global:MetaDir
    }

    # RejectDir: remove only when Rejected=remove
    if ($Global:RejectDir -and $rejectedAction -eq "remove") {
        $foldersToRemove += $Global:RejectDir
    }

    # Collect log entries BEFORE deleting directories
    $logEntries = @("Finalize Cleanup Log - $(Get-Date)", "======================================", "")
    
    # Log preserved folders
    if ($tempFolderAction -eq "keep") {
        Show-Format "PRESERVED" "TempDir" "$($Global:TempDir) (TempFolder=keep)" -NameColor "Cyan"
        $logEntries += "PRESERVED: TempDir - $($Global:TempDir) (TempFolder=keep)"
    }
    if ($rejectedAction -eq "remove") {
        Show-Format "CLEANUP" "RejectDir" "$($Global:RejectDir) (Rejected=remove)" -NameColor "Yellow"
        $logEntries += "CLEANUP: RejectDir - $($Global:RejectDir) (Rejected=remove)"
    } else {
        Show-Format "PROTECTED" "RejectDir" "$($Global:RejectDir) (Rejected=keep)" -NameColor "Cyan"
        $logEntries += "PROTECTED: RejectDir - $($Global:RejectDir) (Rejected=keep)"
    }
    # MediaDir is always preserved - contains finished videos
    if ($mediaFolderAction -eq "remove") {
        Show-Format "PROTECTED" "MediaDir" "$($Global:MediaDir) (MediaFolder=remove genegeerd - bevat afgewerkte videos!)" -NameColor "Yellow"
        $logEntries += "PROTECTED: MediaDir - $($Global:MediaDir) (remove genegeerd - bevat afgewerkte videos)"
    } else {
        Show-Format "PROTECTED" "MediaDir" "$($Global:MediaDir) (bevat afgewerkte videos)" -NameColor "Cyan"
        $logEntries += "PROTECTED: MediaDir - $($Global:MediaDir) (bevat afgewerkte videos)"
    }
    if ($metadataFolderAction -eq "keep" -or $Global:DEBUGMode) {
        $reason = if ($Global:DEBUGMode) { "DEBUGMode=true" } else { "MetadataFolder=keep" }
        Show-Format "PRESERVED" "MetaDir" "$($Global:MetaDir) ($reason)" -NameColor "Cyan"
        $logEntries += "PRESERVED: MetaDir - $($Global:MetaDir) ($reason)"
    }
    $logEntries += ""

    foreach ($folder in $foldersToRemove) {
        if (-not $folder) {
            Show-Format "SKIP" "Folder not defined" "$folder" -NameColor "Yellow"
            $logEntries += "SKIP: Folder not defined - $folder"
            continue
        }

        if (Test-Path -LiteralPath $folder) {
            try {
                Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction Stop
                Write-Progress -Activity "Removing" -Completed  # Clear progress bar
                Show-Format "REMOVED" "$folder" "" -NameColor "Green"
                $logEntries += "REMOVED: $folder"
            } catch {
                Write-Progress -Activity "Removing" -Completed  # Clear progress bar
                Show-Format "ERROR" "Failed to remove $folder $_" "" -NameColor "Red"
                $logEntries += "ERROR: Failed to remove $folder - $_"
            }
        } else {
            Show-Format "SKIP" "Does not exist" "$folder" -NameColor "DarkGray"
            $logEntries += "SKIP: Does not exist - $folder"
        }
    }

    # Remove processed source folders (only if Originals=remove and no video files remain)
    $originalsAction = if ($Global:Originals) { $Global:Originals.ToLower() } else { "keep" }
    
    if ($Global:ProcessedSourceFolders -and $originalsAction -eq "remove") {
        DrawBanner -Text "STEP 12 CLEANING UP SOURCE FOLDERS"
        Write-Progress -Activity "Cleanup" -Completed  # Clear progress bar
        
        # Get normalized SourceDir path for comparison
        $normalizedSourceDir = [System.IO.Path]::GetFullPath($Global:SourceDir)
        
        foreach ($sourceFolder in $Global:ProcessedSourceFolders) {
            if ($sourceFolder -and (Test-Path -LiteralPath $sourceFolder)) {
                # NEVER remove the SourceDir itself (when files are directly in SourceDir, not in subfolders)
                $normalizedSource = [System.IO.Path]::GetFullPath($sourceFolder)
                if ($normalizedSource -eq $normalizedSourceDir) {
                    Show-Format "PROTECTED" "SourceDir" "⚠️ SourceDir preserved (files directly in SourceDir were processed individually)" -NameColor "Cyan"
                    $logEntries += "PROTECTED: SourceDir preserved - $sourceFolder"
                    continue
                }
                
                try {
                    # Check for remaining video files only
                    $videoExts = @(".mkv", ".mp4", ".avi", ".mov", ".wmv", ".flv", ".webm")
                    $remainingVideoFiles = Get-ChildItem -LiteralPath $sourceFolder -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                        $videoExts -contains $_.Extension.ToLower()
                    }
                    
                    if ($remainingVideoFiles.Count -eq 0) {
                        # No video files left, remove the entire folder
                        Remove-Item -LiteralPath $sourceFolder -Recurse -Force -ErrorAction Stop
                        Write-Progress -Activity "Removing" -Completed  # Clear progress bar
                        Show-Format "REMOVED" "$(Split-Path $sourceFolder -Leaf)" "✅ no videos left" -NameColor "Green"
                        $logEntries += "REMOVED FOLDER: $sourceFolder (all videos processed)"
                    } else {
                        Show-Format "SKIP" "$(Split-Path $sourceFolder -Leaf)" "⚠️ contains $($remainingVideoFiles.Count) video file(s)" -NameColor "Yellow"
                        $logEntries += "SKIP FOLDER: $sourceFolder (contains $($remainingVideoFiles.Count) video files)"
                    }
                } catch {
                    Show-Format "ERROR" "Failed to remove $sourceFolder $_" "" -NameColor "Red"
                    $logEntries += "ERROR: Failed to remove $sourceFolder - $_"
                }
            }
        }
    } elseif ($Global:ProcessedSourceFolders) {
        Show-Format "INFO" "Source folders preserved (Originals=keep)" "Folders should be in \Done if moved by Step 09" -NameColor "Cyan"
        $logEntries += "INFO: Source folders preserved due to Originals=keep setting"
    } else {
        Show-Format "SKIP" "No processed source folders to clean" "" -NameColor "DarkGray"
        $logEntries += "SKIP: No processed source folders to clean"
    }

    # Clean up empty folders in SourceDir (Downloads)
    if ($Global:SourceDir -and (Test-Path $Global:SourceDir)) {
        DrawBanner -Text "REMOVING EMPTY FOLDERS FROM DOWNLOADS"
        
        # Get normalized SourceDir path to protect it
        $normalizedSourceDir = [System.IO.Path]::GetFullPath($Global:SourceDir)
        
        $emptyFolders = @()
        # Find all directories, deepest first
        Get-ChildItem -Path $Global:SourceDir -Directory -Recurse | Sort-Object {$_.FullName.Length} -Descending | ForEach-Object {
            $folder = $_
            $normalizedFolder = [System.IO.Path]::GetFullPath($folder.FullName)
            
            # NEVER remove SourceDir itself, only subdirectories
            if ($normalizedFolder -eq $normalizedSourceDir) {
                return
            }
            
            # Check if folder is empty (no files and no subdirectories)
            $items = Get-ChildItem -LiteralPath $folder.FullName -Force -ErrorAction SilentlyContinue
            if ($items.Count -eq 0) {
                $emptyFolders += $folder
            }
        }
        
        if ($emptyFolders.Count -gt 0) {
            Show-Format "INFO" "Found $($emptyFolders.Count) empty folder(s)" "" -NameColor "Cyan"
            $logEntries += "EMPTY FOLDERS FOUND: $($emptyFolders.Count)"
            
            foreach ($emptyFolder in $emptyFolders) {
                try {
                    Remove-Item -LiteralPath $emptyFolder.FullName -Force -ErrorAction Stop
                    Show-Format "REMOVED" "$($emptyFolder.Name)" "empty folder" -NameColor "Green"
                    $logEntries += "REMOVED EMPTY: $($emptyFolder.FullName)"
                } catch {
                    Show-Format "ERROR" "Failed to remove empty folder" "$($emptyFolder.Name): $_" -NameColor "Red"
                    $logEntries += "ERROR REMOVING EMPTY: $($emptyFolder.FullName) - $_"
                }
            }
        } else {
            Show-Format "INFO" "No empty folders found" "" -NameColor "DarkGray"
            $logEntries += "No empty folders found in SourceDir"
        }
    }

    $logEntries += ""
    $logEntries += "Cleanup completed: $(Get-Date)"
    $logEntries += ""
    $logEntries += "PRESERVED DIRECTORIES:"
    $logEntries += "  - SourceDir: $($Global:SourceDir)"
    $logEntries += "  - MediaDir: $($Global:MediaDir)"
    $logEntries += "  - LogDir: $($Global:LogDir)"

    # Write log to file (LogDir is preserved)
    if (Test-Path $Global:LogDir) {
        try {
            $logPath = Join-Path $Global:LogDir "finalize.log"
            Set-Content $logPath ($logEntries -join "`n")
        } catch {
            # If log write fails, just continue - cleanup already happened
        }
    }
}

function Start-Finalize {
    Start-StepLog -StepNumber "12" -StepName "Finalize"
    Cleanup-WorkingDirectories
    Stop-StepLog
}

