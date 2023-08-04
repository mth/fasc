import std/[strformat, strutils, tables, posix]
import services, system, utils

when defined(arm64):
  const asoundrc = readResource("tv/asound.conf")
else:
  const asoundrc = readResource("asound.conf")

const default_pa = readResource("default.pa")
const mpd_conf = readResource("tv/mpd.conf")

proc configureALSA*(args: StrMap) =
  # CARD should be configurable by argument
  writeFile("/etc/asound.conf", [asoundrc.replace("CARD", "0")])
  packagesToInstall.add ["alsa-utils", "libasound2-plugins"]

proc sharedPulseAudio*(args: StrMap) =
  let mainUID = if "user" in args: $args.userInfo.uid
                else: ""
  let cardId = args.getOrDefault("card", "0")
  packagesToInstall.add ["alsa-utils", "pulseaudio"]
  aptInstallNow()
  writeFile("/etc/pulse/default.pa", [default_pa.replace("${CARD}", cardId)], true)
  discard modifyProperties("/etc/pulse/daemon.conf",
            [("allow-module-loading", "no"),
             ("allow-exit", "no"),
             ("resample-method", "speex-float-5"),
             ("default-sample-rate", "48000"),
             ("alternate-sample-rate", "44100"),
             ("avoid-resampling", "yes")],
            comment=';')
  if mainUID != "":
    proxy(proxy="pulse-proxy:pulse:pulse-access:0660",
          listen="/run/pulse.native", bindTo="",
          connectTo=fmt"/run/user/{mainUID}/pulse/native",
          exitIdleTime="1min", targetService="",
          description="Pulseaudio socket proxy")

proc installMpd*(user: UserInfo) =
  packagesToInstall.add "mpd"
  aptInstallNow()
  safeFileUpdate "/etc/mpd.conf", mpd_conf
  var service = @[
    ("User=", "mpd"),
    ("Group=", user.group),
    ("SupplementaryGroups=", "audio"),
  ]
  if compatible("s922x"):
    service &= ("CPUAffinity=", "0 1") # use economy cores
  overrideService "mpd.service", {s_sandbox}, service
  overrideService "mpd.socket", {},
    ("ExecStartPre=", "/usr/bin/install -m 755 -o mpd -g audio -d /run/mpd"),
    ("SocketUser=", "mpd"), ("SocketGroup=", "audio"), ("SocketMode=", "0660")
  const fifo = "/var/lib/mpd/keep-alsa-open"
  if mkfifo(fifo, 0o600) == -1:
    echo fmt"({fifo}) failed: {strerror(errno)}"
    quit 1
  runCmd "chown", "mpd:audio", fifo
  addService "alsa-open", "Keeps ALSA device open", ["sound.target"],
    fmt"/usr/bin/aplay -t raw -f dat {fifo}", "multi-user.target", {}, [
      fmt"ExecStop=/usr/bin/dd if=/dev/zero of=/var/lib/mpd/{fifo} bs=4 count=1",
      "User=mpd", "Group=tv", "SupplementaryGroups=audio"], "simple"
