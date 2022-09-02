import std/strutils
import utils

const asoundrc = readResource("asound.conf")

proc configureALSA*(args: StrMap) =
  # CARD should be configurable by argument
  writeFile("/etc/asound.conf", [asoundrc.replace("CARD", "0")])
  packagesToInstall.add ["alsa-utils", "libasound2-plugins"]

proc systemPulseAudio*(args: StrMap) =
  packagesToInstall.add "pulseaudio"
  discard modifyProperties("/etc/pulse/client.conf",
            [("autospawn", "no")], onlyEmpty=false, comment=';')
