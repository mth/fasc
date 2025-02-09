# This file is part of FASC, the FAst System Configurator.
#
# Copyright (C) 2022-2024 Madis Janson
#
# FASC is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# FASC is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with FASC. If not, see <https://www.gnu.org/licenses/>.

import std/[sequtils, streams, parseutils, strformat, strutils,
            tables, os, osproc, posix]

type StrMap* = Table[string, string]
type UpdateMap* = Table[string, proc(old: string): string]
type UserInfo* = tuple[user: string, home: string, uid: Uid, gid: Gid]

var packagesToInstall*: seq[string]
var enableUnits*: seq[string]
var startUnits*:  seq[string]
var systemdReload*: bool
var aptUpdate*: bool
var distroDetected = false
var hasDebianVersion = false
var hasFedoraRelease = false

const resourceDir = currentSourcePath().parentDir / "resources"

let fedoraPackageMap = [
  ("openssh-client", "openssh-clients"),
  ("fonts-unifont", "unifont-ttf-fonts"),
  ("fonts-terminus-otb", ""),
  ("brightness-udev", ""),
  ("libnss3-tools", "nss-tools"),
  ("intel-media-va-driver", "libva-intel-media-driver"),
  ("xwayland", "xorg-x11-server-Xwayland"),
  ("qtwayland5", ""),
  ("nim", ""),
  ("git", "git-core"),
  ("xmahjongg", "gnome-mahjongg"),
  ("build-essential", "gcc"),
  ("nbd-client", "nbd"),
].toTable

proc detectDistro() =
  if not distroDetected:
    hasDebianVersion = fileExists("/etc/debian_version")
    hasFedoraRelease = fileExists("/usr/lib/fedora-release")
    distroDetected = true

proc isDebian*(): bool =
  detectDistro()
  return hasDebianVersion 

proc isFedora*(): bool =
  detectDistro()
  return hasFedoraRelease

proc readResource*(filename: string): string =
  readFile(resourceDir / filename)

proc readResourceDir*(dirname: string): seq[(string, string)] =
  for kind, file in walkDir(resourceDir / dirname):
    if kind == pcFile:
      result.add (file.extractFilename, readFile(file))

proc nonEmptyParam*(params: StrMap, key: string): string =
  result = params.getOrDefault(key)
  if result.len == 0:
    echo fmt"Expected parameter {key}=<{key}>"
    quit 1

func group*(user: UserInfo): string =
  let group = getgrgid(user.gid)
  if group == nil:
    return $user.gid
  return $group.gr_name

func groupId*(group: string): int =
  let description = getgrnam(group)
  if description == nil:
    return -1
  return description.gr_gid.int

proc readSymlink*(symlink: string): string =
  try:
    return expandSymlink(symlink)
  except:
    discard

proc sparseFile*(filename: string, size: Off, permissions: Mode) =
  let fd = open(filename, O_CREAT or O_EXCL or O_WRONLY, permissions)
  var error: cint = 0
  if fd != -1:
    if fd.ftruncate(size) != 0:
      error = errno
    if fd.close == 0 and error == 0:
      return
  if error == 0:
    error = errno
  if fd != -1:
    discard unlink(filename)
  raise newException(OSError, fmt"truncate({filename}, {size}) failed: {strerror(error)}")

proc setPermissions*(fullPath: string, permissions: Mode) =
  if chmod(fullPath, permissions) == -1:
    echo fmt"chmod({fullPath}) failed: {strerror(errno)}"

proc setPermissions*(fullPath: string, uid: Uid, gid: Gid, permissions: Mode) =
  if chown(fullPath, uid, gid) == -1:
    echo fmt"chown({fullPath}) failed: {strerror(errno)}"
  setPermissions fullPath, permissions

proc setPermissions*(fullPath: string, user: UserInfo, permissions: Mode) =
  setPermissions fullPath, user.uid, user.gid, permissions

proc groupExec*(fullPath: string, user: UserInfo) =
  if chown(fullPath, 0, user.gid) == -1:
    echo fmt"chgrp({fullPath}) failed: {strerror(errno)}"
  setPermissions fullPath, 0o750

