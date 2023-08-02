import std/[parseutils, sequtils, strformat, strutils, os, posix, tables]
import apps, services, utils

# adding rules is like following:
# nft add rule inet filter input ip saddr 172.20.0.2 tcp dport 4713 ct state new accept
const nft_prefix = """
#!/usr/sbin/nft -f

flush ruleset

"""

const default_firewall = readResource("nftables.conf")
const ovpnScript = readResource("ovpn")
const resolvedServicePath = "/lib/systemd/system/systemd-resolved.service"

# TODO parameter to set DNSStubListenerExtra= 
#      parameter to set default DNS addresses?
proc useResolvedStub() =
  const resolvConf = "/etc/resolv.conf"
  const stub = "/run/systemd/resolve/stub-resolv.conf"
  if resolvConf.readSymlink == stub:
    return
  if stub.fileExists:
    removeFile resolvConf
    createSymlink stub, resolvConf

proc configureResolved() =
  addPackageUnless "systemd-resolved", resolvedServicePath
  aptInstallNow()
  discard modifyProperties("/etc/systemd/resolved.conf", [("DNSSEC", "allow-downgrade"),
            ("ReadEtcHosts", "yes"), ("LLMNR", "no"), ("MulticastDNS", "no")])
  enableAndStart "systemd-resolved"
  commitQueue()
  useResolvedStub()

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
  network("wlan", "Name=wlp*", "DHCP=yes", "IPv6PrivacyExtensions=true", "DNSSEC=allow-downgrade")
  wpa_supplicant(device)
  addPackageUnless("wpasupplicant", "/usr/sbin/wpa_supplicant")
  addPackageUnless("iw", "/usr/sbin/iw")
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

proc wlan*(args: StrMap) =
  var devices: seq[string]
  for net in findInterfaces():
    if net.isWireless:
      wlanDevice(net)
      configureResolved()
      return
    devices.add net
  let deviceList = devices.join ", "
  echo fmt"No wlp* WLAN device found (existing devices: {deviceList})"

proc wifiNet*(args: StrMap) =
  let ssid = args.nonEmptyParam "ssid"
  stderr.write fmt"{ssid} password: "
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

# nft
# nft add rule inet filter input tcp dport 80 accept
# nft list ruleset
# man nft /Add, change, delete a table.
proc enableDefaultFirewall*(args: StrMap) =
  const confFile = "/etc/nftables.conf"
  for line in lines(confFile):
    if line.endsWith(" accept") or line.endsWith(" drop"):
      echo "Not a default Debian /etc/nftables.conf, not modifying"
      return
  echo "Setting up default firewall"
  when defined(arm) or defined(arm64):
    let rules = "tcp dport 22 ct state new accept\n\t\t"
  else:
    let rules = ""
  writeFile(confFile, nft_prefix & default_firewall.replace("${RULES}", rules))
  discard chmod(confFile, 0o755)
  enableAndStart("nftables.service")

const kill_vpn = """#!/bin/sh

[ "`id -u`" = 0 ] || exec /usr/bin/sudo "$0"
/usr/bin/killall openvpn
"""

proc ovpnClient*(args: StrMap) =
  var user: UserInfo
  if "nosudo" notin args:
    user = userInfo args
  const ovpnPath = "/usr/local/bin/ovpn"
  const killVPNPath = "/usr/local/bin/kill-vpn"
  writeFile(ovpnPath, [ovpnScript])
  writeFile(killVPNPath, kill_vpn)
  if not fileExists("/etc/openvpn/update-systemd-resolved"):
    packagesToInstall.add ["openvpn", "openvpn-systemd-resolved"]
  enableAndStart "systemd-resolved"
  if user.uid == 0:
    setPermissions(ovpnPath, 0o750)
    setPermissions(killVPNPath, 0o750)
    commitQueue()
  else:
    user.sudoNoPasswd "", ovpnPath, killVPNPath
  runCmd("systemctl", "disable", "openvpn")
  runCmd("systemctl", "stop", "openvpn")
  if not fileExists("/root/.vpn/client.ovpn"):
    createDir("/root/.vpn")
    setPermissions("/root/.vpn", 0o700)
    echo "Please copy client.ovpn into /root/.vpn"
  useResolvedStub()

const dns_block_service = readResource("dnsblock.service")

proc setupSafeNet*(args: StrMap) =
  let dnsBlockDir = "/var/cache/dnsblock"
  createDir dnsBlockDir
  writeFile(dnsBlockDir & "/hosts.block", [
    "0.0.0.0 youtube.com", "0.0.0.0 www.youtube.com",
    "0.0.0.0 m.youtube.com", "0.0.0.0 i.ytimg.com",
    "0.0.0.0 www.reddit.com", "0.0.0.0 old.reddit.com"])
  if not resolvedServicePath.fileExists:
    configureResolved()
  let resolveUser = userInfo "systemd-resolve"
  setPermissions dnsBlockDir, resolveUser, 0o750
  overrideService "systemd-resolved", {},
    ("BindReadOnlyPaths=", "/var/cache/dnsblock/hosts:/etc/hosts:norbind")
  safeFileUpdate "/etc/systemd/system/dnsblock.service", dns_block_service
  addTimer "dnsblock", "Update DNS filter weekly", "OnBootSec=1min", "OnUnitActiveSec=1w"
  systemdReload = true
  enableAndStart "dnsblock.timer", "start-resolved.service"
  firefoxParanoid()
  appendRcLocal "/usr/bin/getent hosts example.com&"
  if modifyProperties("/etc/systemd/resolved.conf",
                      [("DNS", "1.1.1.3"), ("ReadEtcHosts", "yes")], false):
    runCmd "systemctl", "start", "dnsblock.service"
    commitQueue()
    runCmd "systemctl", "restart", "systemd-resolved.service"
