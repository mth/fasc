# This file is part of FASC, the FAst System Configurator.
#
# Copyright (C) 2022-2024 Madis Janson
#
# FASC is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# FASC is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with FASC. If not, see <https://www.gnu.org/licenses/>.

import std/[parseutils, sequtils, strformat, strutils, os, tables]
import services, utils

const clean_old_tmp_service = readResource("tmpfs/clean-old-tmp.service")
const clean_old_tmp_sh = readResource("tmpfs/clean-old-tmp.sh")
const pci_autosuspend = readResource("power/pci-autosuspend")
const sys_psu = "/sys/class/power_supply"
const batteryType = "Battery"

proc isCPUVendor(vendor: string): bool =
  for line in lines("/proc/cpuinfo"):
    if line.startsWith("vendor_id") and line.endsWith(vendor):
      return true

proc isAMDCPU*(): bool = isCPUVendor("AuthenticAMD")
proc isIntelCPU*(): bool = isCPUVendor("GenuineIntel")

when defined(arm64):
  const n2plusFixup = readResource("arm/boot-dtb-odroid-n2plus")

  proc compatible*(what: string): bool =
    const dtsc = "/sys/firmware/devicetree/base/compatible"
    return dtsc.fileExists and what in dtsc.readFile

  proc addWatchDog() =
    addPackageUnless "watchdog", "/usr/sbin/watchdog"
    aptInstallNow()
    discard modifyProperties("/etc/watchdog.conf", [
      ("watchdog-device", "/dev/watchdog0"),
      ("watchdog-timeout", "30")])

  func cpuFreq(path, val: string): string =
    "echo " & val & "> /sys/devices/system/cpu/cpufreq/" & path

  proc dtsFixup(): bool =
    const dtsModel = "/sys/firmware/devicetree/base/model"
    var machineName = if dtsModel.fileExists:
                        dtsModel.readFile.strip
                      else: ""
    addPackageUnless "device-tree-compiler", "/usr/bin/dtc"
    addPackageUnless "zram-tools", "/etc/default/zramswap"
    if "ODROID-N2Plus" in machineName:
      echo "Detected Odroid-N2+"
      appendRcLocal cpuFreq("policy0/scaling_governor", "performance"),
        cpuFreq("policy2/scaling_governor", "ondemand"),
        cpuFreq("policy2/scaling_min_freq", "1000000")
      discard appendMissing("/etc/modules", ["meson-ir", "ir_rc5_decoder", "meson_gxbb_wdt"])
      addPackageUnless "patch", "/usr/bin/patch"
      addWatchDog()
      const dtbFile = "/odroid-n2-plus.dtb"
      const postInst = "/etc/kernel/postinst.d/boot-dtb-odroid-n2plus"
      writeFile postInst, [n2plusFixup], false, 0o755
      #writeFile postInst, [n2plusFixup], true, 0o755
      writeFile "/grub/custom.cfg", ["echo 'Loading device tree ...'",
                                         "devicetree " & dtbFile]
      if not fileExists("/boot" & dtbFile):
        aptInstallNow()
        runCmd postInst
        return true
else:
  proc compatible*(what: string): bool = false
  proc dtsFixup(): bool = false

proc findPSU(psuType: string): string =
  for psu in sys_psu.listDir:
    if readFile(psu / "type").strip == psuType:
      return psu

proc batteryCount(): int = findPSU(batteryType).len
proc hasBattery*(): bool = batteryCount() != 0

proc hasProcess(exePath: string): bool =
  for kind, subdir in walkDir("/proc"):
    if kind == pcDir and subdir[^1] in {'0'..'9'} and
        readSymlink(subdir / "exe") == exePath:
      return true

proc udevReload(subsystem: string) =
  runCmd "udevadm", "control", "--reload-rules"
  runCmd "udevadm", "trigger", fmt"--attr-match=subsystem={subsystem}"

