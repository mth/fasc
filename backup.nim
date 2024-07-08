import std/[strformat, strutils, os, tables]
import services, utils

const backupMountPoint = "/media/backupstore"
const rotateBackup = readResource("rotate-backup.sh")

func sshUserConfig(user: string): string = fmt"""
Match User {user}
	AuthorizedKeysFile /etc/ssh/authorized_keys/{user}
	AllowStreamLocalForwarding local
	ChrootDirectory /run/nbd-backup/{user}
"""

func mountUnit(description, unit, what, where: string): string = fmt"""
[Unit]
Description={description}
{unit}
[Mount]
What={what}
Where={where}
"""

const nbdConfig = """
[generic]

[backup]
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

proc backupNbdServer(mountUnit, name, group, directory: string) =
  addService name & "-nbd-server@", "Backup NBD server for " & name, [],
    "/bin/nbd-server 0 {directory}/backup.image -C /etc/nbd-server/backup.conf",
    flags={s_sandbox, s_private_dev, s_call_filter},
    options=["StandardInput=socket", "User=" & name, "Group=" & group,
             "CollectMode=inactive-or-failed", "ReadWritePaths=" & directory],
    unitOptions=["RequiresMountsFor=" & backupMountPoint,
                 "BindsTo=" & mountUnit, "StopWhenUnneeded=true"]
  writeFile fmt"/etc/nbd-server/backup.conf", [nbdConfig]
  socketUnit name & "-nbd-server.socket", "Backup NBD socket for " & name,
             &"/run/nbd-backup/{name}/socket", "SocketUser=" & name,
             "SocketGroup=" & group, "SocketMode=0600",
             &"ExecStartPre=/bin/mkdir -pm 755 '/run/nbd-backup/{name}'"

proc rotateBackupTimer(mountUnit: string) =
  writeFile "/usr/local/sbin/rotate-backup", [rotateBackup], permissions=0o755
  addService "backup-rotate", "Rotates backup image snapshots", [],
    "/usr/local/sbin/rotate-backup", serviceType="oneshot",
    flags={s_sandbox, s_private_dev, s_call_filter},
    options=[&"ReadWritePaths={backupMountPoint}/client"],
    unitOptions=["RequiresMountsFor=" & backupMountPoint, "BindsTo=" & mountUnit]
  addTimer "backup-rotate", "Timer to rotate backup image snapshots",
           "OnCalendar=*-01,04,07,10-01 10:10:10"

proc backupServer*(args: StrMap) =
  let backupUser = args.nonEmptyParam "backup-user"
  let dev = args.getOrDefault "backup-dev"
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
    if defaultImage.fileExists:
      echo "Image already exists: ", defaultImage
    elif imageSize > 0: # MB
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
  backupNbdServer mountUnit, user.user, group, activeDir
  rotateBackupTimer mountUnit

# TODO klient
#...?

