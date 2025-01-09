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
import services, utils, github

const backupMountPoint = "/media/backupstore"
const rotateBackup = readResource("backup/rotate-backup.sh")
const backupClient = readResource("backup/nbd-backup")
const backupConf   = readResource("backup/nbd-backup.conf")

# XXX considering everything we should have two classes of backup clients
#     1. server type, always online. these should continue to use the nbd-backup
#     2. desktop type, going to sleep, possibly unreliably wifi network.
#        These should use restic package from distribution.
#        The server needs to start restic server via systemd-socket-proxyd to start/stop it,
#        binding it to mounting of the backup fs.
#        Would be nice if sftp could be made to mount it.
#        https://linuxize.com/post/how-to-set-up-sftp-chroot-jail/
#        https://blog.christophetd.fr/how-to-properly-setup-sftp-with-chrooted-users/
# 1. command to add restic server
#    * download from github by version (github:downloadResticServer)
#    * generate self-signed tls certificate (resticTLSCert)
#    * secured systemd service         (services:addService)
#      https://github.com/restic/rest-server/blob/master/examples/systemd/rest-server.service
# 2. command to add user/passwd (htpasswd)
# 3. command to add restic client

# https://linuxize.com/post/how-to-set-up-sftp-chroot-jail/
# https://blog.christophetd.fr/how-to-properly-setup-sftp-with-chrooted-users/

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
                         password, fmt"$2a$05${saltB64}$")[0]

proc htpassword(filename, user, password: string) =
  var updatedConf: seq[string]
  let prefix = user & ':'
  let userPass = prefix & bcryptPassword(password)
  for line in lines(filename):
    if not line.startsWith(prefix):
      updatedConf.add line
  updatedConf.add userPass
  safeFileUpdate(filename, updatedConf.join("\n") & '\n')

const sshBackupService = """

Host backup-service
HostName 127.0.0.1
User what-backup
IdentityFile /root/.ssh/id_backup-service
"""

func sshUserConfig(user: string): string = fmt"""
Match User {user}
	AuthorizedKeysFile /etc/ssh/authorized_keys/{user}
	AllowStreamLocalForwarding local
	ChrootDirectory /run/backup-nbd-proxy/{user}
"""

func mountUnit(description, unit, what, where: string): string = fmt"""
[Unit]
Description={description}
{unit}
[Mount]
What={what}
Where={where}
"""

func nbdConfig(name: string): string = fmt"""
[generic]
unixsock = {backupMountPoint}/client/{name}/active/nbd.socket

[backup-storage]
exportname = {backupMountPoint}/client/{name}/active/backup.image
maxconnections = 1
splice = true
flush = true
fua = true
trim = true
rotational = true
"""

proc sshChrootUser(user: string) =
  if not fileExists("/usr/sbin/sshd") or not fileExists("/bin/nbd-server"):
    packagesToInstall.add ["openssh-server", "nbd-server"]
    commitQueue()
  createDir "/etc/ssh/authorized_keys"
  let confFile = &"/etc/ssh/sshd_config.d/{user}.conf"
  writeFile confFile, [sshUserConfig(user)]
  if appendMissing("/etc/ssh/sshd_config", "Include " & confFile):
    runCmd "systemctl", "reload", "sshd"

proc createBackupUser(name, home: string; nbd = true): UserInfo =
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

proc backupMount(dev: string): string =
  onDemandMount "Backup store mount", dev, backupMountPoint

proc backupNbdServer(mountUnit, name, group: string) =
  addService "backup-nbd-server@", "Backup NBD server for %i", [],
    "/bin/nbd-server -C /etc/nbd-server/%i.conf", serviceType="forking",
    flags={s_sandbox, s_private_dev, s_call_filter},
    options=["ExecStartPre=/bin/rm -f '/media/backupstore/client/%i/active/nbd.socket'",
             "User=%i", &"Group={group}", &"ReadWritePaths={backupMountPoint}/client/%i/active",
             "RuntimeMaxSec=12h"],
    unitOptions=[&"RequiresMountsFor={backupMountPoint}",
                 &"BindsTo={mountUnit}", "StopWhenUnneeded=true"]
  writeFile fmt"/etc/nbd-server/{name}.conf", [nbdConfig(name)]

proc rotateBackupTimer(mountUnit: string) =
  writeFile "/usr/local/sbin/rotate-backup", [rotateBackup], permissions=0o755
  addService "backup-rotate", "Rotates backup image snapshots", [],
    "/usr/local/sbin/rotate-backup", serviceType="oneshot",
    flags={s_sandbox, s_private_dev, s_call_filter},
    options=[&"ReadWritePaths={backupMountPoint}/client"],
    unitOptions=[&"RequiresMountsFor={backupMountPoint}", &"BindsTo={mountUnit}"]
  addTimer "backup-rotate", "Timer to rotate backup image snapshots",
           "OnCalendar=*-*-01 10:10:10"

