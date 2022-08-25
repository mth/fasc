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

proc sshOVPN(user: userInfo, machine: string) =
  
