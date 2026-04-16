# MKV Script PowerShell

A practical Windows PowerShell pipeline for processing video files, downloading or generating subtitles, translating them, syncing them, and embedding the final result back into MKV files.

## Overview

This project is built to automate the repetitive work around subtitle handling for movies and series. It combines preparation, subtitle extraction, subtitle download, speech-to-text fallback, translation, sync, embedding, and cleanup into one workflow.

## Features

- automatic video copy and preparation
- subtitle extraction from existing MKV files
- subtitle download with FileBot and OpenSubtitles
- speech-to-text fallback when no subtitle is available
- subtitle translation with Argos Translate
- subtitle sync with ALASS and FFSubSync
- final embedding into MKV files
- cleanup of temp, metadata, and rejected files
- logging per step for easier troubleshooting

## Workflow

1. initialize the working folders
2. copy and normalize video files
3. collect metadata
4. extract or strip subtitle tracks
5. download matching subtitles
6. generate subtitles with speech-to-text if needed
7. validate and clean subtitle files
8. score and sync the best subtitle
9. translate subtitles when required
10. embed the result into the final MKV
11. finalize and clean up

## Quick start

1. Copy `config.example.ini` to `config.ini`
2. Adjust the paths to your own PC
3. Copy `OpenSubtitles.auth.example` to `OpenSubtitles.auth`
4. Fill in your own OpenSubtitles credentials
5. Run `start_mkvdut.bat`

For the full setup instructions, see `README_SETUP.md`.

## Requirements

- Windows
- PowerShell 7+
- FFmpeg and FFprobe
- MKVToolNix
- FileBot
- optional: ALASS, FFSubSync, Faster-Whisper, Argos Translate packages

## Screenshots

You can add screenshots here later, for example:

- main console workflow
- sync progress view
- config GUI
- final embedded result

Example structure:

```text
/docs/images/main-console.png
/docs/images/config-gui.png
```

Then reference them in the README with normal Markdown images.

## Repository notes

This repository intentionally does not include:

- personal credentials
- local machine-specific config files
- downloaded media
- temporary output folders
- local executable tools and packages

Those files are excluded through the Git ignore rules.

## License

This project is released under the GNU GPL v3 license.

That means people may use, study, modify, and redistribute it, but redistributed versions must keep the same license terms.

## Status

This is a real-world utility project that is being refined step by step through testing on actual video files.
