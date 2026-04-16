# Per-Stap Logging Instructies

## Overzicht

De pipeline heeft nu ondersteuning voor per-stap logging. Elke stap krijgt een eigen logfile met timestamp in de `LogDir`.

## Logfile Naamgeving

Formaat: `Step_XX_StepName_YYYYMMDD_HHmmss.log`

Voorbeelden:
- `Step_01_Initialisation_20251206_143022.log`
- `Step_03_Generate_Metadata_20251206_143045.log`
- `Step_05_DownloadSubs_20251206_143112.log`

## Conversie Specifieke Logfiles

Wanneer conversie functies worden aangeroepen vanuit een stap, schrijven ze naar de stap logfile.
Als ze standalone worden aangeroepen, krijgen ze hun eigen logfile:
- `h265_conversion_YYYYMMDD_HHmmss.log` - Voor H.265 naar H.264 conversie
- `downscale_conversion_YYYYMMDD_HHmmss.log` - Voor high bit-depth naar H.265 8-bit conversie

## Implementatie per Stap

### Voorbeeld (Step_03_Generate_Metadata.ps1)

```powershell
function Start-GenMeta {
    Start-StepLog -StepNumber "03" -StepName "Generate_Metadata"
    
    # ... stap logica hier ...
    Get-MetaData
    
    # Process H.265 files based on H265Action setting
    if ($Global:H265Action -eq "reject") {
        DrawBanner -Text "REJECTING H.265 FILES"
        Reject-H265Files -FolderPath $Global:TempDir
        Process-RejectedSourceFolders
    } elseif ($Global:H265Action -eq "convert") {
        DrawBanner -Text "CONVERTING H.265 FILES to H.264"
        Convert-AllH265InFolder -FolderPath $TempDir -Preset $Global:H265Preset -CRF $Global:H265CRF -Encoder $Global:H265Encoder
    } elseif ($Global:H265Action -eq "downscale") {
        DrawBanner -Text "CONVERTING HIGH BIT-DEPTH to H.265 8-bit"
        Convert-AllHighBitDepthInFolder -FolderPath $TempDir -Resolution $Global:DownscaleResolution -Preset $Global:DownscalePreset -CRF $Global:DownscaleCRF -Encoder $Global:DownscaleEncoder
    }
    
    Stop-StepLog
}
```

### Te Implementeren in Volgende Stappen

Voor elke `Start-*` functie:

1. **Step_01_Initialisation.ps1** - `Start-Init`
   ```powershell
   function Start-Init {
       Start-StepLog -StepNumber "01" -StepName "Initialisation"
       # ... existing code ...
       Stop-StepLog
   }
   ```

2. **Step_02_Prepare_Videos.ps1** - `Start-Prep`
   ```powershell
   function Start-Prep {
       Start-StepLog -StepNumber "02" -StepName "Prepare_Videos"
       # ... existing code ...
       Stop-StepLog
   }
   ```

3. **Step_04_StoreAndStrip.ps1** - `Start-Store`
   ```powershell
   function Start-Store {
       Start-StepLog -StepNumber "04" -StepName "StoreAndStrip"
       # ... existing code ...
       Stop-StepLog
   }
   ```

4. **Step_05_DownloadSubs.ps1** - `Start-DownloadSubs`
   ```powershell
   function Start-DownloadSubs {
       Start-StepLog -StepNumber "05" -StepName "DownloadSubs"
       # ... existing code ...
       Stop-StepLog
   }
   ```

5. **Step_06_Validate_Subtitles.ps1** - `Start-Validate`
   ```powershell
   function Start-Validate {
       Start-StepLog -StepNumber "06" -StepName "Validate_Subtitles"
       # ... existing code ...
       Stop-StepLog
   }
   ```

6. **Step_07_Score_Subtitles.ps1** - `Start-Score`
   ```powershell
   function Start-Score {
       Start-StepLog -StepNumber "07" -StepName "Score_Subtitles"
       # ... existing code ...
       Stop-StepLog
   }
   ```

7. **Step_08_Sync_Subtitles.ps1** - `Start-Sync`
   ```powershell
   function Start-Sync {
       Start-StepLog -StepNumber "08" -StepName "Sync_Subtitles"
       # ... existing code ...
       Stop-StepLog
   }
   ```

