import strutils, utils, apps, apt, system, std/os

const font_auto_hinting = readResource("fonts-autohinting.xml")
const xkb_uml = readResource("uml.xkb")
const icewm_startup = readResource("icewm/startup")
const icewm_toolbar = readResource("icewm/toolbar")
const xdefaults = readResource("icewm/Xdefaults")
const xcompose* = readResource("user/XCompose")
const gammastep_ini* = readResource("user/gammastep.ini")
const tearfree = readResource("icewm/20-intel.conf")

proc disableTracker*(args: StrMap) =
  runCmd("systemctl", "--user", "unmask", "tracker-extract-3.service",
         "tracker-miner-fs-3.service", "tracker-miner-rss-3.service",
         "tracker-writeback-3.service", "tracker-xdg-portal-3.service",
         "tracker-miner-fs-control-3.service")

proc commonGuiSetup*(user: UserInfo) =
  writeFile("/etc/fonts/conf.d/10-autohinting.conf", [font_auto_hinting])
  writeFile("/usr/share/X11/xkb/symbols/uml", @[xkb_uml])
  runCmd("usermod", "-G",
    "adm,audio,cdrom,dialout,input,netdev,kvm,video,render,systemd-journal", user.user)
  if isIntelCPU():
    packagesToInstall.add "intel-media-va-driver" # newer driver, maybe better?
    # packagesToInstall.add "i965-va-driver"
  else:
    packagesToInstall.add "mesa-va-drivers"
  packagesToInstall.add ["desktop-base", "policykit-1"]

proc installX11(user: UserInfo) =
  writeAsUser(user, ".Xdefaults", xdefaults)
  writeAsUser(user, ".XCompose", xcompose)
  writeAsUser(user, ".config/redshift.conf", gammastep_ini.replace("wayland", "xrandr"))
  packagesToInstall.add ["xserver-xorg", "xserver-xorg-input-evdev",
    "xserver-xorg-video-intel", "lightdm", "x11-utils", "x11-xserver-utils",
    "mesa-utils", "redshift", "mc", "fonts-unifont"]
  user.commonGuiSetup
  addFirefoxESR false

proc installLXQT*(args: StrMap) =
  installDesktopPackages args
  packagesToInstall.add ["lxqt", "libio-stringy-perl", "media-player-info",
    "fonts-hack", "qt5-image-formats-plugins", "qpdfview", "oxygen-icon-theme",
    "gvfs-backends", "gvfs-fuse", "xscreensaver", "p7zip-full", "moc", "qimgv"]
  args.userInfo.installX11

proc installIceWM*(args: StrMap) =
  let sleepMinutes = defaultSleepMinutes()
  let user = args.userInfo
  writeAsUser(user, ".icewm/startup",
              icewm_startup.replace("SLEEP_SEC", $((sleepMinutes - 2) * 60))
                           .replace("USERNAME", user.user), 0o755)
  writeAsUser(user, ".icewm/toolbar", icewm_toolbar)
  writeAsUser(user, ".icewm/theme", "Theme=\"Infadel2/default.theme\"\n")
  installDesktopPackages args
  packagesToInstall.add ["icewm", "mirage", "thunar", "xterm", "moc", "evince", "geany",
                         "light-locker"]
  user.installX11
  systemdSleep sleepMinutes
  let pref = user.home / ".icewm/preferences"
  if not pref.fileExists:
    commitQueue()
    copyFile "/usr/share/icewm/preferences", pref
    discard modifyProperties(pref, [("DesktopBackgroundImage",
                "/usr/share/desktop-base/active-theme/grub/grub-16x9.png"),
              ("ModSuperIsCtrlAlt", "1")], false)
    setPermissions(pref, user, 0o644)
  writeFile "/etc/X11/xorg.conf.d/20-intel.conf", [tearfree]
