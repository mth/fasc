import sway, sound, utils, std/[os, posix, strformat, strutils]

const weston_ini = readResource("tv/weston.ini")
const util_files = [
  ("/usr/local/bin/sonata1", readResource("tv/sonata1"), 0o755),
  ("/usr/local/bin/odroid-amixer", readResource("tv/odroid-amixer"), 0o755),
]

proc codename(): string =
  for line in lines("/etc/os-release"):
    if line.startsWith "VERSION_CODENAME=":
      return line[17..^1]
  return "bookworm"

proc vivaldi(user: UserInfo) =
  const vivaldi_list = "/etc/apt/sources.list.d/vivaldi.list"
  if not vivaldi_list.fileExists:
    writeFileSynced vivaldi_list,
      "deb https://repo.vivaldi.com/stable/deb/ stable main\n"
    writeFile "/etc/apt/sources.list.d/raspberry.list",
      [&"deb http://archive.raspberrypi.org/debian/ {codename()} main\n"]
    writeFile "/etc/apt/preferences.d/raspbian",
      ["Package: *", "Pin: origin \"archive.raspberrypi.org\"", "Pin-Priority: -1"]
    setPermissions vivaldi_list, 0o644
    runCmd "apt-get", "update"
    packagesToInstall.add ["chromium-browser", "libwidevinecdm0"]
    # packagesToInstall.add ["vivaldi-stable", "libwidevinecdm0"]
    const symlink = ".local/lib/libwidevinecdm.so"
    user.createParentDirs symlink
    createSymlink("/opt/WidevineCdm", user.home / symlink)
    writeAsUser user, ".config/vivaldi/WidevineCdm/latest-component-updated-widevine-cdm",
                """{"Path":"/opt/WidevineCdm/chromium"}"""

proc westonTV*(args: StrMap) =
  let user = args.userInfo
  user.waylandUserConfig
  writeAsUser user, ".config/weston.ini", weston_ini
  user.runWayland "/usr/bin/weston"
  packagesToInstall.add ["weston", "openssh-client", "foot", "celluloid", "mpv",
                         "sonata", "geeqie", "fonts-terminus-otb", "mpd"]
  user.vivaldi
  user.installMpd # commits queue
  for (path, content, mode) in util_files:
    writeFile path, [content], false, mode.Mode
