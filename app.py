#!/usr/bin/env python3

from gevent import monkey; monkey.patch_all()

import os
import subprocess
import threading
import queue
import yaml
from flask import Flask, Response, stream_with_context, request

# Load configuration
with open("config.yml", "r") as f:
    config = yaml.safe_load(f)

LOCAL_M3U_PATH = config.get("local_m3u_path", "playlist_local.m3u")
SERVER_HOST = config.get("server", {}).get("host", "0.0.0.0")
SERVER_PORT = config.get("server", {}).get("port", 3037)
FFMPEG_PROFILE_NAME = config.get("ffmpeg_profile", "")

# All available FFmpeg profiles
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
    "software_libx264": [
        'ffmpeg', "-hide_banner", "-loglevel", "info",
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
    if os.path.exists("/dev/nvidia0"):
        return "hevc_nvenc"
    if os.path.exists("/dev/dri/renderD128"):
        return "h264_nvenc"
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
            return Response(f.read(), content_type="application/x-mpegURL")
    except FileNotFoundError:
        return "M3U file not found", 404

@app.route("/health")
def health():
    return "OK", 200

class StreamProcess:
    def __init__(self, stream_url, cmd):
        self.stream_url = stream_url
        self.cmd = cmd
        self.clients = 0
        self.lock = threading.Lock()
        self.buffer = queue.Queue(maxsize=100)
        self.running = True
        self.process = None
        self.thread = None
        self.start()

    def start(self):
        try:
            self.process = subprocess.Popen(self.cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            self.thread = threading.Thread(target=self._read_output)
            self.thread.daemon = True
            self.thread.start()
        except Exception as e:
            print(f"Failed to start FFmpeg for {self.stream_url}: {e}")
            self.running = False

    def _read_output(self):
        try:
            while self.running and self.process and self.process.poll() is None:
                chunk = self.process.stdout.read(8192)
                if not chunk:
                    break
                try:
                    self.buffer.put(chunk, timeout=1)
                except queue.Full:
                    continue
        finally:
            self.running = False
            self.shutdown()

    def get_stream_generator(self):
        self.increment_clients()
        def generator():
            try:
                while self.running:
                    try:
                        chunk = self.buffer.get(timeout=5)
                        yield chunk
                    except queue.Empty:
                        break
            finally:
                self.decrement_clients()
        return generator()

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
            if self.process:
                self.process.kill()
        except Exception:
            pass
        with self.lock:
            self.clients = 0

stream_processes = {}
stream_processes_lock = threading.Lock()

@app.route("/stream")
def stream():
    stream_url = request.args.get("url")
    if not stream_url:
        return "Missing 'url' query parameter", 400

    with stream_processes_lock:
        sp = stream_processes.get(stream_url)
        if sp is None or not sp.running:
            try:
                cmd = build_ffmpeg_command(stream_url)
                sp = StreamProcess(stream_url, cmd)
                stream_processes[stream_url] = sp
            except Exception as e:
                return f"Failed to start stream: {e}", 500

    return Response(stream_with_context(sp.get_stream_generator()), content_type='video/mp2t')

def cleanup_dead_processes():
    import time
    while True:
        with stream_processes_lock:
            to_delete = [url for url, sp in stream_processes.items() if not sp.running]
            for url in to_delete:
                del stream_processes[url]
        time.sleep(30)

threading.Thread(target=cleanup_dead_processes, daemon=True).start()

if __name__ == "__main__":
    app.run(host=SERVER_HOST, port=SERVER_PORT)
