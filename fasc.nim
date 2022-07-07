import std/[strformat, strutils, tables, os]
import cmdqueue
import sway

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
  echo fmt"Configuring WLAN device {device} for DHCP"
  network("wlan", "Name=wlp*", "DHCP=yes", "IPv6PrivacyExtensions=true")
  wpa_supplicant(device)
  packagesToInstall.add "wpa_supplicant"
  enableAndStart("systemd-networkd.service", fmt"wpa_supplicant@{device}.service")

proc wlan() =
  var devices: seq[string]
  for (kind, path) in walkDir("/sys/class/net"):
    let net = extractFilename(path)
    if net.startsWith("wlp"):
      wlanDevice(net)
      return
    devices.add net
  let deviceList = devices.join ", "
  echo fmt"No wlp* WLAN device found (existing devices: {deviceList})"

let tasks = {
  "wlan": ("Configure WLAN client with DHCP", wlan),
  "sway": ("Configure sway desktop startup", swayUnit)
}.toTable

if paramCount() == 0:
  echo "FAst System Configurator."
  echo "fasc (wlan|sway)"
  quit()

if not (paramStr(1) in tasks):
  echo "Unknown task: ", paramStr(1)
else:
  tasks[paramStr(1)][1]()
runQueuedCommands()
