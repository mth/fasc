#!/usr/bin/python3

import json
import os
import platform
import struct
import sys
import subprocess

def main():
    message = get_message()
    url = message.get("url")

    # https://github.com/mpv-player/mpv/issues/4241
    args = ["mpv", "--fs", "--no-terminal"]
    final_message = "ok"

    try:
        height = json.loads(subprocess.run(["swaymsg", "-t", "get_tree"],
                            capture_output=True).stdout)['rect']['height']
        if height:
            args.append("--ytdl-format=bestvideo[height<=?" + str(height) + "]+bestaudio/best")
    except:
        final_message = "Couldn't determine screen resolution from swaymsg -t get_tree"

    subprocess.Popen(args + ["--", url])

    # Need to respond something to avoid "Error: An unexpected error occurred" in Browser Console.
    send_message(final_message)

# https://developer.mozilla.org/en-US/Add-ons/WebExtensions/Native_messaging#App_side
def get_message():
    raw_length = sys.stdin.buffer.read(4)
    if not raw_length:
        return {}
    length = struct.unpack("@I", raw_length)[0]
    message = sys.stdin.buffer.read(length).decode("utf-8")
    return json.loads(message)

def send_message(message):
    content = json.dumps(message).encode("utf-8")
    length = struct.pack("@I", len(content))
    sys.stdout.buffer.write(length)
    sys.stdout.buffer.write(content)
    sys.stdout.buffer.flush()

if __name__ == "__main__":
    main()
