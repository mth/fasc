import std/[os, sequtils, strutils, tables]
import utils, network, sway, apt, system

let tasks = {
  "wlan": ("Configure WLAN client with DHCP", wlan),
  "wifinet": ("Add WLAN network", wifiNet),
  "sway": ("Configure sway desktop startup", swayUnit),
  "swaycfg": ("Configure sway compositor", swayConf),
  "apt": ("Configure APT defaults", configureAPT),
  "sysctl": ("Configure sysctl parameters", sysctls),
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