8. **Step_09_Embed_All.ps1** - `Start-Embed`
   ```powershell
   function Start-Embed {
       Start-StepLog -StepNumber "09" -StepName "Embed_All"
       # ... existing code ...
       Stop-StepLog
   }
   ```

9. **Step_10_Finalize.ps1** - `Start-Finalize`
   ```powershell
   function Start-Finalize {
       Start-StepLog -StepNumber "10" -StepName "Finalize"
       # ... existing code ...
       Stop-StepLog
   }
   ```

10. **Step_11_CheckDiskSpace.ps1** - `Start-CheckDisk`
    ```powershell
    function Start-CheckDisk {
        Start-StepLog -StepNumber "11" -StepName "CheckDiskSpace"
        # ... existing code ...
        Stop-StepLog
    }
    ```

## Functies Beschrijving

### Start-StepLog
Begint transcript logging voor een stap.

**Parameters:**
- `StepNumber` (verplicht): Stapnummer (bijv. "03", "05")
- `StepName` (verplicht): Stap naam (bijv. "Generate_Metadata", "DownloadSubs")

**Output:**
```
═══════════════════════════════════════════════════════════
STEP 03 - Generate_Metadata
Started: 2025-12-06 14:30:45
Log file: Step_03_Generate_Metadata_20251206_143045.log
═══════════════════════════════════════════════════════════
```

### Stop-StepLog
Beëindigt transcript logging en schrijft samenvatting.

**Parameters:**
- `Status` (optioneel): Status bericht (standaard: "COMPLETED")

**Output:**
```
═══════════════════════════════════════════════════════════
Status: COMPLETED
Ended: 2025-12-06 14:32:18
═══════════════════════════════════════════════════════════
```

## Voordelen

1. **Gescheiden Logs**: Elke stap heeft zijn eigen logfile
2. **Timestamps**: Logfiles bevatten timestamp voor traceerbaarheid
3. **Transcript**: Volledige console output wordt vastgelegd
4. **Integratie**: Conversie functies schrijven naar stap logfile als beschikbaar
5. **Debugging**: Makkelijker problemen traceren per specifieke stap
6. **Historisch**: Logs behouden voor latere analyse

## Status

- ✅ **GEÏMPLEMENTEERD**: Step 03 (Generate_Metadata)
- ⏳ **TE DOEN**: Steps 01, 02, 04-11

## Conversie Logging Details

De nieuwe `downscale` conversie logt:
- Pixelformaat detectie (8-bit, 10-bit, 12-bit)
- Conversie parameters (resolution, encoder, preset, CRF)
- Per-file conversie resultaten met elapsed time
- Samenvatting: aantal geconverteerd, aantal overgeslagen

Voorbeeld logfile entry:
```
[2025-12-06 14:35:22] ✔️  Movie.S01E01.mkv | 10-bit → H.265 8-bit 1080p | nvidia | 23.5s
```

## H265Action Opties in config.ini

```ini
# Video Conversion
H265Action=downscale          # reject | convert | downscale | skip

# Downscale Settings (voor H265Action=downscale)
DownscaleResolution=1080p     # 1080p | 720p
DownscaleEncoder=nvidia       # nvidia | amd | cpu
DownscaleCRF=23              # 18-28 (lower = better quality)
DownscalePreset=medium       # ultrafast | fast | medium | slow
```

### H265Action Opties:
- **reject**: Weigert H.265 bestanden (verplaatst naar Rejected folder)
- **convert**: Converteert H.265 → H.264 (oude methode, voor oudere TV's)
- **downscale**: Converteert 10-bit/12-bit → H.265 8-bit (AANBEVOLEN voor moderne TV's)
- **skip**: Geen conversie (laat H.265 ongemoeid)

### Wanneer welke optie:
- **Samsung UE40H6200AWXXN**: Gebruik `downscale` (ondersteunt H.265 8-bit 1080p)
- **Oudere TV's zonder H.265**: Gebruik `convert` (H.264 is universeel)
- **Moderne 4K TV's**: Gebruik `skip` (ondersteunen meestal 10-bit)
