import std/[strformat, os, tables]
import services, utils

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

func nspawnConf(host: string): string = fmt"""
[Exec]
Hostname={host}
Boot=on
PrivateUsers=pick
NoNewPrivileges=true
Capability=CAP_IPC_LOCK
DropCapability=CAP_AUDIT_CONTROL CAP_AUDIT_READ CAP_AUDIT_WRITE CAP_BLOCK_SUSPEND CAP_BPF CAP_CHECKPOINT_RESTORE CAP_LINUX_IMMUTABLE CAP_MAC_ADMIN CAP_MAC_OVERRIDE CAP_NET_BROADCAST CAP_PERFMON CAP_SYS_BOOT CAP_SYS_MODULE CAP_SYS_NICE CAP_SYS_PACCT CAP_SYS_PTRACE CAP_SYS_RAWIO CAP_SYS_RESOURCE CAP_SYS_TIME CAP_SYSLOG CAP_WAKE_ALARM
"""

proc createNspawn(name: string, pulse = false) =
  var conf = nspawnConf(name)
  if pulse:
    conf &= "\n[Files]\nBind=/run/pulse.native\n"
    proxy "pulse-proxy:pulse:pulse-access:0660", "/run/pulse.native", bindTo="",
          "/run/user/1000/pulse/native", "1min", targetService="",
          "Pulseaudio socket proxy service"
  writeFile fmt"/etc/systemd/nspawn/{name}.nspawn", [conf]
  addPackageUnless "systemd-container", "/usr/bin/systemd-nspawn"
  # TODO run machinectl

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
