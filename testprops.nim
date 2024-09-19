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

import utils, std/[tables, os, sugar]

var update: Table[string, proc(old: string): string]

for nth in 1 .. (paramCount() - 1) div 2:
  let idx = nth * 2
  let key = paramStr(idx)
  let value = paramStr(idx + 1)
  capture value:
    update[key] = old => value

modifyProperties(paramStr(1), update)
