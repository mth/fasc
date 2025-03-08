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

import std/[strformat, strutils, os, tables]
import utils, apps, gui, system

const foot_ini = readResource("user/foot.ini");

const user_config = [
  (".XCompose", xcompose),
  (".config/waybar/config.jsonc", readResource("user/waybar.jsonc")),
  (".config/mpv/mpv.conf", readResource("user/mpv.conf")),
  (".config/gammastep/config.ini", gammastep_ini)
]

const sway_config = readResourceDir("sway")
const vimfm_desktop = readResource("vimfm.desktop")

# desktop - blank 600, suspend 660; laptop - blank 300, suspend 480
func swayIdle(blankTime: int): string = fmt"""
exec exec swayidle -w \
  timeout {blank_time} 'swaymsg "output * dpms off"' \
  resume 'swaymsg "output * dpms on"' \
  before-sleep 'swaylock -f -c 092a00' \
  after-resume 'pidof -q gammastep || gammastep&' \
  idlehint 20
"""

proc waylandUserConfig*(user: UserInfo) =
  for (file, conf) in user_config:
    writeAsUser(user, file, conf)
  var foot = foot_ini
  if not isDebian():
    foot = foot.replace("=Terminus:size=12,", "=")
  writeAsUser(user, ".config/foot/foot.ini", foot)

proc configureSway(user: UserInfo, sleepMinutes: int) =
  user.waylandUserConfig
  for (file, conf) in sway_config:
    var content = firefoxDebianize(conf)
    if file == "config":
      if isFedora():
        content = content.replace("\ninclude bar\n", "\ninclude waybar\n")
        let inc = "include /usr/share/sway/config.d"
        content &= &"{inc}/50-rules-*\n{inc}/*brightness.conf\n{inc}/*volume.conf\n"
      else:
        content &= &"include xf86bindings\n"
    writeAsUser(user, ".config/sway" / file, content)
  writeAsUser(user, ".config/sway/idle", swayIdle((sleepMinutes - 2) * 60))
  user.firefoxConfig

proc swayConf*(args: StrMap) =
  echo "swayConf called."
  configureSway(args.userInfo, defaultSleepMinutes())

proc swayUnit*(args: StrMap) =
  let userInfo = args.userInfo
  let sleepTime = defaultSleepMinutes()
  userInfo.configureSway sleepTime
  packagesToInstall.add ["qtwayland5", "xwayland"]
  addPackageUnless "greetd", "/usr/bin/greetd", true
  let agreety = if isDebian(): "/usr/sbin/agreety"
                else: "agreety"
  discard modifyProperties("/etc/greetd/config.toml",
            [("command", &"\"{agreety} --cmd '/usr/bin/ssh-agent /usr/bin/sway'\"")], false)
  userInfo.commonGuiSetup
  if "nosleep" notin args:
    systemdSleep(sleepTime)
  let ytdlAlias = "/usr/local/bin/youtube-dl"
  if not ytdlAlias.fileExists:
    try:
      createSymlink("/usr/bin/yt-dlp", ytdlAlias)
    except:
      echo("Cannot link /usr/bin/yt-dlp to ", ytdlAlias)
  addFirefox true
  # fonts-dejavu? fonts-liberation? fonts-freefont-ttf?
  # yt-dlp is in unstable, causes problems here
  packagesToInstall.add ["sway", "swayidle", "openssh-client", "foot",
                         "evince", "gammastep", "grimshot", "mpv", #"yt-dlp",
                         "fonts-terminus-otb", "fonts-unifont"]
  if listDir("/sys/class/backlight").len != 0:
    packagesToInstall.add ["brightnessctl", "brightness-udev"]
  const vimfmPath = "/usr/share/applications/vimfm.desktop"
  if not vimfmPath.fileExists:
    aptInstallNow()
    vimfmPath.writeFileSynced vimfm_desktop
    updateMime()
  if fileExists("/usr/lib/systemd/system/sddm.service"):
    runCmd "systemctl", "disable", "sddm.service"
