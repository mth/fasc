import std/[os, strutils, tables]
import system
import utils

# This part is unlikely to need customization, and probably should into /etc/bash.bashrc
const etc_bashrc = readResource("bash.bashrc")
const dot_bashrc = readResource("user/bashrc")
const debian_bashrc_header = "# ~/.bashrc: executed by bash(1) for non-login shells."
const upload_cam_script = readResource("user/upload-cam")

proc configureUserBash(user: UserInfo) =
  let bashrc = user.home / ".bashrc"
  try:
    if readLines(bashrc, 1) != [debian_bashrc_header]:
      echo(bashrc, " is not a debian default, not modifying")
      return
  except:
    discard # non-existent .bashrc isn't a problem
  echo("Replacing ", bashrc)
  writeFile(bashrc, dot_bashrc)

proc configureBash*(args: StrMap) =
  echo "Replacing /etc/bash.bashrc"
  writeFile("/etc/bash.bashrc", etc_bashrc)
  configureUserBash(args.userInfo)

proc uploadCam*(args: StrMap) =
  let rsync_args = args.getOrDefault("rsync-args", "'--groupmap=*:www-data'")
  args.userInfo.writeAsUser("bin/upload-cam",
    upload_cam_script.replace("{RSYNC_TARGET}", args.nonEmptyParam("rsync-to"))
                     .replace("{RSYNC_ARGS}", rsync_args), 0o755, true)
  fstab(tmpfs = false)
