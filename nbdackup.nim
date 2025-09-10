import std/[strformat, strutils, os, tables]
import backup, services, utils

const backupClient  = readResource("backup/nbd-backup")
const backupConf    = readResource("backup/nbd-backup.conf")
const rotateBackup  = readResource("backup/rotate-backup.sh")

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

proc backupNbdServer(mountUnit, name, group: string) =
  addService "backup-nbd-server@", "Backup NBD server for %i", [],
    "/bin/nbd-server -C /etc/nbd-server/%i.conf", serviceType="forking",
    flags={s_sandbox, s_private_dev, s_call_filter},
    options=["ExecStartPre=/bin/rm -f '/media/backupstore/client/%i/active/nbd.socket'", maxRuntime,
             "User=%i", &"Group={group}", &"ReadWritePaths={backupMountPoint}/client/%i/active"],
    unitOptions=[&"RequiresMountsFor={backupMountPoint}", &"BindsTo={mountUnit}",
                 &"After={mountUnit}", "StopWhenUnneeded=true"]
  writeFile fmt"/etc/nbd-server/{name}.conf", [nbdConfig(name)]

proc rotateBackupTimer(mountUnit: string) =
  writeFile "/usr/local/sbin/rotate-backup", [rotateBackup], permissions=0o755
  addService "backup-rotate", "Rotates backup image snapshots", [],
    "/usr/local/sbin/rotate-backup", serviceType="oneshot",
    flags={s_sandbox, s_private_dev, s_call_filter},
    options=[&"ReadWritePaths={backupMountPoint}/client"],
    unitOptions=[&"RequiresMountsFor={backupMountPoint}", &"BindsTo={mountUnit}", &"After={mountUnit}"]
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
  backupClientService "nbd-backup", "Start NBD backup client",
                      "/usr/local/sbin/nbd-backup sync-no-sleep"
  let sshConfig = "/root/.ssh/config"
  if not sshConfig.fileContains("Host backup-service"):
    sshConfig.appendToFile sshBackupService, 0o600
    setPermissions "/root/.ssh", 0o700
    runCmd "ssh-keygen", "-t", "ed25519", "-f", "/root/.ssh/id_backup-service", "-N", ""
    for line in lines("/root/.ssh/id_backup-service.pub"):
      echo line
    echo fmt"vi {sshConfig}"
