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

import std/[strformat, strutils, os, tables]
import services, utils

const backupMountPoint = "/media/backupstore"
const rotateBackup = readResource("backup/rotate-backup.sh")
const backupClient = readResource("backup/nbd-backup")
const backupConf   = readResource("backup/nbd-backup.conf")

# for some reason, systemd-inhibit doesn't always prevent sleep
const delaySleep = """
#!/bin/sh

[ "$1" = "pre" ] || exit
while systemctl is-active -q nbd-backup.service
do sleep 1
done
"""

const waitUnhibited = """
#!/bin/sh

while ! systemd-inhibit --what=idle:sleep:handle-lid-switch:handle-suspend-key:handle-hibernate-key --who=nbd-backup /bin/true
do sleep 1
done
"""

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

proc createBackupUser(name, home: string): UserInfo =
  try:
    return name.userInfo # already exists
  except KeyError:
    let nbdGid = groupId("nbd")
    let group = if nbdGid != -1: $nbdGid
                else: ""
    addSystemUser name, group, home
    return name.userInfo

proc onDemandMount(description, dev, mount: string): string =
  result = mount.strip(chars={'/'}).replace('/', '-') & ".mount" 
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
             "User=%i", &"Group={group}", &"ReadWritePaths={backupMountPoint}/client/%i/active"],
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
  const waitWakeup = "/etc/backup/wait-uninhibited"
  createDir "/media/backup-storage"
  writeFile "/usr/local/sbin/nbd-backup", [backupClient], permissions=0o750
  writeFile "/etc/backup/nbd-backup.conf", [backupConf]
  writeFile waitWakeup, [waitUnhibited], permissions=0o755
  safeFileUpdate "/usr/lib/systemd/system-sleep/backup-no-sleep", delaySleep, permissions=0o755
  setPermissions "/etc/backup", 0, 0, 0o700
  addPackageUnless "nbd-client", "/usr/sbin/nbd-client"
  addService "nbd-backup", "Start NBD backup client", [],
             "systemd-inhibit --what=idle:sleep:handle-lid-switch:handle-suspend-key:handle-hibernate-key --who=nbd-backup \"--why=Active backup\" /usr/local/sbin/nbd-backup sync",
             options=["ExecStartPre=" & waitWakeup, "User=root", "PAMName=crond"],
             unitOptions=["ConditionACPower=true"]
  #           unitOptions=["ConditionACPower=true", "BindsTo=user@0.service", "After=user@0.service"]
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
