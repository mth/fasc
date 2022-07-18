import cmdqueue, aptcleaner
import std/[strformat, strutils, os]

const default_apt_conf = """
Acquire::Languages "none";
APT::ExtractTemplates::TempDir "/dev/shm";
APT::Get::AutomaticRemove true;
aptitude::AutoClean-After-Update true;
aptitude::Delete-Unused true;
""";

proc preferences(release: string, priority: int) =
  let name = release.rsplit('=', 1)[^1]
  writeFile(fmt"/etc/apt/preferences.d/{name}-priority", [
     "Package: *",
     "Pin: release " & release,
     fmt"Pin-Priority: {priority}"
   ], true)

proc aptConf() =
  writeFile("/etc/apt/apt.conf.d/90disable-recommends",
    ["APT::Install-Recommends false;"])
  writeFile("/etc/apt/apt.conf", [default_apt_conf])

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

# XXX removing ifupdown should be network modules job
proc defaultPrune() =
  let remove = ["avahi-autoipd", "debian-faq", "discover", "doc-debian",
        "ifupdown", "installation-report", "isc-dhcp-client", "isc-dhcp-common",
        "liblockfile-bin", "nano", "netcat-traditional", "reportbug",
        "task-english", "task-laptop", "tasksel", "tasksel-data",
        "telnet", "vim-tiny", "vim-common"]
  prunePackages(["elvis-tiny", "netcat-openbsd"], remove)

proc configureAPT*(args: Strs) =
  aptConf()
  preferences("o=Ubuntu", -1)
  if "unstable" notin args:
    preferences("o=Debian,a=unstable", -1)
  mandbUpdate()

# XXX something should install rlwrap
proc installDevel*(args: Strs) =
  packagesToInstall.add ["build-essential", "pinfo", "strace"]
