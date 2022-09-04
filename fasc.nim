import std/[algorithm, os, sequtils, strutils, tables]
import utils, network, sway, apt, system, sound, shell, nspawn, services, zoom

func argsToMap(args: seq[string]): StrMap =
  for arg in args:
    let argParts = arg.split('=', maxsplit = 1)
    result[argParts[0]] = if argParts.len == 1: ""
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
  "shared-pa": ("Configure PulseAudio server for shared socket [card=1] [user=username]",
                sharedPulseAudio),
  "bash": ("Configure bash", configureBash),
  "firewall": ("Setup default firewall", enableDefaultFirewall),
  "ovpn": ("Setup openvpn client", ovpnClient),
  "desktop-packages": ("Install desktop packages", installDesktopPackages),
  "gui-packages": ("Install GUI desktop packages", installDesktopUIPackages),
  "devel": ("Install development packages", installDevel),
  "showuser": ("Shows user", showUser),
  "nfs": ("Adds NFS mount", nfs),
  "upload-cam": ("upload-cam script", uploadCam),
  "propset": ("set properties in config=/file/path", propset),
  "install-fasc": ("Install FASC into nspawn container machine=target", installFASC),
  "nspawn-ovpn": ("Create scripts to run ovpn in container by user=name", containerOVPN),
  "proxy": ("socket=name[:owner[:group[:mode]]] listen=1234 [bind=host0]\n" &
            19.spaces & "connect=127.0.0.1:2345 [idle-timeout=10min] [service=foobar]",
            socketProxy),
  "zoom": ("Install zoom", zoomSandbox),
  "update-zoom": ("Update zoom install", updateZoom),
}.toTable
if paramCount() == 0:
  echo "FAst System Configurator."
  echo "fasc command key=value..."
  echo ""
  echo "Commands:"
  for key in tasks.keys.toSeq.sorted:
    let (description, _) = tasks[key]
    echo("  ", key.alignLeft(16), ' ', description)
  quit()

if not (paramStr(1) in tasks):
  echo "Unknown task: ", paramStr(1)
else:
  tasks[paramStr(1)][1](commandLineParams()[1..^1].argsToMap)
commitQueue()
