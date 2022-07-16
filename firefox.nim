import std/[strformat, strutils]
import cmdqueue

const ff2mpv_script = """
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
            args.append("--ytdl-format=bestvideo[height<=?" + height + "]+bestaudio/best")
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
"""
const ff2mpv_host = """{
    "name": "ff2mpv",
    "description": "ff2mpv's external manifest",
    "path": "HOME/.mozilla/ff2mpv.py",
    "type": "stdio",
    "allowed_extensions": ["ff2mpv@yossarian.net"]
}"""

func pref(key, value: string): string =
  fmt"""pref("{key}", "{(value.escape)}")"""

func pref(key: string, value: int): string =
  fmt"""pref("{key}", {value})\n"""

func pref(key: string, value: bool): string =
  fmt"""pref("{key}", {value})\n"""

proc addFirefoxESR*() =
  writeFile("/etc/firefox-esr/optimize.js", [
    pref("browser.aboutConfig.showWarning", false),
    pref("browser.cache.disk.capacity", 262144),
    pref("browser.cache.offline.enable", false),
    pref("browser.download.dir", "/tmp/downloads"),
    pref("browser.fixup.alternate.enabled", false),
    pref("browser.formfill.enable", false),
    pref("browser.newtabpage.enhanced", false),
    pref("browser.privatebrowsing.autostart", true),
    #pref("browser.safebrowsing.malware.enabled", false),
    #pref("browser.safebrowsing.phishing.enabled", false),
    pref("browser.search.suggest.enabled", false),
    pref("browser.search.update", false),
    #pref("browser.tabs.inTitlebar", 0),
    pref("browser.tabs.loadInBackground", false),
    #pref("browser.urlbar.placeholderName", "DuckDuckGo"),
    #pref("browser.urlbar.placeholderName.private", "DuckDuckGo"),
    pref("browser.urlbar.showSearchSuggestionsFirst", false),
    #pref("dom.ipc.processCount", 12),
    pref("dom.suspend_inactive.enabled", true),
    pref("gfx.canvas.azure.accelerated", true),
    pref("gfx.webrender.all", true),
    pref("gfx.webrender.enabled", true),
    pref("layers.acceleration.force-enabled", true),
    pref("media.ffmpeg.vaapi.enabled", true),
    pref("media.hardware-video-decoding.force-enabled", true),
    pref("widget.wayland_dmabuf_backend.enabled", true),
    pref("widget.wayland-dmabuf-vaapi.enabled", true),
    #pref("network.cookie.cookieBehavior", 1),
    pref("network.cookie.lifetimePolicy", 2),
    pref("network.dns.disablePrefetch", true),
    #pref("network.http.referer.spoofSource", true),
    pref("network.http.referer.trimmingPolicy", 1),
    #pref("network.http.sendRefererHeader", 1),
    pref("permissions.default.camera", 2),
    pref("permissions.default.desktop-notification", 2),
    pref("permissions.default.geo", 2),
    pref("permissions.default.microphone", 2),
    pref("privacy.clearOnShutdown.cache", false),
    pref("privacy.clearOnShutdown.downloads", false),
    pref("privacy.clearOnShutdown.history", true),
    pref("privacy.clearOnShutdown.offlineApps", true),
    pref("privacy.firstparty.isolate", true),
    pref("privacy.resistFingerprinting", true),
    pref("ui.systemUsesDarkTheme", 1),
  ])
  packagesToInstall.add "firefox-esr"

proc firefoxConfig*(user: UserInfo) =
    writeAsUser(user, ".mozilla/ff2mpv.py", ff2mpv_script, force = true)
    writeAsUser(user, ".mozilla/native-messaging-hosts/ff2mpv.json",
                ff2mpv_host.replace("HOME", user.home),
                permissions = 0o755, force = true)