proc backupServer*(args: StrMap) =
  let backupUser = args.nonEmptyParam "backup-user"
  let dev = args.getOrDefault "backup-dev"
  let recreateImage = "recreate-image" in args
  let userDir = backupMountPoint / "client" / backupUser
  let activeDir = userDir / "active"
  let defaultImage = activeDir / "backup.image"
  let imageSize = args.getOrDefault("backup-size", "0").parseInt
  let user = createBackupUser(backupUser, activeDir)
  let mountUnit = backupMount dev
  runCmd "systemctl", "daemon-reload"
  runCmd "systemctl", "start", mountUnit
  try:
    createDir activeDir
    setPermissions userDir, 0, user.gid, 0o750
    setPermissions activeDir, user, 0o700
    if not recreateImage and defaultImage.fileExists:
      echo "Image already exists: ", defaultImage
    elif imageSize > 0: # MB
      if recreateImage:
        discard tryRemoveFile(defaultImage)
      sparseFile defaultImage, imageSize * 1024 * 1024, 0o600
    else:
      echo fmt"Invalid backup-size={imageSize} for the image"
      quit 1
    setPermissions defaultImage, user, 0o600
  finally:
    runCmd "systemctl", "stop", mountUnit
  sshChrootUser user.user
  let group = if groupId("nbd") != -1: "nbd"
              else: "%i"
  # nbd-server is a finicky piece of soft. Only configuration where it seems to
  # work somewhat reliably is a forking server without TLS and no inetd style use.
  backupNbdServer mountUnit, user.user, group
  proxy fmt"backup-nbd-proxy@:%i:{group}:0600", "/run/backup-nbd-proxy/%i/socket",
        "", backupMountPoint / "client/%i/active/nbd.socket", "30s",
        "backup-nbd-server@%i.service", "Backup NBD proxy for %i",
        [&"ExecStartPre=/bin/mkdir -pm 755 '/run/backup-nbd-proxy/%i'"]
  enableAndStart fmt"backup-nbd-proxy@{user.user}.socket"
  rotateBackupTimer mountUnit

proc installBackupClient*(args: StrMap) =
  createDir "/media/backup-storage"
  writeFile "/usr/local/sbin/nbd-backup", [backupClient], permissions=0o750
  writeFile "/etc/backup/nbd-backup.conf", [backupConf]
  setPermissions "/etc/backup", 0, 0, 0o700
  addPackageUnless "nbd-client", "/usr/sbin/nbd-client"
  addService "nbd-backup", "Start NBD backup client", [],
             "/usr/local/sbin/nbd-backup sync-no-sleep",
             options=["User=root", "PAMName=crond"],
             unitOptions=["ConditionACPower=true"]
  addTimer "nbd-backup", "Starts NBD backup client periodically",
           ["OnCalendar=*-*-02/4 05:05:05", "WakeSystem=true"]
  let sshConfig = "/root/.ssh/config"
  if not sshConfig.fileContains("Host backup-service"):
    sshConfig.appendToFile sshBackupService, 0o600
    setPermissions "/root/.ssh", 0o700
    runCmd "ssh-keygen", "-t", "ed25519", "-f", "/root/.ssh/id_backup-service", "-N", ""
    for line in lines("/root/.ssh/id_backup-service.pub"):
      echo line
    echo fmt"vi {sshConfig}"

proc resticTLSCert(param: StrMap, restic: UserInfo): string =
  const sslDir = "/etc/ssl/restic"
  const private_key = sslDir & "/private.der"
  const public_key = sslDir & "/public.der"
  if private_key.fileExists and public_key.fileExists:
    echo "Not going to replace existing restic TLS key: ", private_key
  else:
    var hostname = param.getOrDefault "hostname"
    if hostname.len == 0:
      hostname = readFile("/etc/hostname").strip
    var ext = "subjectAltName ="
    let ip = param.getOrDefault "serverip"
    if ip.len != 0:
      ext &= " IP:" & ip
    ext &= " DNS:" & hostname
    echo "Creating ", public_key, " certificate with ", ext
    createDir sslDir
    runCmd "openssl", "req", "-newkey", "rsa:2048", "-nodes", "-x509",
           "-keyout", private_key, "-out", public_key, "-days", "1826",
           "-addext", ext
    setPermissions sslDir, 0, restic.gid, 750
    setPermissions private_key, restic, 400
    setPermissions public_key, 0, restic.gid, 440
  return fmt" --tls --tls-cert {public_key} --tls-key {private_key}"

const resticHome = backupMountPoint / "restic"
const resticPassFile = "/etc/ssl/restic/rpasswd"

proc installResticServer*(args: StrMap) =
  let restic = createBackupUser("restic", resticHome, false)
  let dev = args.getOrDefault "backup-dev"
  downloadResticServer restic
  let tlsOpt = args.resticTLSCert restic
  let mountUnit = backupMount dev
  runCmd "systemctl", "daemon-reload"
  runCmd "systemctl", "start", mountUnit
  try:
    createDir resticHome
    setPermissions resticHome, restic, 700
  finally:
    runCmd "systemctl", "stop", mountUnit
  addService "restic", "Restic server", ["restic.socket"],
    "/opt/restic/rest-server --private-repos --path " & resticHome &
    " --htpasswd-file " & resticPassFile & tlsOpt,
    flags={s_sandbox, s_private_all, s_call_filter},
    options=["ExecStartPre=/bin/rm -f '/media/backupstore/client/%i/active/nbd.socket'",
             "User=restic", "Group=restic", &"ReadWritePaths={resticHome}",
             "UMask=027", "RuntimeMaxSec=12h"],
    unitOptions=[&"RequiresMountsFor={backupMountPoint}",
                 &"BindsTo={mountUnit}", "StopWhenUnneeded=true"]
  # TODO create systemd services
  # TODO create necessary configuration

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
  setPermissions resticPassFile, resticUser, 600

