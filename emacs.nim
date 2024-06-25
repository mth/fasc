import std/[sequtils, strutils]
import utils

const emacsConf = readResource("emacs/emacs.el")
const emacsModules = ["configure-cua.el", "configure-company.el",
                      "configure-merlin.el", "merlin-eldoc.el"].mapIt(
                      (it, readResource("emacs/" & it)))

echo emacsModules
