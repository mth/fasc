import std/[parseutils, sequtils, strformat, strutils, os, tables]
import utils

const clean_old_tmp_service = readResource("tmpfs/clean-old-tmp.service")
const clean_old_tmp_sh = readResource("tmpfs/clean-old-tmp.sh")
const pci_autosuspend_service = readResource("power/pci-autosuspend.service")
const pci_autosuspend = readResource("power/pci-autosuspend")
const sys_psu = "/sys/class/power_supply"

proc isCPUVendor(vendor: string): bool =
  for line in lines("/proc/cpuinfo"):
    if line.startsWith("vendor_id") and line.endsWith(vendor):
      return true

proc isAMDCPU*(): bool = isCPUVendor("AuthenticAMD")
proc isIntelCPU*(): bool = isCPUVendor("GenuineIntel")

proc hasBattery*(): bool =
  sys_psu.listDir.anyIt(readFile(it / "type").strip == "Battery")

proc hasProcess(exePath: string): bool =
  for kind, subdir in walkDir("/proc"):
    try:
      if kind == pcDir and subdir[^1] in {'0'..'9'} and
          expandSymlink(subdir / "exe") == exePath:
        return true
    except:
      discard

proc sysctls(battery: bool) =
  var conf = @[
    "kernel.dmesg_restrict=0",
    "kernel.sched_autogroup_enabled=1",

    # Less swapping should be preferable on most of my configurations with SSD.
    # Swapping can eat flash lifetime and fast SSD can re-read lost cached
    # pages fast. Memory-hungry Java and Javascript processes tend to re-read
    # swapped out pages during tracing GC.
    "vm.swappiness=40",
    "vm.page-cluster=0",

    "net.ipv4.ip_forward=1",
    "net.ipv4.tcp_congestion_control=westwood",
    "net.core.default_qdisc=fq_codel",

    # Enable IPv6 temporary addresses to obstruct web tracking
    "net.ipv6.conf.all.use_tempaddr=2",
    "net.ipv6.conf.default.use_tempaddr=2",
    "net.ipv6.conf.lo.use_tempaddr=-1",
  ]
  if battery:
    conf.add "kernel.nmi_watchdog=0"
    conf.add "vm.dirty_writeback_centisecs=1500"
  writeFile("/etc/sysctl.d/00-local.conf", conf, force=true)

func addGrubZSwap(old: string): string =
  if "zswap." in old:
    return old
  var params = old.strip(chars={'"'}).strip
  if params.len > 0:
    params &= ' '
  return '"' & params &
    "zswap.enabled=1 zswap.compressor=lz4hc zswap.zpool=z3fold zswap.max_pool_percent=33\""

proc encryptedSwap(): bool =
  if fileExists("/etc/crypttab"):
    for crypt in lines("/etc/crypttab"):
      if "swap" in crypt and (" /dev/urandom " in crypt or
                              " /dev/random " in crypt):
        return true

# some laptops need psmouse.synaptics_intertouch=1, however its not universal
proc bootConf() =
  # resume spews errors and delays boot with swap encrypted using random key
  const resume = "/etc/initramfs-tools/conf.d/resume"
  var initramfs = encryptedSwap() and resume.fileExists and
    modifyProperties(resume, [("RESUME", "none")], false)
  var grubUpdate: UpdateMap
  if readLines("/proc/swaps", 2).len > 1:
    grubUpdate["GRUB_CMDLINE_LINUX_DEFAULT"] = addGrubZSwap
    if appendMissing("/etc/initramfs-tools/modules", "lz4hc", "z3fold"):
      echo "Configured zswap"
      initramfs = true
  if modifyProperties("/etc/initramfs-tools/initramfs.conf",
                      [("MODULES", "dep")], false) or initramfs:
    runCmd("update-initramfs", "-u")
  grubUpdate["GRUB_TIMEOUT"] = stringFunc("3")
  if modifyProperties("/etc/default/grub", grubUpdate):
    runCmd("update-grub")

proc memTotal*(): int =
  for line in lines("/proc/meminfo"):
    const total = "MemTotal:"
    if line.startsWith(total) and
       line.parseInt(result, total.len + line.skipWhiteSpace(total.len)) > 0:
      return

proc nextSata(): string =
  result = "sd`"
  for _, disk in walkDir("/sys/class/block"):
    let name = disk.extractFilename
    if name.len == 3 and name.startsWith("sd") and name > result:
      result = name
  result[2].inc

