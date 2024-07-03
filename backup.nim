#import std/[parseutils, sequtils, strformat, strutils, os, tables]
#import apps, services, utils

import std/[strformat, os]
import utils

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


# TODO server
# * socket-activation vahendaja, et nbd-server käivitada ainult vastavalt vajadusele 
#   (using proxy function from services module)
# * nbd-server systemd teenus
# * on-demand systemd mount backup failisüsteemile, mida nbd-server kasutaks
#   + Determine UUID by device path
#     blkid -o value -s UUID /dev/sda2
# * kasutaja loomine kes saaks ssh kaudu seda soklit kasutada
# * sshd conf ChrootDirectory ja AllowStreamLocalForwarding local kasutajale
# * script to rotate backup images

# TODO klient
...?

