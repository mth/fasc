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

import std/[os, strutils, tables]
import utils

# This part is unlikely to need customization, and probably should into /etc/bash.bashrc
const etc_bashrc = readResource("bash.bashrc")
const dot_bashrc = readResource("user/bashrc")
const debian_bashrc_header = "# ~/.bashrc: executed by bash(1) for non-login shells."
const fedora_bashrc_header = "# .bashrc"
const upload_cam_script = readResource("user/upload-cam")
const upload_cam_desktop = readResource("user/upload-cam.desktop")
const helix = readResource("user/helix.toml")

proc configureUserBash(user: UserInfo) =
  let bashrc = user.home / ".bashrc"
  try:
    let bashrc_first = readLines(bashrc, 1)
    if bashrc_first != [debian_bashrc_header] and
       bashrc_first != [fedora_bashrc_header]:
      echo bashrc, " is not a debian default, not modifying"
      return
  except:
    discard # non-existent .bashrc isn't a problem
  echo("Replacing ", bashrc)
  if isDebian():
    writeFile(bashrc, dot_bashrc)
  else:
    writeFile(bashrc, dot_bashrc.replace("&& return\n", "&& return\n. /etc/bash.bashrc\n") &
                      "alias ncal='cal -v'\n")
  user.writeAsUser(".config/helix/config.toml", helix)

proc configureBash*(args: StrMap) =
  echo "Replacing /etc/bash.bashrc"
  writeFile("/etc/bash.bashrc", etc_bashrc)
  configureUserBash(args.userInfo)

proc uploadCam*(args: StrMap) =
  let rsync_args = args.getOrDefault("rsync-args", "'--groupmap=*:www-data'")
  let user = args.userInfo
  user.writeAsUser("bin/upload-cam",
    upload_cam_script.multiReplace(("{RSYNC_TARGET}", args.nonEmptyParam("rsync-to")),
                                   ("{RSYNC_ARGS}", rsync_args)), 0o755, true)
  user.writeAsUser(".local/share/applications/upload-cam.desktop",
    upload_cam_desktop.replace("HOME", user.home))
  addPackageUnless("rsync", "/usr/bin/rsync")
