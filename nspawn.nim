import std/[strformat, strutils, os, posix]
import utils

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

proc writeFilesTo(machine, dir: string; files: openarray[(string, int, string)];
                  user = "root"; group = "root") =
  var records: seq[TarRecord]
  for (path, mode, content) in files:
    let (name, flag) = if path.endsWith '/': (path[0..^2], TAR_DIR_TYPE)
                       else: (path, TAR_FILE_TYPE)
    records &= (name: name, flag: flag, mode: mode,
                user: user, group: group, content: content)
  writeTo(machine, dir, records)

proc sshOVPN(user: UserInfo, machine: string) =
  let pubKeyFile = user.home / ".ssh/ovpn.pub"
  if not fileExists(pubKeyFile):
    user.createKey "ovpn"
  let pubKey = readFile(pubKeyFile)
  machine.writeFilesTo("/root", [(".ssh/", 0o700, ""),
    (".ssh/authorized_keys", 0o600, "command=\"/usr/bin/ovpn\" " & pubKey)])
