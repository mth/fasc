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

proc codename(): string =
  for line in lines("/etc/os-release"):
    if line.startsWith "VERSION_CODENAME=":
      return line[17..^1]
  return "bookworm"

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

# wget -O - http://apt.xbian.org/xbian.gpg.key | gpg --dearmor > /usr/share/keyrings/xbian-archive-keyring.gpg

proc addRepo(name, arch, suites, keyUrl, repoUrl: string,
             preferences: varargs[(string, int)]) =
  let keyring = fmt"/usr/share/keyrings/{name}-archive-keyring.gpg"
  if not keyring.fileExists:
    let gpgKey = outputOfCommand("", "wget", "-qO", "-", keyUrl)
    discard outputOfCommand(gpgKey.join("\n"), "gpg", "--dearmor", "-o", keyring)
  let source = fmt"/etc/apt/sources.list.d/{name}.list"
  if not source.fileExists:
    writeFileSynced source, &"deb [signed-by={keyring} arch={arch}] {repoUrl} {suites}\n"
    aptUpdate = true
    if preferences.len > 0:
      let urlParts = repoUrl.split '/'
      var prefs: seq[string]
      for (package, priority) in preferences:
        prefs &= [&"Package: {package}",
                  &"Pin: origin \"{urlParts[2]}\"",
                  &"Pin-Priority: {priority}"]
      writeFile fmt"/etc/apt/preferences.d/{name}", prefs

#proc addXbian() =
#  when defined(arm64):
#    runCmd "dpkg", "--add-architecture", "armhf"
#    addRepo "xbian", "armhf", &"stable armv7l-{codename()}",
#            "http://apt.xbian.org/xbian.gpg.key", "http://apt.xbian.org/",
#            ("*", -1), ("libc6", 600)
proc addRaspbian() =
  when defined(arm64):
    runCmd "dpkg", "--add-architecture", "armhf"
    addRepo "raspbian", "armhf", "bullseye main",
            "https://archive.raspberrypi.org/debian/raspberrypi.gpg.key",
            "https://archive.raspberrypi.org/debian/", ("*", -1), ("libwidevinecdm0", 500)

# TODO use chromium:armhf chromium-sandbox:armhf

proc westonTV*(args: StrMap) =
  let user = args.userInfo
  user.waylandUserConfig
  writeAsUser user, ".config/weston.ini", weston_ini
  const widevine_link = ".local/lib/libwidevinecdm.so"
  user.createParentDirs widevine_link
  if not symlinkExists(user.home / widevine_link):
    createSymlink("/opt/WidevineCdm", user.home / widevine_link)
  user.runWayland "/usr/bin/weston"
  addRaspbian()
  packagesToInstall.add ["weston", "openssh-client", "foot", "celluloid", "mpv", "mpd", "mpc",
                         "sonata", "python3-pkg-resources", "geeqie", "fonts-terminus-otb"]
  #user.vivaldi
  user.installMpd # commits queue
  for (path, content, mode) in util_files:
    writeFile path, [content], false, mode.Mode
