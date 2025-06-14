#!/usr/bin/env python3

import subprocess
from flask import Flask, Response, stream_with_context, request
import yaml
import os

# Load config
with open("config.yml", "r") as f:
    config = yaml.safe_load(f)

LOCAL_M3U_PATH = config.get("local_m3u_path", "playlist_local.m3u")
SERVER_HOST = config.get("server", {}).get("host", "0.0.0.0")
SERVER_PORT = config.get("server", {}).get("port", 3037)
FFMPEG_PROFILE_NAME = config.get("ffmpeg_profile", "")

# FFmpeg profiles dict
FFMPEG_PROFILES = {
    "hevc_nvenc": [
        'ffmpeg', "-hide_banner", "-loglevel", "error", "-probesize", "500000", "-analyzeduration", "1000000",
        "-fflags", "+genpts+discardcorrupt", "-flags", "low_delay", "-avoid_negative_ts", "make_zero",
        "-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "60", "-timeout", "5000000",
        "-rw_timeout", "5000000", "-copyts", "-start_at_zero",
        "-hwaccel", "cuda", "-hwaccel_output_format", "cuda",
        "-threads", "0", "-thread_queue_size", "8192",
        "-i", "{streamUrl}",
        "-map", "0:v:0", "-map", "0:a:0?", "-map", "0:s?",
        "-c:v", "hevc_nvenc", "-preset", "fast", "-tune", "ull", "-profile:v", "main", "-level", "4.1",
        "-rgb_mode", "1", "-g", "25", "-bf", "1", "-rc", "vbr_hq", "-cq", "26", "-rc-lookahead", "10",
        "-lookahead_level", "auto", "-no-scenecut", "1", "-temporal-aq", "1", "-spatial-aq", "1", "-aq-strength", "4",
        "-b:v", "6000k", "-maxrate", "7500k", "-bufsize", "12000k",
        "-c:a", "aac", "-b:a", "128k", "-ac", "2", "-af", "aresample=async=0", "-vsync", "1",
        "-f", "mpegts", "-muxrate", "0", "-muxdelay", "0.05", "-mpegts_flags", "+initial_discontinuity",
        "-bsf:v", "hevc_mp4toannexb", "pipe:1"
    ],
    "h264_nvenc": [
        'ffmpeg', "-hide_banner", "-loglevel", "error", "-probesize", "500000", "-analyzeduration", "1000000",
        "-fflags", "+genpts+discardcorrupt", "-flags", "low_delay", "-avoid_negative_ts", "make_zero",
        "-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "60", "-timeout", "5000000",
        "-rw_timeout", "5000000", "-copyts", "-start_at_zero",
        "-hwaccel", "cuda", "-hwaccel_output_format", "cuda",
        "-threads", "0", "-thread_queue_size", "8192",
        "-i", "{streamUrl}",
        "-map", "0:v:0", "-map", "0:a:0?", "-map", "0:s?",
        "-c:v", "h264_nvenc", "-preset", "fast", "-tune", "ull", "-profile:v", "main", "-level", "4.1",
        "-rgb_mode", "1", "-g", "25", "-bf", "1", "-rc", "vbr_hq", "-cq", "23", "-rc-lookahead", "20",
        "-lookahead_level", "auto", "-no-scenecut", "1", "-temporal-aq", "1", "-spatial-aq", "1", "-aq-strength", "6",
        "-b:v", "10000k", "-maxrate", "13000k", "-bufsize", "26000k",
        "-c:a", "aac", "-b:a", "128k", "-ac", "2", "-af", "aresample=async=0", "-vsync", "1",
        "-f", "mpegts", "-muxrate", "0", "-muxdelay", "0.05", "-mpegts_flags", "+initial_discontinuity",
        "-bsf:v", "h264_mp4toannexb", "pipe:1"
    ],
    # Add other profiles here as needed (amf, vaapi, qsv, software_libx264, software_libx265) ...
        'ffmpeg', "software_libx264": [
        "-hide_banner", "-loglevel", "info",
        "-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "4294",
        "-analyzeduration", "2000000", "-probesize", "10000000",
        "-i", "{streamUrl}",
        "-map_metadata", "-1", "-map_chapters", "-1",
        "-map", "0:0", "-map", "0:1", "-map", "-0:s",
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-preset", "fast",
        "-tune", "film",
        "-crf", "23",
        "-maxrate", "8000000",
        "-bufsize", "16000000",
        "-profile:v", "main",
        "-level", "4.1",
        "-x264opts", "subme=0:me_range=4:rc_lookahead=10:partitions=none",
        "-force_key_frames", "expr:gte(t,n_forced*3)",
        "-vf", "yadif=0:-1:0",
        "-c:a", "aac", "-ac", "2", "-b:a", "192k",
        "-f", "mpegts",
        "-copyts", "1",
        "-async", "1",
        "-movflags", "+faststart",
        "pipe:1"
    ]
}

def detect_hardware_encoder():
    """Detects hardware encoder available on the host machine."""
    # Check for NVIDIA GPU (nvenc)
    if os.path.exists("/dev/nvidia0"):
        return "hevc_nvenc"  # Or "h264_nvenc" if preferred
    # Check for AMD GPU (amf)
    # For AMD, detection is less straightforward, assume present if AMF libs present or add env override
    # For demo purposes, skip automatic AMD detection here
    # Check for Intel Quick Sync (qsv)
    if os.path.exists("/dev/dri/renderD128"):
        # For now assume QSV available if this device exists
        return "h264_qsv"
    # Default to software
    return "software_libx264"

def build_ffmpeg_command(stream_url: str):
    profile_name = FFMPEG_PROFILE_NAME.strip()
    if not profile_name:
        profile_name = detect_hardware_encoder()
    profile = FFMPEG_PROFILES.get(profile_name)
    if not profile:
        raise ValueError(f"Unknown ffmpeg profile: {profile_name}")
    return [arg.format(streamUrl=stream_url) for arg in profile]

app = Flask(__name__)

@app.route("/playlist.m3u")
def playlist():
    try:
        with open(LOCAL_M3U_PATH, "r", encoding="utf-8") as f:
            data = f.read()
        return Response(data, content_type="application/x-mpegURL")
    except FileNotFoundError:
        return "M3U file not found", 404

@app.route("/stream")
def stream():
    stream_url = request.args.get("url")
    if not stream_url:
        return "Missing 'url' query parameter", 400

    cmd = build_ffmpeg_command(stream_url)

    def generate():
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            while True:
                chunk = process.stdout.read(1024)
                if not chunk:
                    break
                yield chunk
        finally:
            process.kill()

    return Response(stream_with_context(generate()), content_type='video/mp2t')

if __name__ == "__main__":
    app.run(host=SERVER_HOST, port=SERVER_PORT)

