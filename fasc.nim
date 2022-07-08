import std/[strutils, tables, os]
import cmdqueue
import network
import sway

let tasks = {
  "wlan": ("Configure WLAN client with DHCP", wlan),
  "sway": ("Configure sway desktop startup", swayUnit)
}.toTable

if paramCount() == 0:
  echo "FAst System Configurator."
  echo "fasc (wlan|sway)"
  quit()

if not (paramStr(1) in tasks):
  echo "Unknown task: ", paramStr(1)
else:
    tasks[paramStr(1)][1](commandLineParams()[1..^1])
runQueuedCommands()
