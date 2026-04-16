# MKV Script PowerShell

Windows PowerShell pipeline for preparing video files, finding or generating subtitles, translating and syncing them, and embedding the result back into MKV files.

## What it does

- copies and prepares video files for processing
- extracts existing subtitles
- downloads subtitles via FileBot / OpenSubtitles
- falls back to speech-to-text when needed
- translates subtitles with Argos Translate
- syncs subtitles with ALASS and FFSubSync
- embeds audio and subtitle tracks into the final MKV
- cleans up temporary files and logs

## Main workflow

1. initialize working folders
2. copy and rename videos
3. collect metadata
4. extract and strip subtitles
5. download subtitles
6. speech-to-text fallback
7. validate and clean subtitles
8. score and sync subtitles
9. translate when needed
10. embed the best result
11. finalize and clean up

## Requirements

- Windows
- PowerShell 7+
- FFmpeg / FFprobe
- MKVToolNix
- FileBot
- optional: ALASS, FFSubSync, Faster-Whisper, Argos Translate models

## Quick start

1. Copy `config.example.ini` to `config.ini`
2. Adjust the paths for your own machine
3. Copy `OpenSubtitles.auth.example` to `OpenSubtitles.auth`
4. Fill in your own OpenSubtitles login details
5. Run `start_mkvdut.bat`

For more setup details, see `README_SETUP.md`.

## Important note

This repository does not include personal credentials, downloaded media, temporary files, or local tool binaries. Those are ignored on purpose.

## Status

This is a practical personal automation project that is being improved step by step during real-world testing.