proc propset*(args: StrMap) =
  let file = args.nonEmptyParam("config")
  var properties = args
  properties.del "config"
  discard modifyProperties(file, properties.pairs.toSeq, false)

proc sysctls(args: StrMap, battery: bool) =
  # expect that buffer-bloat restriction on wired connection is routers problem
  let qdisc = args.getOrDefault("default-qdisc",
                                if battery: "fq_codel"
                                else: "sfq")
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
    "net.ipv4.tcp_sack=0", # avoid SACK panic attacks
    "net.core.default_qdisc=" & qdisc,

    # Enable IPv6 temporary addresses to obstruct web tracking
    "net.ipv6.conf.all.use_tempaddr=2",
    "net.ipv6.conf.default.use_tempaddr=2",
    "net.ipv6.conf.lo.use_tempaddr=-1",

    # "user.max_user_namespaces=0", # security, but those are needed for nspawn
  ]
  if battery:
    conf.add "kernel.nmi_watchdog=0"
    conf.add "vm.dirty_writeback_centisecs=1500"
  writeFile("/etc/sysctl.d/00-local.conf", conf, force=true)
  runCmd("sysctl", "-p", "/etc/sysctl.d/00-local.conf")

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

proc hasNormalSwap(): bool =
  for line in lines("/proc/swaps"):
    if line.startsWith("/dev/") and not line.startsWith("/dev/zram"):
      return true

# some laptops need psmouse.synaptics_intertouch=1, however its not universal
proc bootConf() =
  # resume spews errors and delays boot with swap encrypted using random key
  const resume = "/etc/initramfs-tools/conf.d/resume"
  var initramfs = encryptedSwap() and resume.fileExists and
    modifyProperties(resume, [("RESUME", "none")], false)
  var grubUpdate: UpdateMap
  if hasNormalSwap():
    grubUpdate["GRUB_CMDLINE_LINUX_DEFAULT"] = addGrubZSwap
    if appendMissing("/etc/initramfs-tools/modules", "lz4hc", "z3fold"):
      echo "Configured zswap"
      initramfs = true
  if isAMDCPU() and appendMissing("/etc/initramfs-tools/modules", "amd_pstate"):
    initramfs = true
  if modifyProperties("/etc/initramfs-tools/initramfs.conf",
                      [("MODULES", "dep")], false) or initramfs:
    runCmd("update-initramfs", "-u")
  grubUpdate["GRUB_TIMEOUT"] = stringFunc("3")
  let updated = modifyProperties("/etc/default/grub", grubUpdate)
  if dtsFixup() or updated:
    runCmd("update-grub")

proc memTotal*(): int =
  for line in lines("/proc/meminfo"):
    const total = "MemTotal:"
    if line.startsWith(total) and
       line.parseInt(result, total.len + line.skipWhiteSpace(total.len)) > 0:
      return

proc readFStab(mounts: var Table[string, int]; hasSwap: var bool): seq[string] =
  for line in lines("/etc/fstab"):
    result.add line
    let fields = line.split.filterIt(it.len > 0)
    if fields.len >= 2 and not fields[0].startsWith('#'):
      if fields[2] == "swap":
        hasSwap = true
      else:
        mounts[fields[1]] = result.len

