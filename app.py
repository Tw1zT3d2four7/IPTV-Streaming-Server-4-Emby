import yaml
import subprocess
from flask import Flask, Response, request, abort

app = Flask(__name__)

# Load config.yml once at startup
with open("config.yml", "r") as f:
    config = yaml.safe_load(f)

FFMPEG_PROFILES = config["profiles"]
DEFAULT_PROFILE = config["streaming"].get("default_profile")
QUEUE_SIZE = config["streaming"].get("queue_size", 100)

def detect_gpu_profile():
    try:
        subprocess.run(["nvidia-smi"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        if "h264_nvenc" in FFMPEG_PROFILES:
            return "h264_nvenc"
        if "hevc_nvenc" in FFMPEG_PROFILES:
            return "hevc_nvenc"
    except Exception:
        pass

    try:
        result = subprocess.run(["ffmpeg", "-hide_banner", "-hwaccels"], capture_output=True, text=True)
        if "qsv" in result.stdout:
            if "h264_qsv" in FFMPEG_PROFILES:
                return "h264_qsv"
            if "hevc_qsv" in FFMPEG_PROFILES:
                return "hevc_qsv"
    except Exception:
        pass

    try:
        result = subprocess.run(["vainfo"], capture_output=True, text=True)
        if result.returncode == 0:
            if "h264_vaapi" in FFMPEG_PROFILES:
                return "h264_vaapi"
            if "hevc_vaapi" in FFMPEG_PROFILES:
                return "hevc_vaapi"
    except Exception:
        pass

    if "libx264" in FFMPEG_PROFILES:
        return "libx264"
    if "libx265" in FFMPEG_PROFILES:
        return "libx265"

    return list(FFMPEG_PROFILES.keys())[0]

def build_ffmpeg_command(stream_url, profile_key):
    profile = FFMPEG_PROFILES.get(profile_key)
    if not profile:
        raise ValueError(f"FFmpeg profile '{profile_key}' not found.")

    cmd_str = profile["ffmpeg_args"]

    if "-fflags" not in cmd_str:
        cmd_str = cmd_str.replace("ffmpeg ", "ffmpeg -fflags +nobuffer ")

    cmd_str = cmd_str.format(streamUrl=stream_url)

    return ["ffmpeg"] + cmd_str.split()

@app.route("/stream")
def stream():
    url = request.args.get("url")
    profile = request.args.get("profile")

    if not url:
        abort(400, "Missing ?url parameter.")

    if not profile:
        profile = detect_gpu_profile()

    try:
        ffmpeg_cmd = build_ffmpeg_command(url, profile)
    except ValueError as e:
        abort(400, str(e))

    def generate():
        process = None
        try:
            process = subprocess.Popen(
                ffmpeg_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                bufsize=QUEUE_SIZE * 1024
            )
            while True:
                chunk = process.stdout.read(65536)
                if not chunk:
                    break
                yield chunk
        except Exception as e:
            app.logger.error(f"Stream error: {e}")
        finally:
            if process and process.poll() is None:
                process.kill()
                process.wait()

    return Response(generate(), mimetype="video/MP2T")

if __name__ == "__main__":
    app.run(
        host=config["server"]["host"],
        port=config["server"]["port"],
        threaded=True,
        debug=config["server"].get("debug", False),
        workers=config["server"].get("workers", 1)
    )
