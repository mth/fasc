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

import std/[strformat, strutils, tables]
import utils, services

proc installVncServer*(args: StrMap) =
  packagesToInstall.add ["tigervnc-standalone-server", "tigervnc-tools", "icewm"]
  aptInstallNow()
  let userInfo = args.userInfo
  let display = args.getOrDefault("display", "2").strip(chars={':'})
  let listenProxy = args.getOrDefault "proxy"
  discard modifyProperties("/etc/tigervnc/vncserver.users",
            [(':' & display, userInfo.user)])
  if listenProxy.len != 0:
    proxy(proxy="vnc-proxy",
          listen=listenProxy,
          bindTo=args.getOrDefault "proxy-bind",
          connectTo=fmt"127.0.0.1:{5900 + display.parseInt}",
          exitIdleTime="10min",
          targetService=fmt"tigervncserver@:{display}")
