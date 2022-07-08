import std/[sequtils, strformat, strutils, os, osproc, posix]

type Strs* = seq[string]
type UserInfo* = tuple[home: string, uid: Uid, gid: Gid]

var packagesToInstall*: Strs
var enableUnits*: Strs
var startUnits*: Strs
var systemdReload*: bool

proc enableAndStart*(units: varargs[string]) =
  for unit in units:
    enableUnits.add unit
    startUnits.add unit

proc writeFile*(filename: string, content: openarray[string]) =
  let (dir, _, _) = filename.splitFile
  createDir dir
  filename.writeFile content.join("\n")

proc setPermissions(fullPath: string, user: UserInfo, permissions: int) =
  if chown(fullPath, user.uid, user.gid) == -1:
    echo fmt"chown({fullPath}) failed: {strerror(errno)}"
  if chmod(fullPath, 0o755) == -1:
    echo fmt"chmod({fullPath}) failed: {strerror(errno)}"

proc writeAsUser*(user: UserInfo, filename, content: string,
                  permissions: int = 0o644) =
  for part in filename.parentDirs(fromRoot = true, inclusive = false):
    let absolute = user.home.joinPath part
    if not absolute.existsOrCreateDir:
      setPermissions(absolute, user, 0o755)
  let absolute = user.home.joinPath filename
  absolute.writeFile content
  setPermissions(absolute, user, permissions)

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

proc userInfo*(user: string): UserInfo =
  let pw = user.getpwnam
  if pw == nil:
    echo fmt"Unknown user {user}"
    quit 1
  return (home: $pw.pw_dir, uid: pw.pw_uid, gid: pw.pw_gid)
