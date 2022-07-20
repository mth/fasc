import std/[sequtils, streams, parseutils, strformat, strutils,
            tables, os, osproc, posix]

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

proc listDir*(path: string): seq[string] =
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

proc modifyProperties*(filename: string,
                       update: Table[string, proc(old: string): string]) =
  var updatedConf: seq[string]
  var updateMap = update
  var modified = false
  for line in lines(filename):
    updatedConf.add line
    let notSpace = line.skipWhitespace
    if notSpace >= line.len or line[notSpace] == '#':
      continue
    var assign = line.skipUntil('=', notSpace)
    var nameEnd = assign - 1
    while line[nameEnd] in Whitespace:
      nameEnd.dec
    let name = line[notSpace..nameEnd]
    if name in updateMap:
      assign.inc line.skipWhitespace(assign + 1)
      let value = line[assign+1..^1].strip(leading=false)
      let updated = updateMap[name](value)
      updateMap.del name
      echo("old=", value, " new=", updated)
      if updated != value:
        updatedConf[^1] = line[0..<notSpace] &
          name & line[nameEnd+1..assign] & updated
        echo("Updated ", updatedConf[^1])
        modified = true
  for key, updater in updateMap:
    let value = updater("")
    if value.len != 0:
      echo("Adding value ", key, '=', value)
      updatedConf.add(key & '=' & value)
      modified = true
  if modified:
    writeFile(filename, updatedConf.join("\n") & '\n')

func stringFunc(value: string, onlyEmpty: bool): proc(old: string) : string =
  return proc(old: string): string = (if not onlyEmpty or old.len == 0: value
                                      else: old)

proc modifyProperties*(filename: string, update: openarray[(string, string)],
                       onlyEmpty = true) =
  var updateMap: Table[string, proc(old: string): string]
  for (key, value) in update:
    updateMap[key] = stringFunc(value, onlyEmpty)
  modifyProperties(filename, updateMap)
