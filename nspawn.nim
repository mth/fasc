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

import std/[strformat, os, strutils, tables]
import network, services, utils

# CAP_CHOWN Make arbitrary changes to file UIDs and GIDs (see chown(2)).
# CAP_DAC_OVERRIDE Bypass file read, write, and execute permission checks.
# CAP_DAC_READ_SEARCH Bypass file read permission checks and directory read and execute permission checks;
#                     invoke open_by_handle_at(2); use the linkat(2) AT_EMPTY_PATH flag to create a link
# CAP_FOWNER Bypass permission checks on operations that normally require the filesystem UID of the process to match
#            the  UID of the file (e.g., chmod(2), utime(2)), excluding those operations covered by CAP_DAC_*.
# CAP_FSETID Don't clear set-user-ID and set-group-ID mode bits when a file is modified;
#            Set the set-group-ID bit for a file whose GID does not match the filesystem
# CAP_IPC_LOCK Lock memory (mlock(2), mlockall(2), mmap(2), shmctl(2)).
# CAP_IPC_OWNER Bypass permission checks for operations on System V IPC objects.
# CAP_KILL Bypass  permission  checks for sending signals (see kill(2)).
# CAP_LEASE (since Linux 2.4) Establish leases on arbitrary files (see fcntl(2)).
# CAP_MKNOD (since Linux 2.4) Create special files using mknod(2).
# CAP_NET_ADMIN Perform various network-related operations:
# CAP_NET_BIND_SERVICE Bind a socket to Internet domain privileged ports (port numbers less than 1024).
# CAP_NET_RAW Use RAW and PACKET sockets; bind to any address for transparent proxying.
# CAP_SETGID Make arbitrary manipulations of process GIDs and supplementary GID list;
#            forge GID when passing socket credentials via UNIX domain sockets;
#            write a group ID mapping in a user namespace (see user_namespaces(7)).
# CAP_SETFCAP (since Linux 2.6.24) Set arbitrary capabilities on a file.
# CAP_SETPCAP add any capability from the calling thread's bounding set to its inheritable set;
#             drop capabilities from the bounding set; make changes to the securebits flags.
#             Make changes to the securebits flags.
# CAP_SYS_CHROOT Use chroot(2); change mount namespaces using setns(2).
# CAP_SYS_TTY_CONFIG Use vhangup(2); employ various privileged ioctl(2) operations on virtual terminals.

func nspawnConf(host, network: string): string = fmt"""
[Network]
{network}

[Exec]
Hostname={host}
Boot=on
PrivateUsers=pick
NoNewPrivileges=true
Capability=CAP_IPC_LOCK
DropCapability=CAP_AUDIT_CONTROL CAP_AUDIT_READ CAP_AUDIT_WRITE CAP_BLOCK_SUSPEND CAP_BPF CAP_CHECKPOINT_RESTORE CAP_LINUX_IMMUTABLE CAP_MAC_ADMIN CAP_MAC_OVERRIDE CAP_NET_BROADCAST CAP_PERFMON CAP_SYS_BOOT CAP_SYS_MODULE CAP_SYS_NICE CAP_SYS_PACCT CAP_SYS_PTRACE CAP_SYS_RAWIO CAP_SYS_RESOURCE CAP_SYS_TIME CAP_SYSLOG CAP_WAKE_ALARM
"""

func networkInterfaces(address, gateway: string): string = fmt"""
auto host0
iface host0
  address {address}
  gateway {gateway}
"""

# TODO create systemd service that ups bridge using simple ip link + ip addr
# [Unit]
# Wants=network.target
# After=local-fs.target network-pre.target systemd-modules-load.service
# Before=network.target shutdown.target network-online.target
# Conflicts=shutdown.target
# [Service]
# Type=oneshot
# RemainAfterExit=yes
# ExecStart=ip link add br-vnet0 type bridge
# ExecStart=ip addr add 172.20.0.1/24 dev br-vnet0
# ExecStart=ip link set br-vnet0 up
# ExecStop=ip link set br-vnet0 down
# ExecStop=ip link del br-vnet0
# [Install]
# WantedBy=network-online.target

