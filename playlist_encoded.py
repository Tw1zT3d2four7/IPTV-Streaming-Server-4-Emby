#!/usr/bin/env python3

import urllib.parse

INPUT_FILE = "playlist_local.m3u"
OUTPUT_FILE = "playlist_local_encoded.m3u"
STREAM_PREFIX = "http://0.0.0.0:3037/stream?url="

def fix_playlist():
    with open(INPUT_FILE, "r", encoding="utf-8") as infile, open(OUTPUT_FILE, "w", encoding="utf-8") as outfile:
        for line in infile:
            stripped = line.strip()
            # Check if line is a raw http/https URL that needs rewriting
            if stripped.startswith("http://") or stripped.startswith("https://"):
                encoded_url = urllib.parse.quote(stripped, safe='')
                fixed_line = f"{STREAM_PREFIX}{encoded_url}&format=mpegts\n"
                outfile.write(fixed_line)
            else:
                # Write other lines (like #EXTINF) unchanged
                outfile.write(line)

    print(f"✅ Fixed playlist written to: {OUTPUT_FILE}")

if __name__ == "__main__":
    fix_playlist()

