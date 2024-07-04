#import std/[parseutils, sequtils, strformat, strutils, os, tables]
#import apps, services, utils

import std/[strformat, strutils, os]
import utils

const backupMountPoint = "/media/backupstore"

func sshUserConfig(user, chrootDir: string): string = fmt"""
Match User {user}
\tAutherizedKeysFile /etc/ssh/authorized_keys/{user}
\tAllowStreamLocalForwarding local
\tChrootDirectory {chrootDir}
"""

proc sshChrootUser(user, chrootDir: string) =
  if not fileExists("/usr/sbin/sshd"):
    packagesToInstall.add "openssh-server"
    commitQueue()
  createDir "/etc/ssh/authorized_keys"
  let confFile = &"/etc/ssh/sshd_config.d/{user}.conf"
  writeFile confFile, [sshUserConfig(user, chrootDir)]
  if appendMissing("/etc/ssh/sshd_config", "Include " & confFile):
    runCommand "systemctl", "reload", "sshd"

proc createBackupUser(name, home: string): UserInfo =
  try:
    return name.userInfo # already exists
  except KeyError:
    let nbdGid = groupId("nbd")
    let group = if nbdGid != -1: $nbdGid
                else: ""
    addSystemUser name, group, home
    return name.userInfo

func mountUnit(description, unit, what, where: string) = fmt"""
[Unit]
Description={description}
{unit}
[Mount]
What={what}
Where={where}
"""

proc onDemandMount(description, dev, mount: string): string =
  var what = dev
  if what.startsWith('/'):
    what = outputOfCommand("", "blkid", "-o", "value", "-s", "UUID", dev).strip
  var unit = mountUnit(description, "StopWhenUnneeded=true\n", dev, mount)
  unit &= "Options=noatime,noexec,nodev,noauto\n"
  result = mount.strip({'/'}).replace('/', '-') & ".mount" 
  writeFile "/etc/systemd/system/" & result, [unit], true

proc backupMount(dev: string): string =
  onDemandMount "Backup store mount", dev, backupMountPoint

# TODO server
# * socket-activation vahendaja, et nbd-server käivitada ainult vastavalt vajadusele 
#   (using proxy function from services module)
# * nbd-server systemd teenus
# % on-demand systemd mount backup failisüsteemile, mida nbd-server kasutaks
#   + Determine UUID by device path
#     blkid -o value -s UUID /dev/sda2
# * Backup image loomine
# % kasutaja loomine kes saaks ssh kaudu seda soklit kasutada
# % sshd conf ChrootDirectory ja AllowStreamLocalForwarding local kasutajale
# * script to rotate backup images

# TODO klient
...?

