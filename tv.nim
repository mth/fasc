import sway, sound, utils, std/[os, posix, strformat, strutils]

const weston_ini = readResource("tv/weston.ini")
const util_files = [
  ("/usr/local/bin/cputemp", readResource("tv/cputemp"), 0o755),
  ("/usr/local/bin/sonata1", readResource("tv/sonata1"), 0o755),
  ("/usr/local/bin/odroid-amixer", readResource("tv/odroid-amixer"), 0o755),
  ("/usr/local/sbin/update-widevine", readResource("tv/update-widevine"), 0o700),
  ("/usr/local/share/pixmaps/celluloid-32x32.png", readResource("tv/celluloid-32x32.png"), 0o644),
  ("/usr/local/share/pixmaps/geeqie-32x32.png", readResource("tv/geeqie-32x32.png"), 0o644),
  ("/usr/local/share/pixmaps/sonata-32x32.png", readResource("tv/sonata-32x32.png"), 0o644),
]

#proc codename(): string =
#  for line in lines("/etc/os-release"):
#    if line.startsWith "VERSION_CODENAME=":
#      return line[17..^1]
#  return "bookworm"
#
#proc vivaldi(user: UserInfo) =
#  const vivaldi_list = "/etc/apt/sources.list.d/vivaldi.list"
#  if not vivaldi_list.fileExists:
    #writeFileSynced vivaldi_list,
    #  "deb https://repo.vivaldi.com/stable/deb/ stable main\n"
    #writeFile "/etc/apt/sources.list.d/raspberry.list",
    #  [&"deb http://archive.raspberrypi.org/debian/ {codename()} main\n"]
    #writeFile "/etc/apt/preferences.d/raspbian",
    #  ["Package: *", "Pin: origin \"archive.raspberrypi.org\"", "Pin-Priority: -1"]
    #setPermissions vivaldi_list, 0o644
    #runCmd "apt-get", "update"
    #packagesToInstall.add ["chromium-browser", "libwidevinecdm0"]
    # packagesToInstall.add ["vivaldi-stable", "libwidevinecdm0"]
    #writeAsUser user, ".config/vivaldi/WidevineCdm/latest-component-updated-widevine-cdm",
    #            """{"Path":"/opt/WidevineCdm/chromium"}"""

proc westonTV*(args: StrMap) =
  let user = args.userInfo
  user.waylandUserConfig
  writeAsUser user, ".config/weston.ini", weston_ini
  const widevine_link = ".local/lib/libwidevinecdm.so"
  user.createParentDirs widevine_link
  createSymlink("/opt/WidevineCdm", user.home / widevine_link)
  user.runWayland "/usr/bin/weston"
  packagesToInstall.add ["weston", "openssh-client", "foot", "celluloid", "mpv",
                         "sonata", "geeqie", "fonts-terminus-otb", "mpd"]
  #user.vivaldi
  user.installMpd # commits queue
  for (path, content, mode) in util_files:
    writeFile path, [content], false, mode.Mode
