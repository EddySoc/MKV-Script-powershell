param(
    [int]$Step
)

Clear-Host
$DebugPreference = "Continue"

# __________ Laad config _______________________________________________________________________________________________________________________
. (Join-Path $PSScriptRoot "Step_0A_Load_Config.ps1")

# __________ Wacht tot alles geladen is _______________________________________________________________________________________________________
$maxWait = 5
$elapsed = 0
while (-not $Global:ConfigLoaded -and $elapsed -lt $maxWait) {
    Start-Sleep -Milliseconds 100
    $elapsed += 0.1
}

# __________ Load pipeline scripts _____________________________________________________________________________________________________________________
if ($Global:ConfigLoaded) {
    # Load sync tools
    . (Join-Path $PSScriptRoot "Step_0C_Sync_Tools.ps1")
    
    # Load all pipeline scripts
    . (Join-Path $Global:ScriptDir "Step_01_Init_Folders.ps1")
    . (Join-Path $Global:ScriptDir "Step_02_Copy_And_Rename.ps1")
    . (Join-Path $Global:ScriptDir "Step_03_Get_Metadata.ps1")
    . (Join-Path $Global:ScriptDir "Step_04_Extract_Subs.ps1")
    . (Join-Path $Global:ScriptDir "Step_05_Download_Subs.ps1")
    . (Join-Path $Global:ScriptDir "Step_06_Speech_To_Text.ps1")
    . (Join-Path $Global:ScriptDir "Step_07_Validate_Subs.ps1")
    . (Join-Path $Global:ScriptDir "Step_08_Clean_Subs.ps1")
    . (Join-Path $Global:ScriptDir "Step_09_Score_Subs.ps1")
    . (Join-Path $Global:ScriptDir "Step_10_Sync_Subs.ps1")
    . (Join-Path $Global:ScriptDir "Step_11_Translate_Subs.ps1")
    . (Join-Path $Global:ScriptDir "Step_12_Embed_Subs.ps1")
    . (Join-Path $Global:ScriptDir "Step_13_Cleanup.ps1")
    . (Join-Path $Global:ScriptDir "Step_14_Check_Disk.ps1")
}

# Pipeline
if ($Global:ConfigLoaded) {
    # Start resource monitoring if enabled in config
    if ($Global:ResourceMonitoring) {
        $interval = if ($Global:MonitoringInterval) { $Global:MonitoringInterval } else { 30 }
        Start-ResourceMonitoring -IntervalSeconds $interval
    }
    
    # STEP 1: Initialize - clean folders, create structure
    if (-not $Step -or $Step -le 1) { Start-Init }
    
    # STEP 2: Prepare - copy videos, copy subs, run language detection
    if (-not $Step -or $Step -le 2) { Start-Prep }
    
    # STEP 3: Generate Metadata - extract video info, subtitle count, track numbers
    if (-not $Step -or $Step -le 3) { Start-GenMeta }
   
    # STEP 4: Store - extract internal subs, strip them from MKV
    if (-not $Step -or $Step -le 4) { Start-Store }
    
    # STEP 5: Download - download missing subs via FileBot
    if (-not $Step -or $Step -le 5) { Start-DownloadSubs }
    
    # STEP 6: STT - genereer sub via Whisper als er geen sub gevonden is
    if (-not $Step -or $Step -le 6) { Start-STT }

    # STEP 7: Validate - check subtitle format/quality
    if (-not $Step -or $Step -le 7) { Start-Validate }
    
    # STEP 8: Clean - clean subtitles (SDH removal, encoding fix)
    if (-not $Step -or $Step -le 8) { Start-CleanSubs }

    # STEP 9: Score - calculate subtitle quality scores
    if (-not $Step -or $Step -le 9) { Start-Score }
    
    # STEP 10: Sync & Select - sync bestaande subs + pre-sync brontaal voor vertaling
    if (-not $Step -or $Step -le 10) { Start-Sync }

    # STEP 11: Translate - vertaal de (gesyncde) brontaal-sub via Argos
    if (-not $Step -or $Step -le 11) { Start-TranslateSubs }
    
    # STEP 12: Embed - embed selected subtitles into MKV
    if (-not $Step -or $Step -le 12) { Start-Embed }
    
    # STEP 13: Finalize - optional post-processing
    if (-not $Step -or $Step -le 13) { Start-Finalize }
    
    # STEP 14: Check Disk - report final file sizes
    if (-not $Step -or $Step -le 14) { Start-CheckDisk }
    
    # Stop resource monitoring if it was started
    if ($Global:ResourceMonitoring) {
        Stop-ResourceMonitoring
    }
} else {
    Show-Format "ERROR" "Config not completely loaded after $maxWait Seconds" -TagColor "Red" -NameColor "Red"
}


