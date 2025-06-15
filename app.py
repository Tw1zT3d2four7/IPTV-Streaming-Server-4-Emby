import os
import yaml
import subprocess
import threading
from flask import Flask, Response, request, abort

app = Flask(__name__)

# Load config.yml
with open("config.yml", "r") as f:
    config = yaml.safe_load(f)

FFMPEG_PROFILES = config["ffmpeg_profiles"]
DEFAULT_PROFILE = config["streaming"]["default_profile"]
QUEUE_SIZE = config["streaming"].get("queue_size", 100)

def build_ffmpeg_command(stream_url, profile_key):
    profile_cmd = FFMPEG_PROFILES.get(profile_key)
    if not profile_cmd:
        raise ValueError(f"FFmpeg profile '{profile_key}' not found.")
    return ["ffmpeg"] + profile_cmd.format(streamUrl=stream_url).split()

@app.route("/stream")
def stream():
    url = request.args.get("url")
    profile = request.args.get("profile", DEFAULT_PROFILE)

    if not url:
        abort(400, "Missing ?url parameter.")

    try:
        ffmpeg_cmd = build_ffmpeg_command(url, profile)
    except ValueError as e:
        abort(400, str(e))

    def generate():
        try:
            process = subprocess.Popen(
                ffmpeg_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                bufsize=QUEUE_SIZE
            )
            while True:
                chunk = process.stdout.read(4096)
                if not chunk:
                    break
                yield chunk
        except Exception as e:
            app.logger.error(f"Stream error: {e}")
        finally:
            if process:
                process.kill()

    return Response(generate(), mimetype="video/MP2T")

if __name__ == "__main__":
    app.run(
        host=config["server"]["host"],
        port=config["server"]["port"],
        threaded=True
    )
