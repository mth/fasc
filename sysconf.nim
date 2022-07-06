import std/[parsecfg, posix, sequtils, strformat, strutils, tables, os, osproc]

var packagesToInstall: seq[string]
var enableUnits: seq[string]
var startUnits: seq[string]
var systemdReload: bool

proc enableAndStart(units: varargs[string]) =
  for unit in units:
    enableUnits.add unit
    startUnits.add unit

proc writeFile(filename: string, content: openarray[string]) =
  writeFile(filename, content.join("\n"))

proc network(unit, match: string, options: varargs[string]) =
  var net = @[
    "[Match]",
    match,
    "",
    "[Link]",
    "RequiredForOnline=no",

    "[Network]"
  ]
  writeFile(fmt"/etc/systemd/network/{unit}.network", net & @options & @[""])

proc wpa_supplicant(device: string) =
  let conf = [
    "ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev",
    "update_config=1",
    "dtim_period=4",
    "beacon_int=200",
    "ignore_old_scan_res=1",
    #"bgscan=\"simple:60:-70:900\"",
    "p2p_disabled=1"
  ]
  let defaultConfName = "/etc/wpa_supplicant/wpa_supplicant.conf"
  if not defaultConfName.fileExists:
    writeFile(defaultConfName, conf)
  let conf_link = fmt"/etc/wpa_supplicant/wpa_supplicant-{device}.conf"
  discard tryRemoveFile(conf_link)
  createSymlink("wpa_supplicant.conf", conf_link)

proc wlanDevice(device: string) =
  network("wlan", "Name=wlp*", "DHCP=yes", "IPv6PrivacyExtensions=true")
  wpa_supplicant(device)
  packagesToInstall.add "wpa_supplicant"
  enableAndStart("systemd-networkd.service", fmt"wpa_supplicant@{device}.service")

proc wlan() =
  for (kind, path) in walkDir("/sys/class/net"):
    let net = extractFilename(path)
    if net.startsWith("wlp") and not net.endsWith("-p2p"):
      wlanDevice(net)
    return

proc runCmd(command: string, args: varargs[string]) =
  let process = startProcess(command, "", args, nil, {poParentStreams, poUsePath})
  let exitCode = process.waitForExit
  if exitCode != 0:
    echo fmt"Executing {command} with {args} failed with exit code {exitCode}"
    quit 1

proc runWayland(compositor, user: string) =
  let pw = user.getpwnam
  if pw == nil:
    echo fmt"Unknown user {user}"
    quit 1
  let groupId = pw.pw_gid
  let home = $pw.pw_dir
  var service = [
    "[Unit]",
    "Description=Runs wayland desktop",
    "Wants=usb-gadget.target",
    "After=systemd-user-sessions.service plymouth-quit-wait.service usb-gadget.target",
    "",
    "[Service]",
    fmt"ExecStartPre=/usr/bin/install -m 700 -o {user} -g {user} -d /tmp/.{user}-cache",
    "ExecStart=/usr/bin/ssh-agent " & compositor,
    "KillMode=control-group",
    "Restart=no",
    "StandardInput=tty-fail",
    "StandardOutput=tty",
    "StandardError=journal",
    "TTYPath=/dev/tty7",
    "TTReset=yes",
    "TTYVHangup=yes",
    "TTYVTDisallocate=yes",
    "WorkingDirectory=" & home,
    "User=" & user,
    fmt"Group={groupId}",
    "PAMName=login",
    "UtmpIdentifier=tty7",
    "UtmpMode=user",
    "Environment=GDK_BACKEND=wayland QT_QPA_PLATFORM=wayland-egl XDG_SESSION_TYPE=wayland MOZ_WEBRENDER=1 LANG=et_EE.utf8",
    "",
    "[Install]",
    "WantedBy=graphical.target",
    ""
  ]
  writeFile("/etc/systemd/system/run-wayland.service", service)
  runCmd("systemctl", "enable", "run-wayland.service")
  systemdReload = true
  packagesToInstall.add(["openssh-client", "qtwayland5"])

proc sway() =
  runWayland("sway", "mzz")
  packagesToInstall.add("sway")

let tasks = {
  "wlan": ("Configure WLAN client with DHCP", wlan),
  "sway": ("Configure sway desktop startup", sway)
}.toTable

if not (paramStr(1) in tasks):
  echo "Unknown task: ", paramStr(1)
else:
  tasks[paramStr(1)][1]()
if packagesToInstall.len > 0:
  runCmd("apt-get", @["install", "-y", "--no-install-recommends"] &
         packagesToInstall.deduplicate)
if systemdReload:
  runCmd("systemctl", "daemon-reload")
if enableUnits.len > 0:
  runCmd("systemctl", "enable" & enableUnits.deduplicate)
if startUnits.len > 0:
  runCmd("systemctl", "start" & startUnits.deduplicate)