proc sync(f: File) =
  if f.getFileHandle.fsync != 0:
    raise newException(OSError, $strerror(errno))

proc writeFileSynced*(filename, content: string; openMode: FileMode = fmWrite) =
  let f = open(filename, fmWrite)
  defer: f.close
  f.write content
  f.sync

proc safeFileUpdate*(filename, content: string, permissions: Mode = 0o644) =
  echo "Updating ", filename
  var ts: Timespec
  discard clock_gettime(CLOCK_REALTIME, ts)
  let tmpFile = filename & ".tmp" & ts.tv_nsec.int64.toHex
  writeFileSynced(tmpFile, content)
  setPermissions(tmpFile, permissions)
  moveFile(tmpFile, filename)

proc writeFileIfNotExists*(filename, content: string; force = false): bool {.discardable.} =
  if not force and filename.fileExists:
    echo fmt"Retaining existing {filename}"
  else:
    echo fmt"Created {filename}"
    filename.writeFileSynced content
    return true

proc listDir*(path: string): seq[string] =
  for _, subdir in walkDir(path):
    result.add subdir

proc writeFile*(filename: string, content: openarray[string],
                force = false, permissions: Mode = 0o644): bool {.discardable.} =
  let (dir, _, _) = filename.splitFile
  createDir dir
  result = writeFileIfNotExists(filename, content.join("\n"), force)
  setPermissions(filename, permissions)

proc createParentDirs*(user: UserInfo, filename: string) =
  for part in filename.parentDirs(fromRoot = true, inclusive = false):
    var absolute = user.home / part
    absolute.removeSuffix '/'
    if not absolute.existsOrCreateDir:
      setPermissions absolute, user, 0o755

proc writeAsUser*(user: UserInfo, filename, content: string,
                  permissions: Mode = 0o644, force = false) =
  createParentDirs(user, filename)
  let absolute = user.home / filename
  if force:
    safeFileUpdate absolute, content, permissions
  else:
    writeFileIfNotExists absolute, content
  setPermissions absolute, user, permissions

proc runCmd(exitOnError: bool, command: string, args: openarray[string]) =
  let process = startProcess(command, "", args, nil, {poParentStreams, poUsePath})
  let exitCode = process.waitForExit
  if exitCode != 0:
    echo fmt"Executing {command} with {args} failed with exit code {exitCode}"
    if exitOnError:
      quit 1
  process.close

proc runCmd*(command: string, args: varargs[string]) =
  runCmd(true, command, args)

proc runCmd*(user: UserInfo, exitOnError: bool, command: string, args: varargs[string]) =
  if getuid() == user.uid:
    runCmd(exitOnError, command, args)
  else:
    runCmd(exitOnError, "systemd-run",
      @["-qPGp", "User=" & $user.uid, "--working-directory=" & user.home,
        "--wait", "--service-type=exec", command] & @args)

proc outputOfCommand*(inputString: string; hasInput: bool;
                      command: string; args: openarray[string]): seq[string] =
  let process = startProcess(command, args = args,
                             options = {poStdErrToStdOut, poUsePath})
  if hasInput:
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

proc outputOfCommand*(inputString, command: string; args: varargs[string]): seq[string] =
  outputOfCommand(inputString, inputString.len > 0, command, args)

proc aptInstallNow*(packages: varargs[string]) =
  packagesToInstall.add packages
  if packagesToInstall.len > 0:
    if aptUpdate and isDebian():
      runCmd "apt-get", "update"
      aptUpdate = false
    if isFedora():
      for i in countdown(packagesToInstall.len - 1, 0):
        let name = packagesToInstall[i]
        if name in fedoraPackageMap:
          let pkg = fedoraPackageMap[name]
          if pkg != "":
            packagesToInstall[i] = pkg
          else:
            packagesToInstall.delete i
      runCmd("dnf", @["-y", "install"] & packagesToInstall & "--setopt=install_weak_deps=False")
    else:
      runCmd("apt-get", @["install", "-y", "--no-install-recommends"] & packagesToInstall)
    packagesToInstall.reset

