# ─── Module: CheckDiskSpace.ps1 ───────────────────────────────────────
# Doel: Controleert vrije ruimte 
# Aanroep: via hoofdscript dat Config.ps1 en Utils.ps1 al heeft geladen

# ─── Bescherm tegen herhaald laden ─────────────────────────────────────
if ($Global:CheckDiskSpaceLoaded) { return }
$Global:CheckDiskSpaceLoaded = $true

Function CheckDisk{
# Bepalen DriveLetter
$driveLetter = $Global:RootDir.Substring(0,1)

# ───── Ophalen vrije ruimte ─────
$drive = Get-PSDrive -Name ($driveLetter.TrimEnd(':'))
$freeGB = [math]::Round($drive.Free / 1GB, 2)

# ───── Kleur bepalen ─────
$tag = "DISK CHECK"
if ($freeGB -gt $DrvMax) {
    $info   = "     !!! DiskSpace OK !!!    $DrvMax GB < DiskSpace"
    $color  = "Green"
    $status = "$freeGB GB Free"
} elseif ($freeGB -ge $DrvMin) {
    $info   = "     !!!   ATTENTION  !!!    $DrvMin GB < DiskSpace < $DrvMax GB"
    $color  = "Yellow"
    $status = "$freeGB GB Free"
} else {
    $info  = "     !!!   SPACE LOW   !!!    DiskSpace < $DrvMin GB"
    $color  = "Red"
    $status = "$freeGB GB Free"
}
# ───── Uitvoer ─────
Write-Host ""
DrawBar -Char "=" -Width $ScreenWidth -Color $Color
Show-Format "$tag" "$info" "$status" -NameColor "$color" -InfoColor "White"
DrawBar -Char "=" -Width $ScreenWidth -Color $Color
Write-Host ""
DrawBanner -Text "DONE" -Char "=" -Color "Cyan"
}

# ─── Begin taakcode ────────────────────────────────────────────────────
function Start-CheckDisk {
    Start-StepLog -StepNumber "14" -StepName "CheckDiskSpace"
    CheckDisk
    Show-StepRunSummary
    Stop-StepLog
}

