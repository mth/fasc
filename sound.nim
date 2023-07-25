import std/[strformat, strutils, tables]
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
  commitQueue()
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
  commitQueue()
  safeFileUpdate "/etc/mpd.conf", mpd_conf
  var service = @[
    "User=mpd",
    "Group=" & user.group,
    "SupplementaryGroups=audio"
  ]
  if compatible("s922x"):
    service &= "CPUAffinity=0 1" # use economy cores
  overrideService "mpd.service", {s_sandbox, s_allow_devices, s_allow_netlink}, service