proc createNSpawn(name, address: string, options: openarray[string] = [], pulse = false) =
  let bridge = "br-vm"
  # TODO alternative for networkdBridge if networkd not used
  networkdBridge bridge, address
  var conf = @[nspawnConf(name, "Bridge=" & bridge)]
  conf &= options
  if pulse:
    conf &= "[Files]\nBind=/run/pulse.native"
    let def = if isFedora(): "pulse-proxy:pipewire:audio:0660"
              else: "pulse-proxy:pulse:pulse-access:0660"
    proxy def, "/run/pulse.native", bindTo="", "/run/user/1000/pulse/native",
          "1min", targetService="", "Pulseaudio socket proxy service"
  conf &= ""
  writeFile fmt"/etc/systemd/nspawn/{name}.nspawn", conf
  addPackageUnless "systemd-container", "/usr/bin/systemd-nspawn"
  let resolvedConf = "/etc/systemd/resolved.conf"
  if not resolvedConf.fileExists:
    writeFile resolvedConf, "[Resolve]\n"
  if modifyProperties(resolvedConf, [("DNSStubListenerExtra", address.split('/', 2)[0])]):
    runCmd "systemctl", "restart", "systemd-resolved"

proc addNSpawn*(args: StrMap) =
  let name = args.nonEmptyParam "machine"
  let address = args.getOrDefault("bridge", "172.20.0.1/24")
  let pulse = "pulse-proxy" in args
  let init = "/var/lib/machines" / name / "sbin/init"
  if not init.fileExists:
    echo fmt"Missing {init}"
    quit 1
  createNSpawn name, address, [], pulse

func runOnScriptSource(command, machine, remoteCommand: string): string = fmt"""
#!/bin/sh
[ "`id -u`" = "0" ] || exec sudo {command}
exec systemd-run -tqGM {machine} --wait --service-type=exec {remoteCommand}
"""

proc runOnScript(command, machine, remoteCommand: string): string =
  command.safeFileUpdate runOnScriptSource(command, machine, remoteCommand)
  return command

func systemdRunArgs(machine: string, command: openarray[string]): seq[string] =
  @["--machine=" & machine, "--wait", "--service-type=exec", "-PGq"] & @command

proc installFASC*(args: StrMap) =
  let machine = args.nonEmptyParam "machine"
  var fascPath = args.getOrDefault "fasc"
  if fascPath == "":
    fascPath = paramStr(0).findExe
    if fascPath == "":
      fascPath = findExe("fasc")
      if fascPath == "":
        echo "Could not find fasc binary"
        quit 1
  runCmd("machinectl", "copy-to", machine, fascPath, "/usr/local/bin/fasc")

proc fascAt(machine: string, arguments: varargs[string]) =
  runCmd("systemd-run", systemdRunArgs(machine, "/usr/local/bin/fasc" & @arguments))

# TODO - configure nftables, resolved
proc containerOVPN*(args: StrMap) =
  let machine = args.nonEmptyParam("machine")
  args.userInfo.sudoNoPasswd("",
    runOnScript("/usr/local/bin/ovpn-" & machine, machine,
                "systemd-run --scope /usr/local/bin/ovpn"),
    runOnScript("/usr/local/bin/kill-vpn-" & machine, machine, "/usr/local/bin/kill-vpn"))
  machine.fascAt("ovpn", "nosudo")

# https://quantum5.ca/2025/03/22/whirlwind-tour-of-systemd-nspawn-containers/
# https://wildwolf.name/a-simple-script-to-create-systemd-nspawn-alpine-container/
# https://github.com/yoshuawuyts/systemd-nspawn-scripts/blob/master/build-alpine
# https://gist.github.com/sfan5/52aa53f5dca06ac3af30455b203d3404

