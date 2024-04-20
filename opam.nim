import utils

const emacs = readResource("emacs")

proc installOpam() =
  # it would be nice to detect whether sway or X11 is used (check for wayland socket?)
  packagesToInstall.add ["opam", "elpa-company", "elpa-tuareg"]
  # add .emacs
  # as user run
  # opam init
  # opam install graphics merlin utop
