import std/[os, strutils]
import utils

const asoundrc = readResource("asound.conf")
const system_pa = readResource("pulseaudio/system.pa")

proc configureALSA*(args: StrMap) =
  # CARD should be configurable by argument
  writeFile("/etc/asound.conf", [asoundrc.replace("CARD", "0")])
  packagesToInstall.add ["alsa-utils", "libasound2-plugins"]


proc pulseAudioTCP*(args: StrMap) =
  discard tryRemoveFile "/etc/asound.conf"

# nft add rule inet filter input ip saddr 172.20.0.2 tcp dport 4713 ct state new accept

proc systemPulseAudio*(args: StrMap) =
  packagesToInstall.add "pulseaudio"
  commitQueue()
  runCmd("systemctl", "disable", "--global", "pulseaudio.socket", "pulseaudio.service")
  for systemdUser in ["/etc/systemd/user/pulseaudio.socket",
                      "/etc/systemd/user/pulseaudio.service"]:
    if systemdUser.readSymlink != "/dev/null":
      discard tryRemoveFile systemdUser
      createSymlink "/dev/null", systemdUser
      systemdReload = true
  writeFile("/etc/pulse/system.pa", [system_pa], true)
  discard modifyProperties("/etc/pulse/client.conf",
            [("autospawn", "no")], onlyEmpty=false, comment=';')
  discard modifyProperties("/etc/pulse/daemon.conf",
            [("default-sample-rate", "48000"),
             ("alternate-sample-rate", "48000")],
            comment=';')
