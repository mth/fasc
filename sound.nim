import std/[os, strutils, tables]
import utils

const asoundrc = readResource("asound.conf")
const default_pa = readResource("default.pa")

proc configureALSA*(args: StrMap) =
  # CARD should be configurable by argument
  writeFile("/etc/asound.conf", [asoundrc.replace("CARD", "0")])
  packagesToInstall.add ["alsa-utils", "libasound2-plugins"]

proc sharedPulseAudio*(args: StrMap) =
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
