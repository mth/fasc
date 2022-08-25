import std/[strformat, os, posix]
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

proc writeFileTo(machine, dir, name, content: string; mode = 0o644;
                 user = "root"; group = "root") =
  writeTo(machine, dir, (name: name, mode: mode,
                         user: user, group: group, content: content))

#proc sshOVPN(user: userInfo, machine: string) =

writeFileTo("dev", "/root", ".ssh/authorized_keys", "ssh-ed25519 AAAA", 0o600)
