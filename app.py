#!/usr/bin/env python3

# --- Early gevent monkey patching ---
from gevent import monkey
monkey.patch_all()

import subprocess
from flask import Flask, Response, stream_with_context, request
import yaml
import os
import threading
import queue

# Load config
def load_config():
    try:
        with open("config.yml", "r") as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        return {}

config = load_config()
LOCAL_M3U_PATH = config.get("local_m3u_path", "playlist_local.m3u")
SERVER_HOST = config.get("server", {}).get("host", "0.0.0.0")
SERVER_PORT = config.get("server", {}).get("port", 3037)
FFMPEG_PROFILE_NAME = config.get("ffmpeg_profile", "")

# FFmpeg profiles
overlay_filter = "overlay=10:10"
FFMPEG_PROFILES = {
    "hevc_nvenc": [
        'ffmpeg', '-hide_banner', '-loglevel', 'error',
        '-reconnect', '1', '-reconnect_streamed', '1', '-reconnect_delay_max', '60',
        '-fflags', '+genpts+discardcorrupt', '-flags', 'low_delay',
        '-i', '{streamUrl}',
        '-map', '0:v:0', '-map', '0:a:0?',
        '-c:v', 'hevc_nvenc', '-preset', 'fast', '-tune', 'ull',
        '-profile:v', 'main', '-level', '4.1',
        '-rc', 'vbr_hq', '-cq', '26',
        '-b:v', '6000k', '-maxrate', '7500k', '-bufsize', '12000k',
        '-c:a', 'aac', '-b:a', '128k', '-ac', '2',
        '-f', 'mpegts', '-mpegts_flags', '+initial_discontinuity',
        'pipe:1'
    ],
    "h264_nvenc": [
        'ffmpeg', '-hide_banner', '-loglevel', 'error',
        '-reconnect', '1', '-reconnect_streamed', '1', '-reconnect_delay_max', '60',
        '-fflags', '+genpts+discardcorrupt', '-flags', 'low_delay',
        '-i', '{streamUrl}',
        '-map', '0:v:0', '-map', '0:a:0?',
        '-c:v', 'h264_nvenc', '-preset', 'fast', '-tune', 'ull',
        '-profile:v', 'main', '-level', '4.1',
        '-rc', 'vbr_hq', '-cq', '23',
        '-b:v', '10000k', '-maxrate', '13000k', '-bufsize', '26000k',
        '-c:a', 'aac', '-b:a', '128k', '-ac', '2',
        '-f', 'mpegts', '-mpegts_flags', '+initial_discontinuity',
        'pipe:1'
    ],
    "software_libx264": [
        'ffmpeg', '-hide_banner', '-loglevel', 'info',
        '-reconnect', '1', '-reconnect_streamed', '1', '-reconnect_delay_max', '4294',
        '-i', '{streamUrl}',
        '-map', '0:0', '-map', '0:1?',
        '-c:v', 'libx264', '-preset', 'fast', '-crf', '23',
        '-maxrate', '8000000', '-bufsize', '16000000',
        '-profile:v', 'main', '-level', '4.1',
        '-force_key_frames', 'expr:gte(t,n_forced*3)',
        '-c:a', 'aac', '-ac', '2', '-b:a', '192k',
        '-f', 'mpegts',
        'pipe:1'
    ]
}

def detect_hardware_encoder():
    if os.path.exists("/dev/nvidia0"):
        return "hevc_nvenc"
    if os.path.exists("/dev/dri/renderD128"):
        return "h264_qsv"
    return "software_libx264"

def build_ffmpeg_command(stream_url: str):
    profile_name = FFMPEG_PROFILE_NAME.strip() or detect_hardware_encoder()
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

# --- STREAMING LOGIC ---
class StreamProcess:
    def __init__(self, stream_url, cmd):
        self.cmd = cmd
        self.buffer = queue.Queue(maxsize=512)
        self.clients = 0
        self.lock = threading.Lock()
        self.running = True
        self.process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.thread = threading.Thread(target=self._read_output, daemon=True)
        self.thread.start()

    def _read_output(self):
        while self.running:
            chunk = self.process.stdout.read(1024)
            if not chunk:
                break
            try:
                self.buffer.put(chunk, timeout=1)
            except queue.Full:
                continue
        self.shutdown()

    def stream_generator(self):
        try:
            while self.running:
                chunk = self.buffer.get(timeout=5)
                yield chunk
        except Exception:
            pass
        finally:
            self.decrement_clients()

    def increment_clients(self):
        with self.lock:
            self.clients += 1

    def decrement_clients(self):
        with self.lock:
            self.clients -= 1
            if self.clients <= 0:
                self.shutdown()

    def shutdown(self):
        self.running = False
        try:
            self.process.kill()
        except Exception:
            pass

stream_processes = {}
stream_lock = threading.Lock()

@app.route("/stream")
def stream():
    stream_url = request.args.get("url")
    if not stream_url:
        return "Missing 'url' parameter", 400

    with stream_lock:
        sp = stream_processes.get(stream_url)
        if not sp or not sp.running:
            cmd = build_ffmpeg_command(stream_url)
            sp = StreamProcess(stream_url, cmd)
            stream_processes[stream_url] = sp
        sp.increment_clients()

    return Response(stream_with_context(sp.stream_generator()), content_type='video/mp2t')

if __name__ == "__main__":
    app.run(host=SERVER_HOST, port=SERVER_PORT, threaded=True)
