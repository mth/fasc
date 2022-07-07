import std/[sequtils, strformat, strutils, os, osproc, posix]

var packagesToInstall*: seq[string]
var enableUnits*: seq[string]
var startUnits*: seq[string]
var systemdReload*: bool

proc enableAndStart*(units: varargs[string]) =
  for unit in units:
    enableUnits.add unit
    startUnits.add unit

proc writeFile*(filename: string, content: openarray[string]) =
  let (dir, _, _) = filename.splitFile
  createDir dir
  writeFile(filename, content.join("\n"))

proc runCmd*(command: string, args: varargs[string]) =
  let process = startProcess(command, "", args, nil, {poParentStreams, poUsePath})
  let exitCode = process.waitForExit
  if exitCode != 0:
    echo fmt"Executing {command} with {args} failed with exit code {exitCode}"
    quit 1

proc runQueuedCommands*() =
  if packagesToInstall.len > 0:
    runCmd("apt-get", @["install", "-y", "--no-install-recommends"] &
           packagesToInstall.deduplicate)
  if systemdReload:
    runCmd("systemctl", "daemon-reload")
  if enableUnits.len > 0:
    runCmd("systemctl", "enable" & enableUnits.deduplicate)
  if startUnits.len > 0:
    runCmd("systemctl", "start" & startUnits.deduplicate)

proc userInfo*(user: string): (string, Uid, Gid) =
  let pw = user.getpwnam
  if pw == nil:
    echo fmt"Unknown user {user}"
    quit 1
  return ($pw.pw_dir, pw.pw_uid, pw.pw_gid)