proc checkSystemdReload() =
  if systemdReload:
    runCmd("systemctl", "daemon-reload")
    systemdReload = false

proc enableAndStart*(units: varargs[string]) =
  checkSystemdReload()
  for unit in units:
    enableUnits.add unit
    startUnits.add unit

proc commitQueue*() =
  aptInstallNow()
  checkSystemdReload()
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

proc addPackageUnless*(packageName, requiredPath: string, commit = false) =
  if not requiredPath.fileExists:
    packagesToInstall.add packageName
    if commit:
      commitQueue()

proc userInfo(pw: ptr Passwd, name: string): UserInfo =
  if pw == nil:
     raise newException(KeyError, fmt"Unknown user {name}")
  (user: $pw.pw_name, home: $pw.pw_dir, uid: pw.pw_uid, gid: pw.pw_gid)

proc userInfo*(name: string): UserInfo =
  userInfo(getpwnam(name), name)

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
  try:
    return userInfo(pw, name)
  except KeyError as e:
    echo e.msg
    quit 1

proc fileContains*(filename, line: string): bool =
  if filename.fileExists:
    for fileLine in lines(filename):
      if fileLine.strip == line:
        return true

proc appendToFile*(filename, contents: string, mode: Mode) =
  var f = if filename.fileExists:
            open filename, fmAppend
          else:
            createDir filename.parentDir
            open filename, fmWrite
  try:
    f.write contents
    f.sync
  finally:
    f.close
  filename.setPermissions mode

proc appendMissing*(filename: string, needed: openarray[(string, string)],
                    create = false): bool =
  var addLines = @needed
  if not create or filename.fileExists:
    for line in lines(filename):
      var idx = addLines.len
      while idx > 0:
        idx.dec
        let (prefix, addLine) = addLines[idx]
        if (if prefix.len != 0: line.startsWith prefix
            else: line == addLine):
          addLines.delete idx
  if addLines.len == 0:
    return false
  var f = open(filename, fmAppend)
  defer: f.close
  for (prefix, line) in addLines:
    f.writeLine(prefix & line)
  f.sync
  return true

proc appendMissing*(filename: string, needed: varargs[string]): bool =
  appendMissing(filename, needed.toSeq.mapIt(("", it)))

proc appendRcLocal*(needed: varargs[string]) =
  let rc = "/etc/rc.local"
  rc.writeFileIfNotExists "#!/bin/sh\n\n"
  rc.setPermissions 0o755
  discard rc.appendMissing needed

proc modifyProperties*(filename: string, update: UpdateMap, comment = '#'): bool =
  var updatedConf: seq[string]
  var updateMap = update
  for line in lines(filename):
    updatedConf.add line
    let notSpace = line.skipWhitespace
    if notSpace >= line.len or line[notSpace] == comment:
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
                       onlyEmpty = true, comment = '#'): bool =
  var updateMap: UpdateMap
  for (key, value) in update:
    updateMap[key] = stringFunc(value, onlyEmpty)
  return modifyProperties(filename, updateMap, comment)

proc sudoNoPasswd*(user: UserInfo, envKeep: string, paths: varargs[string]) =
  var rules: seq[(string, string)]
  for path in paths:
    path.groupExec user
    if envKeep.len != 0:
      rules &= ("Defaults!" & path & ' ', "env_keep=\"" & envKeep & '"')
    rules &= ("", user.user & " ALL=(root:root) NOPASSWD: " & path)
  addPackageUnless "sudo", "/usr/bin/sudo"
  aptInstallNow()
  discard appendMissing("/etc/sudoers", rules)

proc updateMime*() =
  if isFedora():
    runCmd "update-mime-database", "/usr/share/mime"
  else:
    runCmd "update-mime"

proc addSystemUser*(user, group, home: string) =
  var arguments = @["-r", "-s", "/usr/sbin/nologin"]
  if group != "":
    arguments &= ["-Ng", group]
  else:
    arguments &= "-U"
  if home != "":
    arguments &= ["-d", home]
  arguments &= user
  runCmd "useradd", arguments
