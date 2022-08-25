import std/[strformat, posix]
import utils

proc createKey(user: userInfo, keyfile: string) =
  var command = fmt"ssh-keygen -t ed25519 -f '{user.home}/.ssh/{keyfile}' -N ''"
  let current_uid = getuid()
  if current_uid == user.uid:
    if execShellCmd(command) != 0:
      quit 1
  elif current_uid == 0:
    runCmd("su", "-c", command, user.name)
  else:
    echo("User ", current_uid, " cannot create key for ", user.name)
    quit 1

func systemdRunArgs(machine: string, command: varargs[string]): seq[string] =
  @["--machine=" & machine, "--wait", "--service-type=exec" "-PGq"] & @command

proc outputOfCommandAt(machine, input, command: varargs[string]): seq[string] =
  outputOfCommand(input, "systemd-run", systemdRunArgs(machine, command))

proc writeFileTo(machine, path, owner, mode: string) =
  var args = @["install", "-D"]
  if owner != '':
    args &= ["-o", owner]
  if mode != '':
    args &= ["-m", mode]
  args &= ["/dev/stdin", 
  for line in outputOfCommandAt(machine, 

proc sshOVPN(user: userInfo, machine: string) =
  
