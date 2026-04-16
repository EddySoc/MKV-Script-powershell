# ___ Bescherm tegen herhaald laden _____________________________________
if ($Global:GenMetaLoaded) { return }
$Global:GenMetaLoaded = $true

# ___ Module: Generate_Metadata.ps1 _______________________________________
# Doel: Haal nodige data uit mkv
# Aanroep: via hoofdscript dat Config.ps1 en Utils.ps1 al heeft geladen

# Load config if not already loaded (for standalone execution)
if (-not $Global:ConfigLoaded) {
    . (Join-Path $PSScriptRoot "Config.ps1")
}

# ___ Begin taakcode ____________________________________________________


function Get-MetaData {
DrawBanner -Text "STEP 03 GET ALL METADATA"

$metaSuccess = 0
$metaFailed = 0
$metaFailedItems = @()

# _____________ Doorloop alle MKV-bestanden _____________
Get-ChildItem -Path $Global:TempDir -Filter *.mkv -Recurse | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
    $infile = $_.FullName
    $name = $_.BaseName
    $relPath = $_.FullName.Substring($Global:TempDir.Length).TrimStart('\')
    $relDir  = [System.IO.Path]::GetDirectoryName($relPath)

    Show-Format "COLLECTING" "MetaData for $name"
    $itemFailed = $false

    $targetDir = Join-Path $Global:TempDir $relDir
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $metaJsonPath = Join-Path $Global:MetaDir "$name.meta.json"
    $subsPath = Join-Path $targetDir "$name.subs.txt"

    # _____ Read existing meta.json from Step 2 _____
    $metaObj = @{}
    if (Test-Path -LiteralPath $metaJsonPath) {
        try {
            $metaObj = Get-Content -LiteralPath $metaJsonPath -Raw | ConvertFrom-Json -AsHashtable
        } catch {
            Show-Format "ERROR" "Failed to read meta.json: $name" -NameColor "Red"
            $itemFailed = $true
        }
    }

    # _____ ffprobe: alles in één JSON-call _____
    $durationSec = 1
    $videoCodec = ""
    $subCount = 0
    $frameRate = ""
    $audioCount = 0
    $audioCodec = ""
    try {
        $ffprobeJson = & $Global:FFprobeExe -v error -show_streams -show_format -of json "$infile" | ConvertFrom-Json

        # Duur
        if ($ffprobeJson.format.duration -match '^[0-9\.]+$') {
            $durationSec = [int][math]::Round([double]$ffprobeJson.format.duration)
        }

        # Video stream info
        $videoStream = $ffprobeJson.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1
        if ($videoStream) {
            $videoCodec = $videoStream.codec_name
            
            # Framerate extractie
            if ($videoStream.r_frame_rate -match "(\d+)/(\d+)") {
                $num = [double]$matches[1]
                $den = [double]$matches[2]
                if ($den -gt 0) {
                    $frameRate = [Math]::Round($num / $den, 3)
                }
            }
        }

        # Audio stream info
        $audioStreams = $ffprobeJson.streams | Where-Object { $_.codec_type -eq "audio" }
        $audioCount = $audioStreams.Count
        if ($audioStreams.Count -gt 0) {
            $audioCodec = $audioStreams[0].codec_name
        }

        # Subs tellen
        $subCount = ($ffprobeJson.streams | Where-Object { $_.codec_type -eq "subtitle" }).Count
    } catch {
        Show-Format "ERROR" "ffprobe JSON failed" "$name" -NameColor "Red" -InverseTag
        $itemFailed = $true
    }

    # _____ Merge new fields into meta.json _____
    $metaObj.DurationSec = $durationSec
    $metaObj.SubCount = $subCount
    $metaObj.VideoCodec = $videoCodec
    $metaObj.FrameRate = $frameRate
    $metaObj.AudioCount = $audioCount
    $metaObj.AudioCodec = $audioCodec
    $metaObj.BestSub = ""
    $metaObj.BestScore = ""

    try {
        $metaObj | ConvertTo-Json | Set-Content -LiteralPath $metaJsonPath -Force
        if ($Global:DEBUGMode) {
            Show-Format "DEBUG" "Updated meta.json" "SubCount=$subCount to $metaJsonPath" -NameColor "DarkGray"
        }
    } catch {
        Show-Format "ERROR" "Writing meta.json Failed: $name" -NameColor "Red"
        $itemFailed = $true
    }

    # _____ Subs.txt alleen als er interne subs zijn _____
    if ($subCount -gt 0) {
        try {
            $subInfo = & $Global:FFprobeExe -v error -select_streams s -show_entries stream=index:stream_tags=language -of csv=p=0 "$infile"
            if ($subInfo) {
                $utf8 = New-Object System.Text.UTF8Encoding($false)
                [System.IO.File]::WriteAllLines($subsPath, $subInfo, $utf8)
                
                if ($Global:DEBUGMode) {
                    Show-Format "DEBUG" "Wrote subs.txt" "$subInfo to $subsPath" -NameColor "DarkGray"
                }
            }
        } catch {
            Show-Format "ERROR" "Writing subs.txt failed: $name" -NameColor "Red"
            $itemFailed = $true
        }
    } else {
        if ($Global:DEBUGMode) {
            Show-Format "DEBUG" "No embedded subs" "SubCount=0 for $name" -NameColor "DarkGray"
        }
    }

    if ($itemFailed) {
        $metaFailed++
        $metaFailedItems += $name
    } else {
        $metaSuccess++
    }
}
Show-Format "INFO" "All metadata collected"
write-host ""

Clear-TempLogs

return @{
    Success = $metaSuccess
    Failed = $metaFailed
    FailedItems = $metaFailedItems
}
}

