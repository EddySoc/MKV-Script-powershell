# Zet spaties in bestands- en mapnamen om naar punten (recursief)
function Convert-TreeSpacesToDots {
    param([string]$Root)
    # Eerst submappen, dan bestanden, dan deze map zelf
    Get-ChildItem -Path $Root -Recurse -Directory | Sort-Object -Property FullName -Descending | ForEach-Object {
        $safeName = $_.Name -replace ' ', '.'
        if ($_.Name -ne $safeName) {
            $newPath = Join-Path ($_.Parent.FullName) $safeName
            if (-not (Test-Path $newPath)) {
                Rename-Item -LiteralPath $_.FullName -NewName $safeName
            }
        }
    }
    Get-ChildItem -Path $Root -Recurse -File | ForEach-Object {
        $safeName = $_.Name -replace ' ', '.'
        if ($_.Name -ne $safeName) {
            $newPath = Join-Path ($_.Directory.FullName) $safeName
            if (-not (Test-Path $newPath)) {
                Rename-Item -LiteralPath $_.FullName -NewName $safeName
            }
        }
    }
    # Rootmap zelf
    $rootObj = Get-Item -LiteralPath $Root
    $safeRoot = $rootObj.Name -replace ' ', '.'
    if ($rootObj.Name -ne $safeRoot) {
        $parent = Split-Path $rootObj.FullName -Parent
        $newRoot = Join-Path $parent $safeRoot
        if (-not (Test-Path $newRoot)) {
            Rename-Item -LiteralPath $rootObj.FullName -NewName $safeRoot
        }
    }
}
# ─── Bescherm tegen herhaald laden ─────────────────────────────────────
if ($Global:InitialisationLoaded) { return }
$Global:InitialisationLoaded = $true

# ─── Module: Initialisation.ps1 ───────────────────────────────────────
# Doel: voert een specifieke taak uit binnen de pipeline
# Aanroep: via hoofdscript dat Config.ps1 en Utils.ps1 al heeft geladen

# ─── FUNCTIONS ──────────────────────────────────────────────────────────
function Init-Folders {
    param ([string[]]$Folders)
    Show-Format "CREATE" "Folders..." -NameColor "Yellow"
    foreach ($folder in $Folders) {
        if (-not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder | Out-Null
            Show-Format "PROCESS" "$folder" "" "✅" -NameColor "Cyan"
        } else {
            Show-Format "EXISTS" "$folder" "" "✅" -NameColor "DarkGray"
        }
    }
}



function Delete-UnwantedSubtitles {
    param (
        [string]$SourceDir,
        [string[]]$LangList
    )

    Show-Format "CLEAN" "Removing unwanted subtitles..." -NameColor Yellow
    Get-ChildItem -Path $SourceDir -Recurse -Filter *.srt | ForEach-Object {
        $keep = $false
        foreach ($lang in $LangList) {
            if ($_.Name -match $lang) {
                $keep = $true
                break
            }
        }
        if (-not $keep) {
            Show-Format "DELETE" "$($_.Name)" "" "❌" -NameColor "Red"
            Remove-Item $_.FullName
        } else {
            Show-Format "KEEP" "$($_.Name)" "" "✅"
        }
    }
}

function Delete-UnwantedFiles {
    param (
        [string]$SourceDir,
        [string[]]$Extensions
    )

    Show-Format "CLEAN" "Removing unwanted files..." -NameColor Yellow

    foreach ($ext in $Extensions) {
        $files = Get-ChildItem -Path $SourceDir -Recurse -Filter $ext -File
        if ($files.Count -gt 0) {
            Show-Format "PROCESS" "*.$ext" "$($files.Count) file(s) found" "🗑"
            $files | Remove-Item -Force
        } else {
            Show-Format "SKIP" "*.$ext" "No files found" "⏭"
        }
    }

    Show-Format "CLEAN" "Unwanted file cleanup complete." -NameColor Green
}

function Delete-OldFormatSubtitles {
    # DEPRECATED: No longer delete from SourceDir
    # SourceDir should remain intact for re-runs if needed
    Show-Format "SKIP" "Old format subtitle deletion disabled" "SourceDir must stay intact" -NameColor "Yellow"
}


function CleanFolders {
    # Build list of protected folders based on configuration
    $protectedFolders = @(
        [System.IO.Path]::GetFullPath($SourceDir),
        [System.IO.Path]::GetFullPath($MediaDir)
    )
    
    # Build preservation message
    $preserveMsg = "SourceDir, MediaDir"
    
    # Add LogDir to protected list only if LogHistory=keep
    if ($Global:LogHistory -eq "keep") {
        $protectedFolders += [System.IO.Path]::GetFullPath($LogDir)
        $preserveMsg += ", LogDir"
    }
    
    # Add DoneDir to protected list only if Originals=keep
    if ($Global:Originals -eq "keep") {
        $protectedFolders += [System.IO.Path]::GetFullPath($DoneDir)
        $preserveMsg += ", DoneDir"
    }
    
    Show-Format "REMOVE" "Temporary folders only" "Preserve: $preserveMsg" -NameColor "Yellow"

    Get-ChildItem -Path $RootDir -Directory | Where-Object {
        $currentPath = [System.IO.Path]::GetFullPath($_.FullName)
        $protectedFolders -notcontains $currentPath
    } | ForEach-Object {        
        try {
            Remove-Item -Path $_.FullName -Recurse -Force
            Write-Progress -Activity "Removing" -Completed  # Clear progress bar
            Show-Format "REMOVED" "$($_.Name)" "" -NameColor "Red" 
        } catch {
            Write-Progress -Activity "Removing" -Completed  # Clear progress bar
            Show-Format "FAILED" "$($_.Name)" "" -NameColor "Red" 
        }
    }
}

Function Initialize {
# ─── EXECUTION ORDER ────────────────────────────────────────────────────
DrawBanner "STEP 01 INIT FOLDERS"
Write-Progress -Activity "Initializing" -Completed  # Clear any lingering progress
CleanFolders

Init-Folders @(
    $SourceDir,
    $MediaDir, "$MediaDir\Series", "$MediaDir\Movies",
    $TempDir, $LogDir, $RejectDir, $DoneDir
)

# Zet direct na aanmaken folders alles in TempDir om naar punten
if (Test-Path $TempDir) {
    Convert-TreeSpacesToDots $TempDir
    # Update globale variabelen naar nieuwe (punt-)namen
    $TempDir = $TempDir -replace ' ', '.'
    $MediaDir = $MediaDir -replace ' ', '.'
    $SourceDir = $SourceDir -replace ' ', '.'
    $LogDir = $LogDir -replace ' ', '.'
    $RejectDir = $RejectDir -replace ' ', '.'
    $DoneDir = $DoneDir -replace ' ', '.'
}

$env:LangList = Expand-LangKeep -LangKeep $LangKeep -LangMap $LangMap

# Do NOT modify filenames - keep original names throughout
# Do NOT delete from SourceDir - keep it intact for re-runs
Delete-UnwantedFiles     -SourceDir $SourceDir -Extensions $DeleteExt

# ___ END ________________________________________________________________

}

# ─── Begin taakcode ────────────────────────────────────────────────────
function Start-Init {
    Start-StepLog -StepNumber "01" -StepName "Init_Folders"
    Initialize
    Stop-StepLog
}

