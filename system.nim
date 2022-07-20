import std/[sequtils, strutils, os]
import utils
  
const sys_psu = "/sys/class/power_supply"

proc hasBattery(): bool =
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

proc systemdSleep(sleepTime: string) =
  var sleepTime = "30min"
  if hasBattery():
    sleepTime = "10min"
  modifyProperties("/etc/systemd/logind.conf",
    [("IdleAction", "suspend"), ("IdleActionSec", sleepTime)])
  modifyProperties("/etc/systemd/sleep.conf",
    [("AllowSuspendThenHibernate", "no")])

proc tuneSystem*(args: Strs) =
  let battery = hasBattery()
  sysctls(battery)
  systemdSleep(if battery: "10min"
               else: "30min")
