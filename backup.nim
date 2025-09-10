# This file is part of FASC, the FAst System Configurator.
#
# Copyright (C) 2022-2025 Madis Janson
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

import std/[base64, strformat, strutils, os, tables]
import services, utils, netutil

const backupMountPoint* = "/media/backupstore"
const resticWrapper = readResource("backup/restic.sh")
const maxRuntime* = "RuntimeMaxSec=12h"
const resticPort = "448"

proc readRandom(buf: var openarray[byte]) =
  var rand = open("/dev/urandom")
  defer: close(rand)
  var pos = 0
  while pos < buf.len:
    let count = rand.readBytes(buf, pos, buf.len - pos)
    if count <= 0:
      raise newException(IOError, "Random error")
    pos += count

proc bcryptPassword(password: string): string =
  var salt: array[0..21, byte]
  readRandom salt
  let saltB64 = salt.encode.replace('+', '.')
  # bcrypt hash using perl to access libcrypt without linking it
  return outputOfCommand("", "perl", "-e", "print(crypt($ARGV[0], $ARGV[1]))",
                         password, fmt"$2a$06${saltB64}$")[0]

proc htpassword(filename, user, password: string) =
  var updatedConf: seq[string]
  let prefix = user & ':'
  let userPass = prefix & bcryptPassword(password)
  for line in lines(filename):
    if not line.startsWith(prefix):
      updatedConf.add line
  updatedConf.add userPass
  safeFileUpdate(filename, updatedConf.join("\n") & '\n')

func mountUnit(description, unit, what, where: string): string = fmt"""
[Unit]
Description={description}
{unit}
[Mount]
What={what}
Where={where}
"""

proc createBackupUser*(name, home: string; nbd = true): UserInfo =
  try:
    return name.userInfo # already exists
  except KeyError:
    let nbdGid = if nbd: groupId("nbd")
                 else: -1
    let group = if nbdGid != -1: $nbdGid
                else: ""
    addSystemUser name, group, home
    return name.userInfo

func mountUnitName(mount: string): string =
  mount.strip(chars={'/'}).replace('/', '-') & ".mount" 

proc onDemandMount(description, dev, mount: string): string =
  result = mount.mountUnitName
  let unitFile = "/etc/systemd/system/" & result
  if dev == "":
    if unitFile.fileExists:
      return result
    echo "Device mount point not defined"
    quit 1
  var what = dev
  if what.startsWith('/'):
    what = outputOfCommand("", "blkid", "-o", "value", "-s", "UUID", dev).join.strip
  var unit = mountUnit(description, "StopWhenUnneeded=true\n", dev, mount)
  unit &= "Options=noatime,noexec,nodev,noauto\n"
  writeFile unitFile, [unit], true

proc backupMount*(dev: string): string =
  onDemandMount "Backup store mount", dev, backupMountPoint

proc backupClientService*(name, description, command: string) =
  calendarTimer name, description, "*-*-02/4 05:05:05", command

proc getHostName(args: StrMap, key: string): string =
  result = args.getOrDefault key
  if result.len == 0:
    return readFile("/etc/hostname").strip

proc resticTLSCert(args: StrMap, restic: UserInfo, force = false): string =
  const sslDir = "/etc/ssl/restic"
  const private_key = sslDir & "/private.der"
  const public_key = sslDir & "/public.der"
  if not force and private_key.fileExists and public_key.fileExists:
    echo "Not going to replace existing restic TLS key: ", private_key
  else:
    let hostname = args.getHostName "hostname"
    var ext = "subjectAltName = "
    let ip = args.getOrDefault "serverip"
    if ip.len != 0:
      ext &= "IP:" & ip & ','
    ext &= "DNS:" & hostname
    echo "Creating ", public_key, " certificate with ", ext
    createDir sslDir
    runCmd "openssl", "req", "-newkey", "rsa:2048", "-nodes", "-x509",
           "-keyout", private_key, "-out", public_key, "-days", "1826",
           "-subj", &"/O=restic/OU=server/CN={hostname}", "-addext", ext
    setPermissions sslDir, 0, restic.gid, 0o750
    setPermissions private_key, restic, 0o400
    setPermissions public_key, 0, restic.gid, 0o440
  return fmt" --tls --tls-cert {public_key} --tls-key {private_key}"

