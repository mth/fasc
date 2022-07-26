import std/[strformat, strutils]
import utils

const run_firefox_script = readResource("user/firefox.sh")
const ff2mpv_script = readResource("user/ff2mpv.py")
const ff2mpv_host = readResource("user/ff2mpv.json")

func pref(key, value: string): string =
  fmt"""pref("{key}", {(value.escape)});"""

func pref(key: string, value: int): string =
  fmt"""pref("{key}", {value});"""

func pref(key: string, value: bool): string =
  fmt"""pref("{key}", {value});"""

# TODO need to add settings to keep the tab/urlbar narrower
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
    #pref("browser.proton.enabled", false),
    #pref("browser.safebrowsing.malware.enabled", false),
    #pref("browser.safebrowsing.phishing.enabled", false),
    pref("browser.search.suggest.enabled", false),
    pref("browser.search.update", false),
    #pref("browser.tabs.inTitlebar", 0),
    pref("browser.tabs.loadInBackground", false),
    #pref("browser.urlbar.placeholderName", "DuckDuckGo"),
    #pref("browser.urlbar.placeholderName.private", "DuckDuckGo"),
    pref("browser.urlbar.showSearchSuggestionsFirst", false),
    pref("browser.uidensity", 1),
    #pref("dom.ipc.processCount", 12),
    #pref("dom.battery.enabled", false),
    pref("dom.event.clipboardevents.enabled", false),
    pref("dom.event.contextmenu.enabled", false),
    pref("dom.suspend_inactive.enabled", true),
    pref("general.warnOnAboutConfig", false),
    pref("gfx.canvas.azure.accelerated", true),
    pref("gfx.webrender.all", true),
    pref("gfx.webrender.enabled", true),
    pref("extensions.pocket.enabled", false),
    pref("layers.acceleration.force-enabled", true),
    pref("media.ffmpeg.dmabuf-textures.enabled", true),
    pref("media.ffmpeg.vaapi.enabled", true),
    pref("media.peerconnection.enabled", false),
    pref("media.peerconnection.ice.default_address_only", true),
    pref("media.peerconnection.ice.no_host", true),
    pref("media.peerconnection.ice.proxy_only_if_behind_proxy", true),
    pref("media.hardware-video-decoding.force-enabled", true),
    pref("widget.wayland_dmabuf_backend.enabled", true),
    pref("widget.wayland-dmabuf-vaapi.enabled", true),
    pref("widget.content.allow-gtk-dark-theme", true),
    #pref("network.cookie.cookieBehavior", 1),
    pref("network.cookie.lifetimePolicy", 2),
    pref("network.dns.disablePrefetch", true),
    #pref("network.http.referer.spoofSource", true),
    pref("network.http.referer.trimmingPolicy", 1),
    #pref("network.http.sendRefererHeader", 1),
    pref("places.history.expiration.max_pages", 1000),
    pref("places.history.expiration.transient_current_max_pages", 1000),
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
    writeAsUser(user, ".config/sway/firefox.sh", run_firefox_script,
                permissions = 0o755, force = true)
