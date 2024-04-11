import utils

const emacs = readResource("emacs")

proc installOpam() =
  packagesToInstall.add ["opam", "elpa-company", "elpa-tuareg"]
  # add .emacs
  # as user run
  # opam init
  # opam install graphics merlin utop
