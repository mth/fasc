import std/[os, sequtils, strutils, tables]
import utils, network, sway, apt, system, alsa, shell

func argsToMap(args: seq[string]): StrMap =
  for arg in args:
    let argParts = arg.split('=', maxsplit = 1)
    result[argParts[0]] = if argParts.len == 0: ""
                          else: argParts[1]

proc showUser(args: StrMap) =
  echo args.userInfo

let tasks = {
  "wlan": ("Configure WLAN client with DHCP", wlan),
  "wifinet": ("Add WLAN network ssid=<ssid>", wifiNet),
  "ntp": ("Enable timesyncd, optional ntp=<server>", startNTP),
  "sway": ("Configure sway desktop startup", swayUnit),
  "swaycfg": ("Configure sway compositor", swayConf),
  "apt": ("Configure APT defaults", configureAPT),
  "apt-all": ("Configure APT defaults and prune extraneous packages",
                configureAndPruneAPT),
  "tunesys": ("Tune system configuration", tuneSystem),
  "hdparm": ("Configure SATA idle timeouts", hdparm),
  "alsa": ("Configure ALSA dmixer", configureALSA),
  "bash": ("Configure bash", configureBash),
  "firewall": ("Setup default firewall", enableDefaultFirewall),
  "ovpn": ("Setup openvpn client", ovpnClient),
  "desktop-packages": ("Install desktop packages", installDesktopPackages),
  "gui-packages": ("Install GUI desktop packages", installDesktopUIPackages),
  "devel": ("Install development packages", installDevel),
  "showuser": ("Shows user", showUser),
  "nfs": ("Adds NFS mount", nfs),
}.toTable

if paramCount() == 0:
  echo "FAst System Configurator."
  echo("fasc ", tasks.keys.toSeq.join("|"))
  quit()

if not (paramStr(1) in tasks):
  echo "Unknown task: ", paramStr(1)
else:
  tasks[paramStr(1)][1](commandLineParams()[1..^1].argsToMap)
commitQueue()
