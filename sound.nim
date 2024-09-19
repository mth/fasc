# This file is part of FASC, the FAst System Configurator.
#
# Copyright (C) 2022-2024 Madis Janson
#
# FASC is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# FASC is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with FASC. If not, see <https://www.gnu.org/licenses/>.

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
      "User=mpd", fmt"Group={user.group}", "SupplementaryGroups=audio"], "simple"
