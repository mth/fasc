import std/[parseutils, sequtils, strformat, strutils, os]
import cmdqueue

proc network(unit, match: string, options: varargs[string]) =
  var net = @[
    "[Match]",
    match,
    "",
    "[Link]",
    "RequiredForOnline=no",
    "",
    "[Network]"
  ]
  writeFile(fmt"/etc/systemd/network/{unit}.network", net & @options & "", true)

const wpa_supplicant_conf = "/etc/wpa_supplicant/wpa_supplicant.conf"

proc ensureSupplicantConf() =
  writeFile(wpa_supplicant_conf, [
    "ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev",
    "update_config=1",
    "dtim_period=4",
    "beacon_int=200",
    "ignore_old_scan_res=1",
    #"bgscan=\"simple:60:-70:900\"",
    "p2p_disabled=1"
  ])

proc wpa_supplicant(device: string) =
  ensureSupplicantConf()
  let conf_link = fmt"/etc/wpa_supplicant/wpa_supplicant-{device}.conf"
  discard tryRemoveFile(conf_link)
  createSymlink("wpa_supplicant.conf", conf_link)

func supplicantService(iface: string): string =
  fmt"wpa_supplicant@{iface}.service"

proc wlanDevice(device: string) =
  echo fmt"Configuring WLAN device {device} for DHCP"
  network("wlan", "Name=wlp*", "DHCP=yes", "IPv6PrivacyExtensions=true")
  wpa_supplicant(device)
  packagesToInstall.add "wpasupplicant"
  enableAndStart("systemd-networkd.service", device.supplicantService)

iterator findInterfaces(): string =
  for kind, path in walkDir("/sys/class/net"):
    yield extractFilename(path)

func isWireless(iface: string): bool =
  iface.startsWith("wlp")

proc isInterfaceUp(iface: string): bool =
  readFile(fmt"/sys/class/net/{iface}/operstate") == "up"

proc stopWireless(): seq[string] =
  for iface in findInterfaces():
    if iface.isWireless and iface.isInterfaceUp:
      result.add iface
  if result.len > 0:
    let services = result.map supplicantService
    echo("Stopping wireless services: ", services.join(", "))
    runCmd("systemctl", "stop" & services)

proc wlan*(args: Strs) =
  var devices: Strs
  for net in findInterfaces():
    if net.isWireless:
      wlanDevice(net)
      return
    devices.add net
  let deviceList = devices.join ", "
  echo fmt"No wlp* WLAN device found (existing devices: {deviceList})"

proc wifiNet*(args: Strs) =
  if args.len != 1:
    echo "Expected fasc wifinet <ssid>"
    quit 1
  let ssid = args[0]
  stderr.write fmt"{ssid} pasaword: "
  let pass = stdin.readLine
  var netConf = "\n"
  for line in outputOfCommand(pass & '\n', "wpa_passphrase", ssid):
    let notWs = line.skipWhitespace
    if notWs < line.len and line[notWs] != '#':
      netConf.add line
      netConf.add "\n"
  ensureSupplicantConf()
  # kill wpa_supplicant instances before configuration modification
  let stoppedInterfaces = stopWireless()
  let file = open(wpa_supplicant_conf, fmAppend)
  file.write netConf
  file.close
  echo fmt"Added {ssid} network into {wpa_supplicant_conf}"
  startUnits.add(stoppedInterfaces.map supplicantService)
