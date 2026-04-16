# MKV Dutch Subtitle Pipeline - Setup Guide

## Moving to Another PC

This script is now portable and can be moved to any Windows PC. Follow these steps:

### 1. Copy Script Folder
Copy the entire script folder (e.g., `C:\QBtor`) to the new PC. You can place it anywhere you want.

### 2. Update config.ini
Edit `config.ini` and update these two paths:

```ini
[Paths]
RootDir=C:\QBMedia          # Your working directory (Downloads/Temp/Media/etc.)
VidDir=C:\Video             # Final destination for processed videos
```

**That's it!** All other paths are automatically calculated relative to these two locations.

### 3. Verify Prerequisites
Ensure these tools are installed on the new PC:

- **PowerShell 7+** (not Windows PowerShell 5.1)
- **FFmpeg** (in PATH or specify full path)
- **MKVToolNix** (mkvmerge, mkvpropedit, mkvextract in PATH)
- **FileBot** (for subtitle downloads)
- **MediaInfo CLI** (for video metadata)

Optional tools:
- **alass-cli.exe** (for subtitle syncing) - place in script folder
- **LangCheck.exe** (for language detection) - place in script folder

### 4. Test Run
1. Place a test video in `RootDir\Downloads`
2. Run `start_mkvdut.bat`
3. Check the console output for any missing dependencies

### Directory Structure Created Automatically
The script creates this structure under `RootDir`:
```
RootDir\
  ├── Downloads\      # Place your videos here
  ├── Temp\           # Working directory (auto-cleaned)
  ├── Media\          # Processed videos (before moving to VidDir)
  ├── Metadata\       # Video metadata cache
  ├── Logs\           # Processing logs
  ├── Done\           # Original source folders (if Originals=keep)
  └── Rejected\       # Rejected videos (H.265 if H265Action=reject)
```

### Configuration Options

#### Video Processing
```ini
[Video]
H265Action=convert       # "convert" = encode to H.264, "reject" = move to Rejected, "skip" = leave as-is
H265Encoder=cpu          # "cpu", "nvidia", or "amd" (nvidia/amd skip 10-bit)
H265Preset=ultrafast     # FFmpeg preset
H265CRF=28              # Quality (lower = better, 18-28 range)
```

#### File Handling
```ini
[Files]
Originals=keep          # "keep" = move to Done/, "remove" = delete after processing
Rejected=keep           # "keep" = keep in Downloads, "remove" = delete rejected files
```

#### Subtitles
```ini
[Lang]
LangKeep=dut            # Comma-separated languages to keep (e.g., "dut,eng")

[Subtitles]
EmbedOnlyPrimary=true   # true = only embed first language, false = embed all
EmbedDefault=true       # true = mark primary subtitle as default
EmbedForced=false       # true = mark non-primary subtitles as forced
```

### GitHub-safe setup
- Copy `config.example.ini` to `config.ini`
- Copy `OpenSubtitles.auth.example` to `OpenSubtitles.auth`
- Fill in your own local paths and login details
- Do not commit your real `config.ini` or `OpenSubtitles.auth`

### OpenSubtitles Authentication
Create/edit `OpenSubtitles.auth` in the script folder:
```
username=your_username
password=your_password
```

### Troubleshooting

**"Config not loaded"**
- Check that `config.ini` exists in the script folder
- Verify paths in `config.ini` are valid Windows paths

**"FFmpeg not found"**
- Add FFmpeg to system PATH, or edit scripts to use full path

**"FileBot error"**
- Ensure FileBot is installed and in PATH
- Check OpenSubtitles.auth credentials

**"Permission denied"**
- Run PowerShell as Administrator if working with system folders
- Check folder permissions for RootDir and VidDir

### Performance Notes

- **CPU encoding**: Slow but supports 10-bit H.265 sources
- **NVIDIA/AMD encoding**: Fast but only works with 8-bit sources (auto-skips 10-bit)
- **Hybrid approach**: Set `H265Encoder=cpu` to handle all sources, or `nvidia`/`amd` to skip 10-bit files

### Log Files
Check these logs in `RootDir\Logs`:
- `download_subtitles.log` - FileBot download activity
- `rejected_videos.log` - Videos rejected (H.265 with reject action)
- `conversion_log.txt` - H.265 to H.264 conversion details
- Pipeline console output - full processing details

---

**Need help?** Check the console output - the script provides detailed feedback at each step.
