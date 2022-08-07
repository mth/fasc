import std/[sequtils, streams, parseutils, strformat, strutils,
            tables, os, osproc, posix]

type StrMap* = Table[string, string]
type UpdateMap* = Table[string, proc(old: string): string]
type UserInfo* = tuple[user: string, home: string, uid: Uid, gid: Gid]

var packagesToInstall*: seq[string]
var enableUnits*: seq[string]
var startUnits*:  seq[string]
var systemdReload*: bool

const resourceDir = currentSourcePath().parentDir / "resources"

proc readResource*(filename: string): string =
  readFile(resourceDir / filename)

proc readResourceDir*(dirname: string): seq[(string, string)] =
  for kind, file in walkDir(resourceDir / dirname):
    if kind == pcFile:
      result.add (file.extractFilename, readFile(file))

proc enableAndStart*(units: varargs[string]) =
  for unit in units:
    enableUnits.add unit
    startUnits.add unit

proc setPermissions*(fullPath: string, permissions: Mode) =
  if chmod(fullPath, permissions) == -1:
    echo fmt"chmod({fullPath}) failed: {strerror(errno)}"

proc setPermissions(fullPath: string, user: UserInfo, permissions: Mode) =
  if chown(fullPath, user.uid, user.gid) == -1:
    echo fmt"chown({fullPath}) failed: {strerror(errno)}"
  setPermissions(fullPath, permissions)

proc writeFileSynced*(filename, content: string) =
  let f = open(filename, fmWrite)
  defer: f.close
  f.write content
  if f.getFileHandle.fsync != 0:
    raise newException(OSError, $strerror(errno))

proc safeFileUpdate*(filename, content: string, permissions: Mode = 0o644) =
  echo "Updating ", filename
  var ts: Timespec
  discard clock_gettime(CLOCK_REALTIME, ts)
  let tmpFile = filename & ".tmp" & ts.tv_nsec.int64.toHex
  writeFileSynced(tmpFile, content)
  setPermissions(tmpFile, permissions)
  moveFile(tmpFile, filename)

proc writeFileIfNotExists*(filename, content: string; force: bool) =
  if not force and filename.fileExists:
    echo fmt"Retaining existing {filename}"
  else:
    echo fmt"Created {filename}"
    filename.writeFileSynced content

proc listDir*(path: string): seq[string] =
  for _, subdir in walkDir(path):
    result.add subdir

proc writeFile*(filename: string, content: openarray[string], force = false) =
  let (dir, _, _) = filename.splitFile
  createDir dir
  writeFileIfNotExists(filename, content.join("\n"), force)

proc writeAsUser*(user: UserInfo, filename, content: string,
                  permissions: Mode = 0o644, force = false) =
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

proc aptInstallNow*(packages: varargs[string]) =
  packagesToInstall.add packages
  if packagesToInstall.len > 0:
    runCmd("apt-get", @["install", "-y", "--no-install-recommends"] & packagesToInstall)
    packagesToInstall.reset

proc commitQueue*() =
  aptInstallNow()
  if systemdReload:
    runCmd("systemctl", "daemon-reload")
    systemdReload = false
  if enableUnits.len > 0:
    let units = enableUnits.deduplicate
    echo("Enabling services: ", units.join(", "))
    runCmd("systemctl", "enable" & units)
    enableUnits.reset
  if startUnits.len > 0:
    let units = startUnits.deduplicate
    echo("Starting services: ", units.join(", "))
    runCmd("systemctl", "start" & units)
    startUnits.reset
  sync()

proc userInfo*(param: StrMap): UserInfo =
  var pw: ptr Passwd
  var uid = getuid()
  var name: string
  if uid == 0:
    name = param.getOrDefault("user")
    if name == "":
      while (pw = getpwent(); pw != nil):
        if pw.pw_uid != 65534: # ignore nobody
          uid = max(uid, pw.pw_uid)
      if uid != 1000:
        echo fmt"Maximum uid in passwd {uid} > 1000, couldn't guess user"
        quit 1
      endpwent()
  if name != "":
    pw = getpwnam(name.cstring)
  else:
    pw = getpwuid(uid)
    name = $uid
  if pw == nil:
    echo fmt"Unknown user {name}"
    quit 1
  return (user: $pw.pw_name, home: $pw.pw_dir, uid: pw.pw_uid, gid: pw.pw_gid)

proc appendMissing*(filename: string, needed: varargs[string]): bool =
  var addLines = @needed
  for line in lines(filename):
    let idx = addLines.find line.strip
    if idx >= 0:
      addLines.delete idx
  if addLines.len == 0:
    return false
  var f = open(filename, fmAppend)
  defer: f.close
  for line in addLines:
    f.writeLine line
  return true

proc modifyProperties*(filename: string, update: UpdateMap): bool =
  var updatedConf: seq[string]
  var updateMap = update
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
      if updated != value:
        updatedConf[^1] = line[0..<notSpace] &
          name & line[nameEnd+1..assign] & updated
        result = true
  for key, updater in updateMap:
    let value = updater("")
    if value.len != 0:
      updatedConf.add(key & '=' & value)
      result = true
  if result:
    safeFileUpdate(filename, updatedConf.join("\n") & '\n')

func stringFunc*(value: string, onlyEmpty = false): proc(old: string): string =
  return proc(old: string): string = (if not onlyEmpty or old.len == 0: value
                                      else: old)

proc modifyProperties*(filename: string, update: openarray[(string, string)],
                       onlyEmpty = true): bool =
  var updateMap: UpdateMap
  for (key, value) in update:
    updateMap[key] = stringFunc(value, onlyEmpty)
  return modifyProperties(filename, updateMap)

proc nonEmptyParam*(params: StrMap, key: string): string =
  result = params.getOrDefault(key)
  if result.len == 0:
    echo fmt"Expected parameter {key}=<{key}>"
    quit 1
