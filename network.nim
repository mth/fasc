import std/[parseutils, streams, strformat, strutils, terminal, os, osproc]
import cmdqueue

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

proc wlan*(args: Strs) =
  var devices: Strs
  for (kind, path) in walkDir("/sys/class/net"):
    let net = extractFilename(path)
    if net.startsWith("wlp"):
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
  let pass = readPasswordFromStdin fmt"{ssid} pasaword: "
  let process = startProcess("wpa_passphrase", args = [ssid])
  let input = process.inputStream
  input.writeLine pass
  input.flush
  let output = process.outputStream
  var netConf: Strs
  var line: string
  while output.readLine line:
    let notWs = line.skipWhitespace
    if notWs < line.len and line[notWs] == '#':
      netConf.add line
  let exitCode = process.waitForExit
  if exitCode != 0:
    echo fmt"wpa_passphrase exit code {exitCode}, output:"
    echo netConf.join("\n")
    quit 1
