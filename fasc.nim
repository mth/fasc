import std/[os, sequtils, strutils, tables]
import cmdqueue
import network
import sway

let tasks = {
  "wlan": ("Configure WLAN client with DHCP", wlan),
  "wifinet": ("Add WLAN network", wifiNet),
  "sway": ("Configure sway desktop startup", swayUnit)
}.toTable

if paramCount() == 0:
  echo "FAst System Configurator."
  echo("fasc ", tasks.keys.toSeq.join("|"))
  quit()

if not (paramStr(1) in tasks):
  echo "Unknown task: ", paramStr(1)
else:
  tasks[paramStr(1)][1](commandLineParams()[1..^1])
runQueuedCommands()
