import std/[os, strutils]
import utils

const asoundrc = readResource("asound.conf")
const system_pa = readResource("pulseaudio/system.pa")

proc configureALSA*(args: StrMap) =
  # CARD should be configurable by argument
  writeFile("/etc/asound.conf", [asoundrc.replace("CARD", "0")])
  packagesToInstall.add ["alsa-utils", "libasound2-plugins"]

proc systemPulseAudio*(args: StrMap) =
  packagesToInstall.add "pulseaudio"
  commitQueue()
  for systemdUser in ["/usr/lib/systemd/user/pulseaudio.socket",
                      "/usr/lib/systemd/user/pulseaudio.service"]:
    if systemdUser.readSymlink != "/dev/null":
      discard tryRemoveFile systemdUser
      createSymlink "/dev/null", systemdUser
  writeFile("/etc/pulse/system.pa", [system_pa], true)
  discard modifyProperties("/etc/pulse/client.conf",
            [("autospawn", "no")], onlyEmpty=false, comment=';')
  discard modifyProperties("/etc/pulse/daemon.conf",
            [("default-sample-rate", "48000"),
             ("alternative-sample-rate", "48000")],
            comment=';')
