import std/[sequtils, strformat, strutils, os, tables]
import utils
  
const sys_psu = "/sys/class/power_supply"

proc hasBattery*(): bool =
  sys_psu.listDir.anyIt(readFile(it / "type").strip == "Battery")

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
    #"net.netfilter.nf_conntrack_helper=1",

    # Enable IPv6 temporary addresses to obstruct web tracking
    "net.ipv6.conf.all.use_tempaddr=2",
    "net.ipv6.conf.default.use_tempaddr=2",
    "net.ipv6.conf.lo.use_tempaddr=-1",
  ]
  if battery:
    conf.add "kernel.nmi_watchdog=0"
    conf.add "vm.dirty_writeback_centisecs=1500"
  writeFile("/etc/sysctl.d/00-local.conf", conf)

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
      if " /dev/random " in crypt and "swap" in crypt:
        return true

proc bootConf() =
  # resume spews errors and delays boot with swap encrypted using random key
  const resume = "/etc/initramfs-tools/conf.d/resume"
  var initramfs = encryptedSwap() and resume.fileExists and
    modifyProperties(resume, {"RESUME": stringFunc("none")}.toTable)
  modifyProperties("/etc/initramfs-tools/initramfs.conf", [("MODULES", "dep")], true)
  var grubUpdate: UpdateMap
  if readLines("/proc/swaps", 2).len > 1:
    echo "Configuring zram..."
    grubUpdate["GRUB_CMDLINE_LINUX_DEFAULT"] = addGrubZSwap
    initramfs = appendMissing("/etc/initramfs-tools/modules", "lz4hc", "z3fold")
  if initramfs:
    runCmd("update-initramfs", "-u")
  grubUpdate["GRUB_TIMEOUT"] = stringFunc("3")
  if modifyProperties("/etc/default/grub", grubUpdate):
    runCmd("update-grub")
  # TODO not zswap specific, but should set MODULES=dep in update-initramfs.conf
  # and this also requires running update-initramfs afterwards

proc defaultSleepMinutes*(): int =
  if hasBattery(): 7
  else: 15

proc systemdSleep*(sleepMinutes: int) =
  modifyProperties("/etc/systemd/logind.conf",
    [("IdleAction", "suspend"), ("IdleActionSec", fmt"{sleepMinutes}min")])
  modifyProperties("/etc/systemd/sleep.conf",
    [("AllowSuspendThenHibernate", "no")])

proc tuneSystem*(args: StrMap) =
  sysctls(hasBattery())
  bootConf()