proc fstab() =
  var fstab: seq[string]
  var mounts: Table[string, int]
  var hasSwap = false
  for line in lines("/etc/fstab"):
    fstab.add line
    let fields = line.split.filterIt(it.len > 0)
    if fields.len >= 2 and not fields[0].startsWith('#'):
      if fields[2] == "swap":
        hasSwap = true
      else:
        mounts[fields[1]] = fstab.len
  let originalLen = fstab.len
  if "/tmp" notin mounts:
    let mem = memTotal()
    if mem >= 2048:
      var tmpfs = "tmpfs\t/tmp\ttmpfs\tnosuid"
      if mem >= 8192:
        tmpfs &= ",size=2048m"
      echo "Adding ", tmpfs
      fstab.insert(tmpfs, mounts.getOrDefault("/", fstab.len))
      writeFile("/var/spool/clean-old-tmp.sh", clean_old_tmp_sh)
      writeFileSynced("/etc/systemd/system/clean-old-tmp.service", clean_old_tmp_service)
      enableUnits.add "clean-old-tmp.service"
  if "/y" notin mounts:
    echo "Adding /y vfat user mount"
    createDir "/y"
    fstab.add(&"/dev/{nextSata()}1\t/y\tvfat\tnoauto,user")
  if fstab.len != originalLen:
    safeFileUpdate("/etc/fstab", fstab.join("\n") & "\n")
  # TODO if no swap, add zswap

proc defaultSleepMinutes*(): int =
  if hasBattery(): 7
  else: 15

proc serviceTimeouts() =
  for filename in ["/etc/systemd/system.conf", "/etc/systemd/user.conf"]:
    if modifyProperties(filename, [("DefaultTimeoutStartSec", "15s"),
                                   ("DefaultTimeoutStopSec", "10s")]):
      systemdReload = true

proc systemdSleep*(sleepMinutes: int) =
  # sway loses display output on logind restart
  if modifyProperties("/etc/systemd/logind.conf",
      [("IdleAction", "suspend"), ("IdleActionSec", fmt"{sleepMinutes}min")]) and
     not hasProcess("/usr/bin/sway"):
    runCmd("systemctl", "restart", "systemd-logind.service")
  if modifyProperties("/etc/systemd/sleep.conf", [("AllowSuspendThenHibernate", "no")]):
    systemdReload = true

const hdparmConf = "/etc/hdparm.conf"
const hdparmAPM = "/usr/lib/pm-utils/power.d/95hdparm-apm"

proc hdparm*(args: StrMap) =
  let standbyTime = args.getOrDefault ""
  var sataDevs: seq[(string, string)]
  for kind, disk in walkDir("/dev/disk/by-id"):
    block current:
      if kind == pcLinkToFile:
        let devName = disk.expandSymlink.extractFilename
        if devName.len == 3 and devName.startsWith "sd":
          for i in 0..<sataDevs.len:
            if sataDevs[i][0] == devName:
              if sataDevs[i][1].extractFilename.startsWith "ata-":
                break current
              sataDevs.del i
              break
          sataDevs.add (devName, disk)
  if sataDevs.len != 0:
    if not (hdparmConf.fileExists and hdparmAPM.fileExists):
      aptInstallNow "hdparm"
    var conf: seq[string]
    for line in lines(hdparmConf):
      if line == "# Config examples:":
        break
      conf.add line
    var modified = false
    for (name, dev) in sataDevs:
      if (dev & " {") notin conf:
        var time = 242 # 1 hour
        if standbyTime.len != 0:
          time = standbyTime.parseInt
        elif readFile(fmt"/sys/block/{name}/queue/rotational").strip != "1":
          time = 1  # 5 sec
        elif hasBattery():
          time = 12 # 1 min
        conf.add(dev & " {")
        conf.add("\tspindown_time = " & $time & "\n}\n")
        modified = true
    if modified:
      writeFile(hdparmConf, conf, true)
      runCmd(hdparmAPM, "resume")

proc autosuspendPCI() =
  writeFile "/etc/systemd/system/pci-autosuspend.service", [pci_autosuspend_service]
  safeFileUpdate "/usr/local/sbin/pci-autosuspend", pci_autosuspend, 0o755
  enableAndStart "pci-autosuspend.service"

proc tuneSystem*(args: StrMap) =
  sysctls hasBattery()
  serviceTimeouts()
  bootConf()
  fstab()
  autosuspendPCI()

proc startNTP*(args: StrMap) =
  let ntpServer = args.getOrDefault ""
  if ntpServer == "":
    enableAndStart "systemd-timesyncd.service" # gets server from DHCP
  elif modifyProperties("/etc/systemd/timesyncd.conf", [("NTP", ntpServer)]):
    runCmd("systemctl", "restart", "systemd-timesyncd.service")
    enableUnits.add "systemd-timesyncd.service"

