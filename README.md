# IPTV Streaming Server

This is a lightweight IPTV streaming server built with Flask and FFmpeg. It streams channels from an M3U playlist with hardware-accelerated encoding when available.

## Features

- Supports multiple FFmpeg profiles including hardware acceleration:
  - NVIDIA NVENC (hevc_nvenc, h264_nvenc)
  - Intel QSV (h264_qsv)
  - Software x264 encoder fallback
- Automatically detects and selects the best available encoder if none specified.
- Simple Flask API serving:
  - `/playlist.m3u` — serves your local M3U playlist.
  - `/stream?url=STREAM_URL` — transcodes and streams the requested URL.
- Runs easily inside a Docker container.
- Configurable via `config.yml`.

---

## Prerequisites

- Docker & Docker Compose installed on your machine.
- Your M3U playlist file placed locally (default is `playlist_local.m3u`).

---

## Configuration

Edit the `config.yml` file to configure server host/port and FFmpeg profile.

```yaml
local_m3u_path: "playlist_local.m3u"

server:
  host: "0.0.0.0"
  port: 3037

# Set to "" for auto hardware detection, or specify profile like "hevc_nvenc", "software_libx264"
ffmpeg_profile: ""

