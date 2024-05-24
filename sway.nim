import std/[strformat, strutils, os]
import utils, apps, gui, system

const foot_ini = readResource("user/foot.ini");

const user_config = [
  (".XCompose", xcompose),
  (".config/waybar/config.jsonc", readResource("user/waybar.jsonc")),
  (".config/mpv/mpv.conf", readResource("user/mpv.conf")),
  (".config/gammastep/config.ini", gammastep_ini)
]

const sway_config = readResourceDir("sway")
const vimfm_desktop = readResource("vimfm.desktop")

# desktop - blank 600, suspend 660; laptop - blank 300, suspend 480
func swayIdle(blankTime: int): string = fmt"""
exec exec swayidle -w \
  timeout {blank_time} 'swaymsg "output * dpms off"' \
  resume 'swaymsg "output * dpms on"' \
  before-sleep 'swaylock -f -c 092a00' \
  after-resume 'pidof -q gammastep || gammastep&' \
  idlehint 20
"""

proc defaultLocale(): string =
  let conf = if isDebian(): "/etc/default/locale"
             else: "/etc/locale.conf"
  for line in lines(conf):
    let strippedLine = line.strip
    if strippedLine.startsWith "LANG=":
      result = strippedLine[5..^1].strip(chars = {'"'})
      break
  if result.len == 0:
    result = "C"

proc runWayland*(userInfo: UserInfo, compositor: string) =
  let user = userInfo.user
  let gid = userInfo.gid
  const maxMemLimit = 0x100000000 # 4GB
  const minMemLimit = 0x040000000 # 1GB
  # Within limits, single process shouldn't exceed 3/4 of physical memory
  var memLimit = memTotal().int64 * 0x300
  if memLimit < minMemLimit or memLimit > maxMemLimit:
    memLimit = maxMemLimit
  var compositor = compositor
  # weird hack for SELinux
  if isFedora():
    compositor = "/usr/bin/sh -c \"exec " & compositor & '"'
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
    fmt"LimitDATA={memLimit}",
    "WorkingDirectory=" & userInfo.home,
    "User=" & user,
    fmt"Group={userInfo.group}",
    "PAMName=login",
    "UtmpIdentifier=tty7",
    "UtmpMode=user",
    "Environment=GDK_BACKEND=wayland" &
    " QT_QPA_PLATFORM=wayland-egl" &
    " XDG_SESSION_TYPE=wayland" &
    " MOZ_WEBRENDER=1" &
    " LANG=" & defaultLocale(),
    "",
    "[Install]",
    "WantedBy=graphical.target",
    ""
  ]
  writeFile("/etc/systemd/system/run-wayland.service", service)
  enableUnits.add "run-wayland.service"
  packagesToInstall.add(["qtwayland5", "xwayland"])
  systemdReload = true
  userInfo.commonGuiSetup

proc waylandUserConfig*(user: UserInfo) =
  for (file, conf) in user_config:
    writeAsUser(user, file, conf)
  var foot = foot_ini
  if not isDebian():
    foot = foot.replace("=Terminus:size=12,", "=")
  writeAsUser(user, ".config/foot/foot.ini", foot)

proc configureSway(user: UserInfo, sleepMinutes: int) =
  user.waylandUserConfig
  for (file, conf) in sway_config:
    var content = firefoxDebianize(conf)
    if file == "config":
      if isFedora():
        content = content.replace("\ninclude bar\n", "\ninclude waybar\n")
        let inc = "include /usr/share/sway/config.d"
        content &= &"{inc}/50-rules-*\n{inc}/*brightness.conf\n{inc}/*volume.conf\n"
      else:
        content &= &"include xf86bindings\n"
    writeAsUser(user, ".config/sway" / file, content)
  writeAsUser(user, ".config/sway/idle", swayIdle((sleepMinutes - 2) * 60))
  user.firefoxConfig

proc swayConf*(args: StrMap) =
  echo "swayConf called."
  configureSway(args.userInfo, defaultSleepMinutes())

proc swayUnit*(args: StrMap) =
  let userInfo = args.userInfo
  let sleepTime = defaultSleepMinutes()
  userInfo.configureSway sleepTime
  userInfo.runWayland "/usr/bin/ssh-agent /usr/bin/sway"
  systemdSleep(sleepTime)
  let ytdlAlias = "/usr/local/bin/youtube-dl"
  if not ytdlAlias.fileExists:
    try:
      createSymlink("/usr/bin/yt-dlp", ytdlAlias)
    except:
      echo("Cannot link /usr/bin/yt-dlp to ", ytdlAlias)
  addFirefox true
  # fonts-dejavu? fonts-liberation? fonts-freefont-ttf?
  # yt-dlp is in unstable, causes problems here
  packagesToInstall.add ["sway", "swayidle", "openssh-client", "foot",
                         "evince", "gammastep", "grimshot", "mpv", #"yt-dlp",
                         "fonts-terminus-otb", "fonts-unifont"]
  if listDir("/sys/class/backlight").len != 0:
    packagesToInstall.add ["brightnessctl", "brightness-udev"]
  const vimfmPath = "/usr/share/applications/vimfm.desktop"
  if not vimfmPath.fileExists:
    aptInstallNow()
    vimfmPath.writeFileSynced vimfm_desktop
    updateMime()
