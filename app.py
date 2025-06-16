#!/usr/bin/env python3

from flask import Flask, request, Response, stream_with_context
import subprocess
import yaml
import os

app = Flask(__name__)

# Load config
with open("config.yml", "r") as f:
    config = yaml.safe_load(f)

LOCAL_M3U_PATH = config.get("local_m3u_path", "playlist_local.m3u")
SERVER_HOST = config.get("server", {}).get("host", "0.0.0.0")
SERVER_PORT = config.get("server", {}).get("port", 3037)
FFMPEG_PROFILE_NAME = config.get("ffmpeg_profile", "")

# FFmpeg profiles
FFMPEG_PROFILES = {
    "h264_nvenc": [
        'ffmpeg', '-hide_banner', '-loglevel', 'error',
        '-hwaccel', 'cuda', '-hwaccel_output_format', 'cuda',
        '-i', '{streamUrl}',
        '-c:v', 'h264_nvenc', '-preset', 'fast', '-tune', 'ull',
        '-b:v', '5000k', '-c:a', 'aac', '-b:a', '128k',
        '-f', 'mpegts', 'pipe:1'
    ],
    "software_libx264": [
        'ffmpeg', '-hide_banner', '-loglevel', 'error',
        '-i', '{streamUrl}',
        '-c:v', 'libx264', '-preset', 'fast', '-crf', '23',
        '-c:a', 'aac', '-b:a', '128k',
        '-f', 'mpegts', 'pipe:1'
    ]
}

def detect_hardware_encoder():
    if os.path.exists("/dev/nvidia0"):
        return "h264_nvenc"
    return "software_libx264"

def build_ffmpeg_command(stream_url: str):
    profile_name = FFMPEG_PROFILE_NAME.strip() or detect_hardware_encoder()
    profile = FFMPEG_PROFILES.get(profile_name)
    if not profile:
        raise ValueError(f"Unknown ffmpeg profile: {profile_name}")
    return [arg.format(streamUrl=stream_url) for arg in profile]

@app.route('/playlist.m3u')
def playlist():
    try:
        with open(LOCAL_M3U_PATH, "r", encoding="utf-8") as f:
            return Response(f.read(), content_type="application/x-mpegURL")
    except FileNotFoundError:
        return "M3U file not found", 404

@app.route('/health')
def health():
    return "OK", 200

@app.route('/stream')
def stream():
    stream_url = request.args.get("url")
    if not stream_url:
        return "Missing 'url' query parameter", 400

    try:
        ffmpeg_command = build_ffmpeg_command(stream_url)
    except Exception as e:
        return f"Failed to build FFmpeg command: {e}", 500

    def generate():
        process = subprocess.Popen(
            ffmpeg_command,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0
        )
        try:
            while True:
                output = process.stdout.read(1024)
                if not output:
                    break
                yield output
        except GeneratorExit:
            pass
        finally:
            try:
                process.kill()
            except Exception:
                pass

    return Response(stream_with_context(generate()), content_type='video/mp2t')

if __name__ == "__main__":
    app.run(host=SERVER_HOST, port=SERVER_PORT, threaded=True)