when defined(arm64):
  const arch = "aarch64"
when defined(amd64):
  const arch = "x86_64"
when defined(i386):
  const arch = "x86"
when defined(arm):
  const arch = "armv7"

proc downloadAlpine(): string =
  let url = fmt"https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/{arch}/"
  let html = outputOfCommand("", "/usr/bin/wget", "-qO", "-", url).join
  let name_prefix = "alpine-minirootfs-"
  let a_prefix = "<a href=\"" & name_prefix
  var i = html.find a_prefix
  var filename = ""
  var version = -1
  while i > 0:
    let begin = i + (a_prefix.len - name_prefix.len)
    i = html.find("\">", i + a_prefix.len)
    if i > 0:
      let name = html[begin..i-1]
      i = html.find(a_prefix, i + 2)
      if name.endsWith ".gz":
        try:
          let ver_end = name.find('-', name_prefix.len)
          var ver = 0
          for part in name[name_prefix.len..ver_end-1].split('.'):
            ver += part.parseInt
            ver *= 10000
          if ver > version:
            filename = name
        except:
          discard
  if filename == "":
    echo "Do not find minirootfs url"
    quit 1
  let path = "/tmp/" & filename
  runCmd "/usr/bin/wget", "-O", path, url & filename
  return path

# http://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/
#   find <a href="alpine-minirootfs-3.21.0-aarch64.tar.gz">alpine-minirootfs-3.21.0-aarch64.tar.gz</a>
#   with biggest -x.y.z- number
# tar xf ../alpine-minirootfs-3.21.3-aarch64.tar.gz
# systemd-nspawn -D test apk add alpine-base
# for i in $(seq 0 10); do echo "pts/$i" >> "test/etc/securetty"; done
# sed -i '/tty[0-9]:/ s/^/#/' "test/etc/inittab"
# echo 'console::respawn:/sbin/getty 38400 console' >> "test/etc/inittab"
# for svc in bootmisc hostname syslog; do ln -s "/etc/init.d/$svc" "test/etc/runlevels/boot/$svc"; done
# for svc in killprocs savecache; do ln -s "/etc/init.d/$svc" "test/etc/runlevels/shutdown/$svc"; done
# test/etc/shadow root:*::0:::::
# systemd-nspawn --kill-signal=SIGUSR2

proc alpineVM*(args: StrMap) =
  let machine = args.nonEmptyParam "machine"
  let address = args.nonEmptyParam "address"
  let addressParts = address.split '.'
  let gateway = addressParts[0..2].join(".") & ".1"
  let tar = downloadAlpine()
  addPackageUnless "systemd-container", "/usr/bin/systemd-nspawn", true
  let root = "/var/lib/machines/" & machine
  createDir root
  runCmd "/usr/bin/tar", "-C", root, "-xzf", tar
  var spawnArg = @["-D", root, "apk", "add", "alpine-base"]
  spawnArg &= "dropbear"
  runCmd "/usr/bin/systemd-nspawn", spawnArg
  var inittab: seq[string]
  let inittabPath = root & "/etc/inittab"
  for line in inittabPath.lines:
    if line.startsWith "tty":
      inittab.add('#' & line)
    else:
      inittab.add line
  inittab.add "console::respawn:/sbin/getty 38400 console\n"
  writeFileSynced inittabPath, inittab.join("\n")
  writeFileSynced root & "/etc/network/interfaces", networkInterfaces(address, gateway)
  for service in ["bootmisc", "hostname", "syslog", "networking"]:
    createSymlink fmt"/etc/init.d/{service}", fmt"{root}/etc/runlevels/boot/{service}"
  for service in ["killprocs", "savecache"]:
    createSymlink fmt"/etc/init.d/{service}", fmt"{root}/etc/runlevels/shutdown/{service}"
  createNSpawn machine, gateway, ["KillSignal=SIGUSR2", ""]
