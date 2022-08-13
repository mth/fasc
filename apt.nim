import utils, aptcleaner, system
import std/[strformat, strutils, os, tables]

const default_apt_conf = """
Acquire::Languages "none";
APT::ExtractTemplates::TempDir "/dev/shm";
APT::Get::AutomaticRemove true;
aptitude::AutoClean-After-Update true;
aptitude::Delete-Unused true;
"""

const scripts = [("/usr/local/bin/apt-why", """
#!/bin/sh
apt-cache --installed rdepends "$@" | awk '{if (!($0 in X)) print; X[$0]=1}'
"""), ("/usr/local/sbin/apt-upgrade", readResource("apt/apt-upgrade"))]

const unattended_upgrade_conf = readResource("apt/50unattended-upgrades")

proc preferences(release: string, priority: int) =
  let name = release.rsplit('=', 1)[^1]
  writeFile(fmt"/etc/apt/preferences.d/{name}-priority", [
     "Package: *",
     "Pin: release " & release,
     fmt"Pin-Priority: {priority}"
   ], true)

proc aptConf() =
  writeFile("/etc/apt/apt.conf.d/90disable-recommends",
    ["APT::Install-Recommends false;\n"])
  writeFile("/etc/apt/apt.conf", [default_apt_conf])

proc setupUnattendedUpgrades() =
  const conf_path = "/etc/apt/apt.conf.d/50unattended-upgrades"
  try:
    for line in lines(conf_path):
      if line.strip == "//FASC: preserve":
        echo "Preserving ", conf_path
        return
  except:
    discard
  safeFileUpdate(conf_path, unattended_upgrade_conf)
  enableUnits.add "unattended-upgrades.service"
  runCmd("systemctl", "restart", "unattended-upgrades.service")

proc mandbUpdate() =
  let autoUpdate = "/var/lib/man-db/auto-update"
  if fileExists(autoUpdate):
    echo "Disabling man-db/auto-update..."
    echo outputOfCommand(
          "debconf man-db/auto-update select false\n",
          "debconf-set-selections")
    removeFile(autoUpdate)
    echo("Deleted ", autoUpdate)
  else:
    echo("Not found ", autoUpdate)

proc installFirmware() =
  packagesToInstall.add ["firmware-linux-free", "firmware-misc-nonfree", "firmware-realtek"]
  if dirExists("/sys/module/iwlwifi"):
    packagesToInstall.add "firmware-iwlwifi"
  if isIntelCPU():
    packagesToInstall.add "intel-microcode"
  if isAMDCPU():
    packagesToInstall.add ["firmware-amd-graphics", "amd64-microcode"]

# XXX removing ifupdown should be network modules job
proc defaultPrune(additionalRemove: varargs[string]) =
  var remove = @["avahi-autoipd", "debian-faq", "discover", "doc-debian",
        "ifupdown", "installation-report", "isc-dhcp-client", "isc-dhcp-common",
        "liblockfile-bin", "nano", "netcat-traditional", "reportbug",
        "task-english", "task-laptop", "tasksel", "tasksel-data",
        "telnet", "vim-tiny", "vim-common"]
  remove.add additionalRemove
  packagesToInstall.add ["elvis-tiny", "netcat-openbsd", "psmisc"]
  prunePackages(packagesToInstall, remove)
  packagesToInstall.reset

proc configureAPT*(args: StrMap) =
  aptConf()
  preferences("o=Ubuntu", -1)
  if "unstable" notin args:
    preferences("o=Debian,a=unstable", -1)
  for (path, script) in scripts:
    writeFile(path, script)
    echo("Created ", path)
    setPermissions(path, 0o755)
  mandbUpdate()

proc configureAndPruneAPT*(args: StrMap) =
  configureAPT(args)
  installFirmware()
  packagesToInstall.add ["systemd-cron", "unattended-upgrades"]
  defaultPrune("anacron", "cron")
  try:
    const anacronTimer = "/etc/systemd/system/anacron.timer"
    if anacronTimer.expandSymlink == "/dev/null":
      discard anacronTimer.tryRemoveFile
  except:
    discard
  systemdReload = true
  setupUnattendedUpgrades()

proc installDesktopPackages*(args: StrMap) =
  packagesToInstall.add ["ncal", "bc", "pinfo", "strace", "lsof", "rlwrap", "mc", "curl", "unzip"]

proc installDesktopUIPackages*(args: StrMap) =
  args.installDesktopPackages
  # packagesToInstall.add "xfe"
  packagesToInstall.add ["geeqie", "xdg-utils"]

proc installDevel*(args: StrMap) =
  installDesktopPackages(args)
  packagesToInstall.add ["build-essential", "git"]
