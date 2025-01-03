# This file is part of FASC, the FAst System Configurator.
#
# Copyright (C) 2022-2024 Madis Janson
#
# FASC is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# FASC is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with FASC. If not, see <https://www.gnu.org/licenses/>.

import std/[algorithm, os, sequtils, strutils, tables]
import utils, network, gui, sway, apt, system, sound, shell, nspawn, services, apps, vnc
import tv, backup

func argsToMap(args: seq[string]): StrMap =
  for arg in args:
    let argParts = arg.split('=', maxsplit = 1)
    result[argParts[0]] = if argParts.len == 1: ""
                          else: argParts[1]

proc showUser(args: StrMap) =
  echo args.userInfo

proc commonSystem(args: StrMap) =
  configureBash args
  tuneSystem args
  startNTP args
  enableDefaultFirewall args
  if isDebian():
    configureALSA args

var common_descr = "Alias for configuring bash, tunesys, ntp, firewall"
if isDebian():
  common_descr &= " and ALSA"

let tasks = {
  "wlan": ("Configure WLAN client with DHCP [supplicant]", wlan),
  "wifinet": ("Add WLAN network ssid=<ssid>", wifiNet),
  "ntp": ("Enable timesyncd, optional ntp=<server>", startNTP),
  "icewm": ("Install IceWM desktop", installIceWM),
  #"lxqt": ("Install LXQT desktop", installLXQT),
  "sway": ("Configure sway desktop startup", swayUnit),
  "swaycfg": ("Configure sway compositor", swayConf),
  "apt": ("Configure APT defaults", configureAPT),
  "prune": ("Configure APT/DNF defaults and prune extraneous packages [retain=a,b]",
                configureAndPrunePackages),
  "common": (common_descr, commonSystem),
  "tunesys": ("Tune system configuration", tuneSystem),
  "hdparm": ("Configure SATA idle timeouts", hdparm),
  "alsa": ("Configure ALSA dmixer", configureALSA),
  "shared-pa": ("Configure PulseAudio server for shared socket [card=1] [user=name]",
                sharedPulseAudio),
  "bash": ("Configure bash", configureBash),
  "firewall": ("Setup default firewall", enableDefaultFirewall),
  "ovpn": ("Setup openvpn client", ovpnClient),
  "desktop-packages": ("Install desktop packages", installDesktopPackages),
  "gui-packages": ("Install GUI desktop packages", installDesktopUIPackages),
  "beginner-devel": ("Install development packages for beginner", beginnerDevel),
  "devel": ("Install development packages", installDevel),
  "showuser": ("Shows user", showUser),
  "nfs": ("Adds NFS mount", nfs),
  "rpmfusion": ("Configures RPM fusion", configureRPMFusion),
  "upload-cam": ("upload-cam script rsync-to=host:/path [rsync-args=...]", uploadCam),
  "propset": ("set properties in config=/file/path", propset),
  "install-fasc": ("Install FASC into nspawn container machine=target", installFASC),
  "nspawn": ("Add nspawn configuration for machine=name [pulse-proxy] [bridge=172.20.0.1/24]", addNSpawn),
  "nspawn-ovpn": ("Create scripts to run ovpn in container by user=name", containerOVPN),
  "vnc-server": ("Install tigervnc server display=:2 proxy=addr:5902 bindTo=host0",
                 installVncServer),
  "proxy": ("proxy=name[:owner[:group[:mode]]] listen=1234 [bind=host0]\n" &
            19.spaces & "connect=127.0.0.1:2345 [idle-timeout=10min] [service=foobar]",
            socketProxy),
  "secure": ("service=name syscall allow_dev allow_netlink 01", secureService),
  "zoom": ("Install zoom", zoomSandbox),
  "idcard": ("Configure ID card", idCard),
  "update-zoom": ("Update zoom install", updateZoom),
  "safenet": ("Setup DNS blocklists", setupSafeNet),
  "tv": ("Install weston gui for TV", westonTV),
  "merlin": ("Setup emacs with tuareg mode and merlin using opam", installMerlin),
  "backup-server": ("Setup backup server backup-dev=/dev/sdd2 backup-user=foo-backup backup-size=MB [recreate-image]", backupServer),
  "nbd-backup": ("Install nbd-backup client", installBackupClient),
  "restic-server": ("Setup restic backup server backup-dev=/dev/sdd2 [hostname=host] [serverip=1.2.3.4]", installResticServer),
  "restic-user": ("Add backup-user=name to the restic server", resticUser),
  "restic-client": ("Setup restic client rest-server=hostname [backup-user=name]", resticClient),
  #"disable-tracker": ("Disable GNOME tracker", disableTracker),
}.toTable
if paramCount() == 0:
  echo "FAst System Configurator."
  echo "fasc command key=value..."
  echo ""
  echo "Commands:"
  for key in tasks.keys.toSeq.sorted:
    if not (isFedora() and key == "apt" or
            not isFedora() and key == "rpmfusion"):
      let (description, _) = tasks[key]
      echo("  ", key.alignLeft(16), ' ', description)
  quit()

if not (paramStr(1) in tasks):
  echo "Unknown task: ", paramStr(1)
else:
  tasks[paramStr(1)][1](commandLineParams()[1..^1].argsToMap)
commitQueue()