const resticHome = backupMountPoint / "restic"
const resticPassFile = "/etc/ssl/restic/rpasswd"

proc installResticServer*(args: StrMap) =
  let restic = createBackupUser("restic", resticHome, false)
  if "recert" in args:
    discard args.resticTLSCert(restic, true)
    return
  let dev = args.getOrDefault "backup-dev"
  downloadResticServer restic
  let tlsOpt = args.resticTLSCert restic
  writeFileIfNotExists resticPassFile, ""
  let mountUnit = backupMount dev
  runCmd "systemctl", "daemon-reload"
  runCmd "systemctl", "start", mountUnit
  try:
    createDir resticHome
    setPermissions resticHome, restic, 0o700
  finally:
    runCmd "systemctl", "stop", mountUnit
  addService "restic-server", "Restic server", [],
    "/opt/restic/rest-server --private-repos --path " & resticHome &
    " --htpasswd-file " & resticPassFile & tlsOpt & " --listen unix:/run/restic/socket",
    flags={s_sandbox, s_private_dev, s_call_filter},
    options=["User=restic", "Group=restic", "ReadWritePaths=" & resticHome,
             "UMask=027", maxRuntime, "RuntimeDirectory=restic"],
    unitOptions=[&"RequiresMountsFor={backupMountPoint}", &"BindsTo={mountUnit}",
                 &"After={mountUnit}", "StopWhenUnneeded=true"]
  let ip = args.getOrDefault "serverip"
  proxy "restic-proxy", ip & ':' & resticPort, "", "/run/restic/socket", "5min",
        "restic-server.service", "Restic server proxy", waitFor=true
  enableAndStart "restic-proxy.socket"

proc resticUser*(args: StrMap) =
  let resticUser = try: userInfo "restic"
                   except: ("", "", 0, 0)
  if resticUser.user.len == 0 or
     not fileExists("/etc/systemd/system/" & backupMountPoint.mountUnitName):
    echo "Missing restic, please run restic-server first"
    quit 1
  let username = args.nonEmptyParam("backup-user")
  stderr.write fmt"Restic user {username} password: "
  let pass = stdin.readLine
  htpassword resticPassFile, username, pass
  setPermissions resticPassFile, resticUser, 0o600

proc resticClient*(args: StrMap) =
  const wrapperFile = "/usr/local/sbin/restic"
  let has_wrapperFile = wrapperFile.fileExists
  let repositoryURI = args.getOrDefault "repo"
  if not has_wrapperFile and repositoryURI.len != 0:
    let wrapper = resticWrapper.multiReplace(("{REPOSITORY}", repositoryURI),
                                  ("{REST_USERNAME}", ""), ("{REST_PASSWORD}", ""))
    writeFile wrapperFile, [wrapper], permissions=0o700
  else:
    const server_pem = "/etc/backup/restic-server.pem"
    let has_server_pem = server_pem.fileExists
    var server = ""
    if not (has_server_pem and has_wrapperFile):
      server = args.nonEmptyParam "rest-server"
      if ':' notin server:
        server &= ':'
        server &= resticPort
    let username = args.getHostName "backup-user"
    if not has_server_pem:
      let certs = try: server.fetchTLSCerts
                  except:
                    sleep 1
                    server.fetchTLSCerts
      writeFile server_pem, [certs[0]]
      setPermissions "/etc/backup", 0o700
    if not has_wrapperFile:
      # generates random password for server, that can be used to add user to the server
      var pass: array[0..11, byte]
      readRandom pass
      let passB64 = pass.encode
      echo &"Generated password {passB64} for {username}"
      let wrapper = resticWrapper.multiReplace(("{REPOSITORY}", &"rest:https://{server}/{username}/"),
                                    ("{REST_USERNAME}", username), ("{REST_PASSWORD}", passB64))
      writeFile wrapperFile, [wrapper], permissions=0o700
  addPackageUnless "restic", "/usr/bin/restic"
  backupClientService "restic", "Start restic client", wrapperFile & " backup-and-forget-no-sleep"
  commitQueue()
  writeFile "/etc/backup/.restic-repo-password", [], permissions=0o600
  echo "If the restic repository didn't already exist, fill /etc/backup/.restic-repo-password and run restic init"
