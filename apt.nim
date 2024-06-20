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
  if not isDebian():
    echo "APT is for Debian"
    quit 1
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
proc defaultPrune(extraProtect: openarray[string], additionalRemove: varargs[string]) =
  var remove = @["avahi-autoipd", "debian-faq", "discover", "doc-debian",
        "installation-report", "isc-dhcp-client", "isc-dhcp-common",
        "liblockfile-bin", "nano", "netcat-traditional", "reportbug",
        "task-english", "task-laptop", "tasksel", "tasksel-data",
        "telnet", "vim-tiny", "vim-common"]
  remove.add additionalRemove
  when not (defined(arm) or defined(arm64)):
    packagesToInstall.add "ifupdown"
  packagesToInstall.add ["elvis-tiny", "netcat-openbsd", "psmisc"]
  prunePackages(packagesToInstall, remove, extraProtect)
  packagesToInstall.reset

proc configureAPT*(args: StrMap) =
  aptConf()
  preferences("o=Ubuntu", -1)
  if "unstable" notin args:
    preferences("o=Debian,a=unstable", -1)
  if "testing" notin args:
    preferences("o=Debian,a=testing", -1)
  for (path, script) in scripts:
    writeFile(path, script)
    echo("Created ", path)
    setPermissions(path, 0o755)
  mandbUpdate()

proc configureAndPruneAPT(args: StrMap) =
  configureAPT(args)
  installFirmware()
  packagesToInstall.add ["systemd-cron", "unattended-upgrades"]
  let extraProtect = args.getOrDefault("retain").split(',')
  defaultPrune(extraProtect, "anacron", "cron")
  const anacronTimer = "/etc/systemd/system/anacron.timer"
  if anacronTimer.readSymlink == "/dev/null":
    discard anacronTimer.tryRemoveFile
  systemdReload = true
  setupUnattendedUpgrades()

proc configureAndPruneDNF(args: StrMap) =
  let installed = outputOfCommand("", "rpm", "-qa", "--queryformat", "%{NAME}\\n")
  discard modifyProperties("/etc/dnf/dnf.conf", [
            ("install_weak_deps", "False"),
            ("max_parallel_downloads", "8"),
            ("fastestmirror", "True"),
            ("deltarpm", "True"),
            ("deltarpm_percentage", "30")])
  var preserve = @["ctags", "openvpn", "tigervnc-server-minimal", "usermode",
                   "nss-tools", "gdb", "nftables"]
  for i in countdown(preserve.len - 1, 0):
    if preserve[i] notin installed:
      preserve.delete i
  runCmd("dnf", @["mark", "install"] & preserve)
  runCmd("dnf", "remove", "NetworkManager", "PackageKit", "PackageKit-glib",
         "avahi", "chrony", "firewalld", "udisks2", "gssproxy", "upower",
         "teamd", "python3-firewall", "sssd-client", "tracker", "bash-color-prompt",
         "virtualbox-guest-additions", "open-vm-tools", "open-vm-tools-desktop",
         "brcmfmac-firmware", "cirrus-audio-firmware", "libertas-firmware",
         "nvidia-gpu-firmware", "nxpwireless-firmware", "tiwilink-firmware")
  echo "You could also remove atheros-firmware and mt7xxx-firmware"
  if isIntelCPU():
    runCmd "dnf", "remove", "amd-ucode-firmware", "amd-gpu-firmware"

proc configureAndPrunePackages*(args: StrMap) =
  if isDebian():
    args.configureAndPruneAPT
  elif isFedora():
    args.configureAndPruneDNF

proc configureRPMFusion*(args: StrMap) =
  let ver = outputOfCommand("", "rpm", "-E", "%fedora")[0]
  runCmd "dnf", "install",
    fmt"https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-{ver}.noarch.rpm",
    fmt"https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-{ver}.noarch.rpm"
  runCmd "dnf", "config-manager", "--enable", "fedora-cisco-openh264"
  runCmd "dnf", "swap", "ffmpeg-free", "ffmpeg", "--allowerasing"
  if isIntelCPU():
    packagesToInstall.add "intel-media-driver"
  elif isAMDCPU():
    runCmd "dnf", "swap", "mesa-va-drivers", "mesa-va-drivers-freeworld"

proc installDesktopPackages*(args: StrMap) =
  if isDebian():
    packagesToInstall.add ["mc", "ncal"]
  packagesToInstall.add ["bc", "pinfo", "strace", "lsof", "rlwrap", "curl", "unzip"]
  if isFedora():
    packagesToInstall.add "fuse-sshfs"

proc installDesktopUIPackages*(args: StrMap) =
  args.installDesktopPackages
  if isFedora():
    packagesToInstall.add "flatpak"
  packagesToInstall.add ["geeqie", "xdg-utils", "xmahjongg"]

proc installDevel*(args: StrMap) =
  installDesktopPackages(args)
  packagesToInstall.add ["build-essential", "git", "nim"]

proc beginnerDevel*(args: StrMap) =
  installDevel args
  packagesToInstall.add ["scratch", "thonny", "ocaml", "utop", "libgraphics-ocaml-dev"]
