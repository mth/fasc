import std/[strformat, os]
import utils, firefox, system

const user_config = [
  (".XCompose", readResource("user/XCompose")),
  (".config/foot/foot.ini", readResource("user/foot.ini")),
  (".config/mpv/mpv.conf", readResource("user/mpv.conf")),
  (".config/gammastep/config.ini", readResource("user/gammastep.ini"))
]

const sway_config = readResourceDir("sway")
const xkb_uml = readResource("uml.xkb")
const font_auto_hinting = readResource("fonts-autohinting.xml")

# desktop - blank 600, suspend 660; laptop - blank 300, suspend 480
func swayIdle(blankTime: int): string = fmt"""
exec exec swayidle -w \
  timeout {blank_time} 'swaymsg "output * dpms off"' \
  resume 'swaymsg "output * dpms on"' \
  before-sleep 'swaylock -f -c 092a00' \
  after-resume 'pidof -q gammastep || gammastep&' \
  idlehint 20
"""

proc runWayland(userInfo: UserInfo, compositor: string) =
  let user = userInfo.user
  let gid = userInfo.gid
  const maxMemLimit = 0x100000000 # 4GB
  const minMemLimit = 0x040000000 # 1GB
  # Within limits, single process shouldn't exceed 3/4 of physical memory
  var memLimit = memTotal().int64 * 0x300
  if memLimit < minMemLimit or memLimit > maxMemLimit:
    memLimit = maxMemLimit
  var service = [
    "[Unit]",
    "Description=Runs wayland desktop",
    "Wants=sysinit.target usb-gadget.target",
    "After=systemd-user-sessions.service plymouth-quit-wait.service sysinit.target usb-gadget.target",
    "",
    "[Service]",
    fmt"ExecStartPre=/usr/bin/install -m 700 -o {user} -g {gid} -d /tmp/.{user}-cache",
    fmt"ExecStartPre=/usr/bin/install -m 700 -o {user} -g {gid} -d /tmp/downloads",
    "ExecStart=" & compositor,
    "KillMode=control-group",
    "Restart=no",
    "StandardInput=tty-fail",
    "StandardOutput=tty",
    "StandardError=journal",
    "TTYPath=/dev/tty7",
    "TTYReset=yes",
    "TTYVHangup=yes",
    "TTYVTDisallocate=yes",
    fmt"LimitDATA={memLimit}", # limit process data sizes to 2GB
    "WorkingDirectory=" & userInfo.home,
    "User=" & user,
    fmt"Group={userInfo.gid}",
    "PAMName=login",
    "UtmpIdentifier=tty7",
    "UtmpMode=user",
    "Environment=GDK_BACKEND=wayland" &
    " QT_QPA_PLATFORM=wayland-egl" &
    " XDG_SESSION_TYPE=wayland" &
    " MOZ_WEBRENDER=1" &
    " LANG=et_EE.utf8", # should be read from /etc/default/locale
    "",
    "[Install]",
    "WantedBy=graphical.target",
    ""
  ]
  writeFile("/etc/systemd/system/run-wayland.service", service)
  writeFile("/etc/fonts/conf.d/10-autohinting.conf", [font_auto_hinting])
  enableUnits.add "run-wayland.service"
  packagesToInstall.add(["qtwayland5", "xwayland"])
  if isIntelCPU():
    packagesToInstall.add "i965-va-driver"
  else:
    packagesToInstall.add "mesa-va-drivers"
  systemdReload = true
  runCmd("usermod", "-G",
    "adm,audio,cdrom,input,kvm,video,render,systemd-journal", user)

proc configureSway(user: UserInfo, sleepMinutes: int) =
  for (file, conf) in user_config:
    writeAsUser(user, file, conf)
  for (file, conf) in sway_config:
    writeAsUser(user, ".config/sway" / file, conf)
  writeAsUser(user, ".config/sway/idle", swayIdle((sleepMinutes - 2) * 60))
  user.firefoxConfig

proc swayConf*(args: StrMap) =
  echo "swayConf called."
  configureSway(args.userInfo, defaultSleepMinutes())

proc swayUnit*(args: StrMap) =
  let userInfo = args.userInfo
  let sleepTime = defaultSleepMinutes()
  writeFile("/usr/share/X11/xkb/symbols/uml", @[xkb_uml])
  userInfo.configureSway sleepTime
  userInfo.runWayland "/usr/bin/ssh-agent /usr/bin/sway"
  systemdSleep(sleepTime)
  let ytdlAlias = "/usr/local/bin/youtube-dl"
  if not ytdlAlias.fileExists:
    try:
      createSymlink("/usr/bin/yt-dlp", ytdlAlias)
    except:
      echo("Cannot link /usr/bin/yt-dlp to ", ytdlAlias)
  addFirefoxESR()
  # fonts-dejavu? fonts-liberation? fonts-freefont-ttf?
  packagesToInstall.add ["sway", "swayidle", "openssh-client", "foot",
                         "evince", "gammastep", "grim", "mpv", "yt-dlp",
                         "fonts-terminus-otb", "fonts-unifont"]
  if listDir("/sys/class/backlight").len != 0:
    packagesToInstall.add ["brightnessctl", "brightness-udev"]