proc fstab*(tmpfs = true) =
  var mounts: Table[string, int]
  var hasSwap = false
  var fstab = readFStab(mounts, hasSwap)
  let originalLen = fstab.len
  if tmpfs and not isFedora() and "/tmp" notin mounts:
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
    fstab.add(&"/dev/disk/usbdrive1\t/y\tvfat\tnoauto,user")
    writeFileSynced("/etc/udev/rules.d/85-usb-storage-alias.rules",
      """KERNEL=="sd?1" SUBSYSTEM=="block" SUBSYSTEMS=="usb" SYMLINK+="disk/usbdrive1"""")
    udevReload "block"
  if fstab.len != originalLen:
    safeFileUpdate "/etc/fstab", fstab.join("\n") & "\n"
  # TODO if no swap, add zswap

proc autoMount*(device, mountPoint, filesystem, flags: string, idleTime = "5min", secure = true) =
  var def = device & '\t' & mountPoint & '\t' & filesystem & '\t' & flags
  if flags != "":
    def &= ','
  if secure:
    def &= "noexec,nodev,sec=sys,"
  def &= "noauto,x-systemd.automount,x-systemd.mount-timeout=20,x-systemd.idle-timeout="
  def &= idleTime
  var fstab = ""
  var hasMount = false
  for line in lines("/etc/fstab"):
    let fields = line.split.filterIt(it.len > 0)
    if fields.len <= 1 or fields[1] != mountPoint:
      fstab &= line
    elif line != def:
      hasMount = true
      fstab &= def
    else:
      return
    fstab &= '\n'
  if hasMount:
    safeFileUpdate "/etc/fstab", fstab
  else:
    def &= '\n'
    writeFileSynced "/etc/fstab", def, fmAppend

proc defaultSleepMinutes*(): int =
  if hasBattery(): 7
  else: 15

proc createModifyProperties(filename: string, section: string,
                            update: varargs[(string, string)]): bool =
  if not filename.fileExists:
    writeFile filename, [section]
  modifyProperties filename, update

proc serviceTimeouts() =
  for filename in ["/etc/systemd/system.conf", "/etc/systemd/user.conf"]:
    if createModifyProperties(filename, "[Manager]",
        ("DefaultTimeoutStartSec", "15s"), ("DefaultTimeoutStopSec", "10s")):
      systemdReload = true

proc systemdSleep*(sleepMinutes: int) =
  # sway loses display output on logind restart
  if createModifyProperties("/etc/systemd/logind.conf", "[Login]",
      ("IdleAction", "suspend"), ("IdleActionSec", fmt"{sleepMinutes}min")) and
     not hasProcess("/usr/bin/sway"):
    runCmd("systemctl", "restart", "systemd-logind.service")
  if createModifyProperties("/etc/systemd/sleep.conf", "[Sleep]",
                            ("AllowSuspendThenHibernate", "no")):
    systemdReload = true

const hdparmConf = "/etc/hdparm.conf"
const hdparmAPM = "/usr/lib/pm-utils/power.d/95hdparm-apm"

proc hdparmForDevs*(standbyTime: int, sataDevs: seq[(string, string)]) =
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
        if standbyTime > 0:
          time = standbyTime
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

proc hdparm*(args: StrMap) =
  let standbyTimeStr = args.getOrDefault ""
  let standbyTime = if standByTimeStr.len != 0: standbyTimeStr.parseInt
                    else: 0
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
  hdparmForDevs standbyTime, sataDevs

# https://wiki.archlinux.org/title/laptop#suspend_on_low_battery_level
proc batteryMonitor(useUdev: bool) =
  const udevLowBattery = "SUBSYSTEM==\"power_supply\", ATTR{status}==\"Discharging\", " &
                         "ATTR{capacity}==\"[0-3]\", RUN+=\"/usr/bin/systemctl suspend\""
  if useUdev or isFedora():
    writeFile "/etc/udev/rules.d/99-lowbat.rules", [udevLowBattery]
    udevReload "power_supply"
  else:
    packagesToInstall.add "sleepd"
    aptInstallNow()
    if modifyProperties("/etc/default/sleepd",
          [("PARAMS", "\"-b 2 -u 0 -c 30 -I -s '/usr/bin/systemctl suspend'\"")],
          onlyEmpty=false):
      runCmd "systemctl", "restart", "sleepd.service"

proc limitBattery(args: StrMap) =
  let limit = args.getOrDefault("maxCharge", "85")
  addService "battery-limit", "Limit battery max charge", [],
    "/bin/sh -c 'for bat in /sys/class/power_supply/BAT*/charge_{stop_threshold,control_end_threshold}; do echo " &
    limit & " > $bat; done'",
    "multi-user.target", serviceType="oneshot"

proc inMemoryJournal() =
  var conf = @[("Storage", "volatile")]
  let logDev = outputOfCommand("", "df", "--output=source", "/var/log")
  if logDev.len >= 2 and logDev[1].startsWith("/dev/mmcblk"):
    conf &= [("RuntimeMaxUse", "32M"), ("ForwardToSyslog", "no")]
  else:
    conf &= ("RuntimeMaxUse", "16M")
  if createModifyProperties("/etc/systemd/journald.conf", "[Journal]", conf):
    runCmd "systemctl", "restart", "systemd-journald.service"
    runCmd "rm", "-rf", "/var/log/journal"

# TODO comment out pam_motd.so from /etc/pam.d/sshd

proc tuneSystem*(args: StrMap) =
  let batteries = batteryCount()
  args.sysctls(batteries != 0)
  serviceTimeouts()
  if isDebian():
    bootConf()
  fstab()
  inMemoryJournal()
  if listDir("/sys/bus/pci/devices").len > 0:
    safeFileUpdate "/usr/local/sbin/pci-autosuspend", pci_autosuspend, 0o755
    addService "pci-autosuspend", "Enables PCI devices autosuspend", [],
               "/usr/local/sbin/pci-autosuspend", "multi-user.target",
               serviceType="oneshot"
  if batteries != 0:
    batteryMonitor(batteries == 1)
    args.limitBattery
  if isFedora():
    runCmd "systemctl", "disable", "--now", "systemd-userdbd.socket",
           "systemd-userdbd.service", "systemd-homed.service"
    runCmd "systemctl", "mask", "systemd-homed.service", "systemd-homed-activate.service"
  addTimer "fstrim", "Discard unused filesystem blocks once a hour", "OnBootSec=5min", "OnUnitInactiveSec=1h"
  systemdReload = true

proc startNTP*(args: StrMap) =
  let ntpServer = args.getOrDefault ""
  addPackageUnless("systemd-timesyncd",
                   "/lib/systemd/system/systemd-timesyncd.service")
  if ntpServer == "":
    enableAndStart "systemd-timesyncd.service" # gets server from DHCP
  elif createModifyProperties("/etc/systemd/timesyncd.conf", "[Time]", ("NTP", ntpServer)):
    runCmd("systemctl", "restart", "systemd-timesyncd.service")
    enableUnits.add "systemd-timesyncd.service"

proc nfs*(args: StrMap) =
  var mounts: Table[string, int]
  var hasSwap = false
  var fstab = readFStab(mounts, hasSwap)
  var originalLen = fstab.len
  var hasParam = false
  var automounts: seq[string]
  for (arg, share) in args.pairs:
    let argParts = arg.split ':'
    if argParts.len >= 2 and argParts[0] == "mount":
      let mount = argParts[^1]
      if not mount.startsWith("/") or mount == "/":
        echo("Invalid mount point: ", mount)
        quit 1
      hasParam = true
      var options = "noauto,noexec,nodev,sec=sys,_netdev,"
      if "ro" in argParts:
        options = "ro," & options
      if "user" in argParts:
        options &= "user"
      else:
        options &= "x-systemd.automount,x-systemd.mount-timeout=20,x-systemd.idle-timeout=5min"
        automounts.add(mount[1..^1].replace('/', '-') & ".automount")
      let line = &"{share}\t{mount}\tnfs4\t{options}"
      let lineNo = mounts.getOrDefault(mount) - 1
      if lineNo < 0:
        fstab.add line
      elif fstab[lineNo] != line:
        fstab[lineNo] = line
        originalLen.dec
      createDir mount
  if not hasParam:
    echo "fasc nfs mount:[ro:][user:]/mount/point=hostname:/export/path"
  if fstab.len != originalLen:
    safeFileUpdate("/etc/fstab", fstab.join("\n") & "\n")
    addPackageUnless("nfs-common", "/sbin/mount.nfs")
    if automounts.len != 0:
      systemdReload = true
      startUnits &= automounts
