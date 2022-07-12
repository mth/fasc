import cmdqueue
import std/[strformat, os]

const default_apt_conf = """
Acquire::Languages "none";
APT::Get::AutomaticRemove true;
APT::ExtractTemplates::TempDir "/dev/shm";
aptitude::AutoClean-After-Update true;
aptitude::Delete-Unused true;
""";

proc preferences(release: string, priority: int) =
  writeFile(fmt"/etc/apt/preferences.d/{release}-priority", [
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
    echo outputOfCommand("debconf-set-selections",
          "debconf man-db/auto-update select false\n")
    removeFile(autoUpdate)
    echo("Deleted ", autoUpdate)
  else:
    echo("Not found ", autoUpdate)

proc configureAPT*(args: Strs) =
  aptConf()
  preferences("o=Ubuntu", -1)
  if "unstable" notin args:
    preferences("o=Debian,a=unstable", -1)
  mandbUpdate()
