import strutils, utils, apps, system

const font_auto_hinting = readResource("fonts-autohinting.xml")
const xkb_uml = readResource("uml.xkb")
const xsession = readResource("icewm/xsession")
const xdefaults = readResource("icewm/Xdefaults")
const gammastep_ini* = readResource("user/gammastep.ini")

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

proc installIceWM*(args: StrMap) =
  let sleepMinutes = defaultSleepMinutes()
  let user = args.userInfo
  writeAsUser(user, ".xsession",
              xsession.replace("SLEEP_SEC", $((sleepMinutes - 2) * 60)), 0o755)
  writeAsUser(user, ".Xdefaults", xdefaults)
  writeAsUser(user, ".config/redshift.conf", gammastep_ini.replace("wayland", "xrandr"))
  packagesToInstall.add ["xserver-xorg", "xserver-xorg-input-evdev",
    "xserver-xorg-video-intel", "x11-utils", "x11-xserver-utils", "mesa-utils",
    "compton", "redshift", "lightdm", "icewm", "mirage", "thunar", "xterm", "moc", "mc",
    "evince", "fonts-terminus-otb", "fonts-unifont"]
  user.commonGuiSetup
  addFirefoxESR()
  systemdSleep sleepMinutes
