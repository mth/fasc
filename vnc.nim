#import std/[strformat, strutils, tables]
import utils

proc installVncServer*(args: StrMap) =
  packagesToInstall.add ["tigervnc-standalone-server", "icewm"]
