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

import utils

const emacs = readResource("emacs")

proc installOpam() =
  # it would be nice to detect whether sway or X11 is used (check for wayland socket?)
  packagesToInstall.add ["opam", "elpa-company", "elpa-tuareg"]
  # add .emacs
  # as user run
  # opam init
  # opam install graphics merlin utop
