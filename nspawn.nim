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

proc createNSpawn(name, address: string, pulse = false) =
  let bridge = "br-vnet0"
  networkdBridge bridge, address
  var conf = nspawnConf(name, "Bridge=" & bridge)
  if pulse:
    conf &= "\n[Files]\nBind=/run/pulse.native\n"
    let def = if isFedora(): "pulse-proxy:pipewire:audio:0660"
              else: "pulse-proxy:pulse:pulse-access:0660"
    proxy def, "/run/pulse.native", bindTo="", "/run/user/1000/pulse/native",
          "1min", targetService="", "Pulseaudio socket proxy service"
  writeFile fmt"/etc/systemd/nspawn/{name}.nspawn", [conf]
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
  createNSpawn name, address, pulse

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
