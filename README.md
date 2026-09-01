# Video Trim and Encoder with Metadata Restoration

A Windows batch script to automatically trim start/end seconds, optionally re-encode videos with custom CRF settings (H.265 or AV1), and preserve or restore correct recording timestamps/timezones.

## Features
* **Smart Trimming:** Cuts specified seconds from the beginning and end of all `.mp4` files in the current folder (skips files that are too short).
* **Optional Compression:** Re-encodes videos via FFmpeg using H.265 or AV1 with custom CRF values.
* **Smart Metadata Handling:**
  * Uses the file modification date as the recording date so gallery apps (e.g., Immich, Google Photos) sort them correctly.
  * Automatically detects DJI Action camera & DJI Mimo App videos (e.g., `DJI_...`) and extracts the exact timestamp from the filename.
  * Prompts for the recording timezone to fix offset issues for cameras without built-in GPS.
* **Timestamp Preservation:** Sets the original modification date on the processed output files (`_cut.mp4` / `_crfXX.mp4`).

## Prerequisites
Place the required executable files in the same directory as the script, or add them to your system `PATH`:

* **[FFmpeg & FFprobe](https://www.gyan.dev/ffmpeg/builds/)** — Download `ffmpeg-release-full.7z`, extract it, and copy both `ffmpeg.exe` and `ffprobe.exe` from the `bin` folder into the script directory.
* **[ExifTool](https://exiftool.org/)** — Download the Windows executable zip, extract it, rename `exiftool(-k).exe` to `exiftool.exe`, and copy it into the script directory.

## How to Use
1. Save the batch script in the folder containing your `.mp4` videos.
2. Ensure `ffmpeg.exe`, `ffprobe.exe`, and `exiftool.exe` are present in the same directory.
3. Double-click the script to run it and follow the on-screen prompts.

## Disclaimer
This project is an independent open-source tool and is not affiliated, associated, authorized, endorsed by, or in any way officially connected with SZ DJI Technology Co., Ltd. (DJI) or any of its subsidiaries or affiliates.
