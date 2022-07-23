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

# TODO detect whether we have swap at all ?
proc zswap() =
  var grubUpdate: UpdateMap
  grubUpdate["GRUB_TIMEOUT"] = stringFunc("3", false)
  grubUpdate["GRUB_CMDLINE_LINUX_DEFAULT"] = addGrubZSwap
  modifyProperties("/etc/default/grub", grubUpdate)
  # TODO add lz4hc and z3fold into /etc/initramfs-tools/modules
  # TODO run update-initramfs -u if modules was updated

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
  zswap()
