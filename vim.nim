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

import std/[os, sequtils, strformat, strutils]
import utils

# TODO
#  * Changing/adding set foo= and PREFIX setlocal foo=
#    (vim allows multiple assignments after set)
#    Possible approximation - simple prefix check (could be done with flag to appendMissing)
#  * Adding unique source directives (can be done with appendMissing)
#  * Write default colors and some other configurations

# Colors
# colorscheme nice
# set hlsearch
# filet plugin on
# sy on

func initVim(user: UserInfo): string =
  user.home / ".config/nvim/init.vim"

proc addVimPlugins(user: UserInfo, plugins: seq[string]) =
  var addPlugins = plugins.mapIt(fmt"Plug '{it}'")
  var doubleQuoted = plugins.mapIt(fmt"""Plug "{it}"""")
  var vimConfig: seq[string]
  var insertPluginsAt = 0
  let initFile = user.initVim
  if initFile.fileExists:
    var pluginSection = false
    for line in initFile.lines:
      vimConfig &= line
      let stripped = line.strip
      if stripped == "call plug#begin()":
        pluginSection = true
      elif not pluginSection:
        continue
      elif stripped == "call plug#end()":
        insertPluginsAt = vimConfig.len - 1
      else:
        var idx = addPlugins.find stripped
        if idx < 0:
          idx = doubleQuoted.find stripped
        if idx >= 0:
          addPlugins.del idx
          doubleQuoted.del idx
  if addPlugins.len > 0:
    if insertPluginsAt == 0:
      addPlugins.insert "call plug#begin()"
      addPlugins.add "call plug#end()"
    vimConfig.insert(addPlugins, insertPluginsAt)
    user.writeAsUser(".config/nvim/init.vim", vimConfig.join("\n") & "\n", force=true)
  let plugScript = user.home / ".config/nvim/autoload/plug.vim"
  if plugins.len > 0 and not plugScript.fileExists:
    user.writeAsUser(".config/nvim/autoload/plug.vim", "")
    addPackageUnless("wget", "/usr/bin/wget")
    aptInstallNow()
    runCmd("wget", "-O", plugScript,
           "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim")
