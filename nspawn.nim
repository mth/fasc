import std/[os, tables]
import utils

func runOnScriptSource(command, machine, remoteCommand: string): string = """
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
  runCmd("machinectl", machine, "copy-to", fascPath, "/usr/local/bin/fasc")

proc fascAt(machine: string, arguments: varargs[string]) =
  runCmd("systemd-run", systemdRunArgs(machine, "/usr/local/bin/fasc" & @arguments))

# TODO - configure nftables, resolved
proc containerOVPN*(args: StrMap) =
  let machine = args.nonEmptyParam("machine")
  args.userInfo.sudoNoPasswd(
    runOnScript("/usr/bin/ovpn-" & machine, machine, "/usr/bin/ovpn"),
    runOnScript("/usr/bin/kill-vpn-" & machine, machine, "/usr/bin/kill-vpn"))
  machine.fascAt("ovpn", "nosudo")