function Reject-H265Files {
    param ([string]$FolderPath)
    
    Show-Format "INFO" "Moving H.265 files to Rejected folder..." -NameColor "Yellow"
    
    $rejectedCount = 0
    Get-ChildItem -Path $FolderPath -Filter *.mkv -Recurse | ForEach-Object {
        $file = $_.FullName
        $codec = ""
        
        try {
            $codec = (& $Global:FFprobeExe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $file | Select-Object -First 1).Trim()
        } catch {
            $codec = ""
        }
        
        if ($codec -eq "hevc") {
            # Move to Rejected folder
            $relativePath = $file.Substring($FolderPath.Length).TrimStart('\')
            $targetPath = Join-Path $Global:RejectDir $relativePath
            $targetDir = Split-Path $targetPath -Parent
            
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            
            try {
                Move-Item -Path $file -Destination $targetPath -Force
                Show-Format "REJECT" $_.Name "Moved to Rejected" -NameColor "Red"
                $rejectedCount++
            } catch {
                Show-Format "ERROR" $_.Name "Failed to move" -NameColor "Red"
            }
        }
    }
    
    Show-Format "INFO" "Rejected $rejectedCount H.265 file(s)" -NameColor "Yellow"
}

function Process-RejectedSourceFolders {
    DrawBanner "PROCESS REJECTED SOURCE FOLDERS"
    $rejectedAction = $Global:Rejected
    
    if (-not $rejectedAction -or ($rejectedAction -ne "keep" -and $rejectedAction -ne "remove")) {
        Show-Format "INFO" "Rejected setting: $rejectedAction" "Source folders will be kept" -NameColor "Cyan"
        return
    }
    
    if ($rejectedAction -eq "keep") {
        Show-Format "INFO" "Rejected source folders will be kept" "No action needed" -NameColor "Cyan"
        return
    }
    
    # Build rejected source folder list from current rejected files and remembered folders.
    # Older code looked for *.rejected.json, but those files are never written.
    $metaDir = $Global:MetaDir
    $sourceFoldersToDelete = @()

    if ($Global:RejectedSourceFolders) {
        foreach ($folder in $Global:RejectedSourceFolders) {
            if ($folder -and ($sourceFoldersToDelete -notcontains $folder)) {
                $sourceFoldersToDelete += $folder
            }
        }
    }

    $rejectedVideos = @()
    if ($Global:RejectDir -and (Test-Path -LiteralPath $Global:RejectDir)) {
        $rejectedVideos = @(Get-ChildItem -LiteralPath $Global:RejectDir -Recurse -Filter "*.mkv" -File -ErrorAction SilentlyContinue)
    }

    foreach ($rejectedVideo in $rejectedVideos) {
        $metaFile = Join-Path $metaDir "$($rejectedVideo.BaseName).meta.json"
        if (Test-Path -LiteralPath $metaFile) {
            try {
                $meta = Get-Content -LiteralPath $metaFile | ConvertFrom-Json
                if ($meta.SourceFolder -and ($sourceFoldersToDelete -notcontains $meta.SourceFolder)) {
                    $sourceFoldersToDelete += $meta.SourceFolder
                }
            } catch {
                Show-Format "WARNING" "Failed to read metadata" "$([System.IO.Path]::GetFileName($metaFile)): $_" -NameColor "Yellow"
            }
        }
    }
    
    if ($sourceFoldersToDelete.Count -eq 0) {
        Show-Format "INFO" "No rejected source folders to delete" "" -NameColor "Cyan"
        return
    }
    
    Show-Format "INFO" "Deleting $($sourceFoldersToDelete.Count) rejected source folder(s)" "" -NameColor "Yellow"
    
    # Get normalized SourceDir path for protection
    $normalizedSourceDir = [System.IO.Path]::GetFullPath($Global:SourceDir)
    
    foreach ($sourceFolder in $sourceFoldersToDelete) {
        if (Test-Path -LiteralPath $sourceFolder) {
            # NEVER remove the SourceDir itself
            $normalizedSource = [System.IO.Path]::GetFullPath($sourceFolder)
            if ($normalizedSource -eq $normalizedSourceDir) {
                Show-Format "PROTECTED" "SourceDir" "SourceDir preserved (files directly in SourceDir were rejected individually)" -NameColor "Cyan"
                continue
            }
            
            try {
                $folderName = Split-Path $sourceFolder -Leaf
                Remove-Item -LiteralPath $sourceFolder -Recurse -Force
                Show-Format "DELETE" "$folderName" "Rejected source removed" -NameColor "DarkGray"
            } catch {
                Show-Format "ERROR" "Failed to delete $folderName" "$_" -NameColor "Red"
            }
        }
    }
}

function Start-GenMeta {
    Start-StepLog -StepNumber "03" -StepName "Get_Metadata"
    
    $metaStats = Get-MetaData
    $Global:LastConversionStats = $null
    
    # Process H.265 files based on H265Action setting
    if ($Global:H265Action -eq "reject") {
        DrawBanner -Text "REJECTING H.265 FILES"
        Reject-H265Files -FolderPath $Global:TempDir
        # Process rejected source folders immediately after rejection
        Process-RejectedSourceFolders
    } elseif ($Global:H265Action -eq "convert") {
        DrawBanner -Text "CONVERTING H.265 FILES to H.264"
        Convert-AllH265InFolder -FolderPath $TempDir -Preset $Global:H265Preset -CRF $Global:H265CRF -Encoder $Global:H265Encoder
    } elseif ($Global:H265Action -eq "downscale") {
        DrawBanner -Text "CONVERTING HIGH BIT-DEPTH to H.265 8-bit"
        Convert-AllHighBitDepthInFolder -FolderPath $TempDir -Resolution $Global:DownscaleResolution -Preset $Global:DownscalePreset -CRF $Global:DownscaleCRF -Encoder $Global:DownscaleEncoder
    }
    # else: skip (any other value like "skip" or "ignore")

    if ($Global:LastConversionStats) {
        Set-StepRunResult -Step "03" `
            -Success ([int]$Global:LastConversionStats.Converted) `
            -Failed ([int]$Global:LastConversionStats.Failed) `
            -FailedItems @($Global:LastConversionStats.FailedItems) `
            -Note "mode=$($Global:LastConversionStats.Mode), skipped=$($Global:LastConversionStats.Skipped)"
    } else {
        Set-StepRunResult -Step "03" `
            -Success ([int]$metaStats.Success) `
            -Failed ([int]$metaStats.Failed) `
            -FailedItems @($metaStats.FailedItems) `
            -Note "metadata collection"
    }
    
    Stop-StepLog
}


