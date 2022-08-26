import std/[strformat, os, posix]
import mktar, utils

proc createKey(user: UserInfo, keyfile: string) =
  var command = fmt"ssh-keygen -t ed25519 -f '{user.home}/.ssh/{keyfile}' -N ''"
  let current_uid = getuid()
  if current_uid == user.uid:
    if execShellCmd(command) != 0:
      quit 1
  elif current_uid == 0:
    runCmd("su", "-c", command, user.user)
  else:
    echo("User ", current_uid, " cannot create key for ", user.user)
    quit 1

func systemdRunArgs(machine: string, command: openarray[string]): seq[string] =
  @["--machine=" & machine, "--wait", "--service-type=exec", "-PGq"] & @command

proc outputOfCommandAt(machine, input: string; command: varargs[string]): seq[string] =
  outputOfCommand(input, "systemd-run", systemdRunArgs(machine, command))

proc writeTo(machine, dir: string; files: varargs[TarRecord]) =
  discard outputOfCommandAt(machine, tar(files), "tar", "-C", dir, "-x")

proc sshOVPN(user: UserInfo, machine: string) =
  let pubKeyFile = user.home / ".ssh/ovpn.pub"
  if not fileExists(pubKeyFile):
    user.createKey "ovpn"
  let pubKey = readFile(pubKeyFile)
  machine.writeTo("/root", [(".ssh/", 0o700, ""),
    (".ssh/authorized_keys", 0o600, "command=\"/usr/bin/ovpn\" " & pubKey)].tarRecords)
