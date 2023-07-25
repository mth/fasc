import sway, sound, utils, std/posix

const weston_ini = readResource("tv/weston.ini")
const util_files = [
  ("/usr/local/bin/sonata1", readResource("tv/sonata1"), 0o755),
  ("/usr/local/bin/odroid-amixer", readResource("tv/odroid-amixer"), 0o755),
]

proc westonTV*(args: StrMap) =
  let user = args.userInfo
  user.waylandUserConfig
  writeAsUser(user, ".config/weston.ini", weston_ini)
  user.runWayland "/usr/bin/weston"
  packagesToInstall.add ["weston", "openssh-client", "foot", "celluloid", "mpv",
                         "sonata", "geeqie", "fonts-terminus-otb", "mpd"]
  user.installMpd # commits queue
  for (path, content, mode) in util_files:
    writeFile path, [content], false, mode.Mode
