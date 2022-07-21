import std/strutils
import utils

const asoundrc = """
defaults.pcm.rate_converter "speexrate_best"

pcm.dmixed {
    type dmix
    ipc_key 1027
    ipc_key_add_uid 0
    ipc_perm 0660
    slave {
        pcm "hw:CARD,0"
        period_time 0
        period_size 1024
        buffer_size 8192
        rate 48000
    }
}

# Everything shall be dmixed, so redefine "default":
pcm.asymed {
    type asym 
    playback.pcm "dmixed" 
    capture.pcm "hw:CARD,0"
}

pcm.!default {
    type plug
    slave.pcm "asymed"
    hint {
    	show on
	description "ALSA Default card with mixer"
    }
}

# OSS via aoss should d(mix)stroyed:
pcm.dsp0 {
    type plug
    slave.pcm "dmixed"
}

ctl.!default {
    type hw
    card CARD
}
"""

proc configureALSA*(args: Strs) =
  # CARD should be configurable by argument
  writeFile("/etc/asound.conf", [asoundrc.replace("CARD", "0")])
  packagesToInstall.add ["alsa-utils", "libasound2-plugins"]
