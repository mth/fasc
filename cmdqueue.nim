import std/[sequtils, streams, strformat, strutils, os, osproc, posix]

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

proc writeFileIfNotExists*(filename, content: string; force: bool) =
  if not force and filename.fileExists:
    echo fmt"Retaining existing {filename}"
  else:
    echo fmt"Created {filename}"
    filename.writeFile content

proc listDir*(path): seq[string] =
  for kind, subdir in walkDir(path):
    result.add subdir

proc writeFile*(filename: string, content: openarray[string], force = false) =
  let (dir, _, _) = filename.splitFile
  createDir dir
  writeFileIfNotExists(filename, content.join("\n"), force)

proc setPermissions(fullPath: string, user: UserInfo, permissions: int) =
  if chown(fullPath, user.uid, user.gid) == -1:
    echo fmt"chown({fullPath}) failed: {strerror(errno)}"
  if chmod(fullPath, 0o755) == -1:
    echo fmt"chmod({fullPath}) failed: {strerror(errno)}"

proc writeAsUser*(user: UserInfo, filename, content: string,
                  permissions: int = 0o644, force = false) =
  for part in filename.parentDirs(fromRoot = true, inclusive = false):
    var absolute = user.home / part
    absolute.removeSuffix '/'
    if not absolute.existsOrCreateDir:
      setPermissions(absolute, user, 0o755)
  let absolute = user.home / filename
  writeFileIfNotExists(absolute, content, force)
  setPermissions(absolute, user, permissions)

proc runCmd*(command: string, args: varargs[string]) =
  let process = startProcess(command, "", args, nil, {poParentStreams, poUsePath})
  let exitCode = process.waitForExit
  if exitCode != 0:
    echo fmt"Executing {command} with {args} failed with exit code {exitCode}"
    quit 1
  process.close

proc outputOfCommand*(inputString, command: string;
                      args: varargs[string]): seq[string] =
  let process = startProcess(command, args = args,
                             options = {poStdErrToStdOut, poUsePath})
  if inputString.len > 0:
    let input = process.inputStream
    input.write inputString
    input.flush
    input.close
  var line: string
  let output = process.outputStream
  while output.readLine line:
    result.add line
  let exitCode = process.waitForExit
  if exitCode != 0:
    echo(command, " exit code ", exitCode, " output: ")
    echo result.join("\n")
    quit 1
  process.close

proc runQueuedCommands*() =
  if packagesToInstall.len > 0:
    runCmd("apt-get", @["install", "-y", "--no-install-recommends"] &
           packagesToInstall.deduplicate)
  if systemdReload:
    runCmd("systemctl", "daemon-reload")
  if enableUnits.len > 0:
    let units = enableUnits.deduplicate
    echo("Enabling services: ", units.join(", "))
    runCmd("systemctl", "enable" & units)
  if startUnits.len > 0:
    let units = startUnits.deduplicate
    echo("Starting services: ", units.join(", "))
    runCmd("systemctl", "start" & units)

proc userInfo*(user: string): UserInfo =
  let pw = user.getpwnam
  if pw == nil:
    echo fmt"Unknown user {user}"
    quit 1
  return (home: $pw.pw_dir, uid: pw.pw_uid, gid: pw.pw_gid)
