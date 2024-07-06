#import std/[parseutils, sequtils, strformat, strutils, os, tables]
#import apps, services, utils

import std/[strformat, strutils, os, tables]
import services, utils

const backupMountPoint = "/media/backupstore"

func sshUserConfig(user, chrootDir: string): string = fmt"""
Match User {user}
\tAutherizedKeysFile /etc/ssh/authorized_keys/{user}
\tAllowStreamLocalForwarding local
\tChrootDirectory {chrootDir}
"""

proc sshChrootUser(user, chrootDir: string) =
  if not fileExists("/usr/sbin/sshd") or not fileExists("/bin/nbd-server"):
    packagesToInstall.add ["openssh-server", "nbd-server"]
    commitQueue()
  createDir "/etc/ssh/authorized_keys"
  let confFile = &"/etc/ssh/sshd_config.d/{user}.conf"
  writeFile confFile, [sshUserConfig(user, chrootDir)]
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

func mountUnit(description, unit, what, where: string): string = fmt"""
[Unit]
Description={description}
{unit}
[Mount]
What={what}
Where={where}
"""

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

func nbdConfig(name: string): string = fmt"""
[generic]

[{name}]
unixsock = {backupMountPoint}/{name}/active/nbd.socket
exportname = {backupMountPoint}/{name}/active/backup.image
splice = true
flush = true
fua = true
trim = true
rotational = true
"""

proc backupNbdServer(mountUnit, name, group: string) =
  addService "backup-nbd-server@", "Backup NBD server for %I", [],
    "/bin/nbd-server -C /etc/nbd-server/%i.conf", serviceType="forking",
    flags={s_sandbox, s_private_dev, s_call_filter},
    options=["User=%I", &"Group={group}", &"ReadWritePaths={backupMountPoint}/%i/active"],
    unitOptions=[&"RequiresMountsFor={backupMountPoint}",
                 &"BindsTo={mountUnit}", "StopWhenUnneeded=true"]
  writeFile fmt"/etc/nbd-server/{name}.conf", [nbdConfig(name)]

# TODO server
# % socket-activation vahendaja, et nbd-server käivitada ainult vastavalt vajadusele 
#   (using proxy function from services module)
# % nbd-server systemd teenus
# % on-demand systemd mount backup failisüsteemile, mida nbd-server kasutaks
#   + Determine UUID by device path
#     blkid -o value -s UUID /dev/sda2
# % Backup image loomine - sparseFile(name, size)
# % kasutaja loomine kes saaks ssh kaudu seda soklit kasutada
# % sshd conf ChrootDirectory ja AllowStreamLocalForwarding local kasutajale
# * script to rotate backup images

proc backupServer*(args: StrMap) =
  let backupUser = args.nonEmptyParam "backup-user"
  let dev = args.getOrDefault "backup-dev"
  let clientDir = backupMountPoint / "client"
  let userDir = clientDir / backupUser
  let defaultImage = userDir / "active/backup.image"
  let imageSize = if defaultImage.fileExists: 0
                  else: args.nonEmptyParam("backup-size").parseInt
  let chrootDir = userDir / "proxy"
  let socketForSSH = chrootDir / "socket"
  # FIXME? Maybe user home should be userDir/active and leave other stuff to root?
  # There isn't really reason why user should have write access anywhere else.
  # The chrootDir can be well be readonly, ssh needs access only to systemd created socket itself
  # The userDir then contains active, socket and older backup images
  createDir clientDir
  let user = createBackupUser(backupUser, userDir)
  user.createParentDirs defaultImage
  createDir chrootDir # root owner
  if imageSize > 0: # MB
    sparseFile defaultImage, imageSize * 1024 * 1024
  setPermissions defaultImage, user, 0o600
  sshChrootUser user.user, chrootDir
  let mountUnit = backupMount dev
  let group = if groupId("nbd") != -1: "nbd"
              else: "%I"
  backupNbdServer mountUnit, user.user, group
  proxy fmt"backup-nbd-proxy@:%I:{group}:0600", socketForSSH, "",
        userDir / "active/nbd.socket", "30s", "backup-nbd-proxy@%i.service",
        "Backup NBD proxy for %I"
  enableAndStart fmt"backup-nbd-proxy@{user.user}"
  # backup rotation

# TODO klient
#...?

