import std/[os, sequtils, strutils, tables]
import utils, network, sway, apt, system, alsa, shell

func argsToMap(args: seq[string]): StrMap =
  for arg in args:
    let argParts = arg.split('=', maxsplit = 1)
    result[argParts[0]] = if argParts.len == 0: ""
                          else: argParts[1]

let tasks = {
  "wlan": ("Configure WLAN client with DHCP", wlan),
  "wifinet": ("Add WLAN network", wifiNet),
  "sway": ("Configure sway desktop startup", swayUnit),
  "swaycfg": ("Configure sway compositor", swayConf),
  "apt": ("Configure APT defaults", configureAPT),
  "apt-prune": ("Configure APT defaults and prune extraneous packages",
                configureAndPruneAPT),
  "tunesys": ("Tune system configuration", tuneSystem),
  "alsa": ("Configure ALSA dmixer", configureALSA),
  "bash": ("Configure bash", configureBash),
  "firewall": ("Setup default firewall", enableDefaultFirewall),
  "desktop-packages": ("Install desktop packages", installDesktopPackages),
}.toTable

if paramCount() == 0:
  echo "FAst System Configurator."
  echo("fasc ", tasks.keys.toSeq.join("|"))
  quit()

if not (paramStr(1) in tasks):
  echo "Unknown task: ", paramStr(1)
else:
  tasks[paramStr(1)][1](commandLineParams()[1..^1].argsToMap)
runQueuedCommands()
