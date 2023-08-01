import std/[os, strutils, tables]
import utils

type ServiceFlags* = enum
  s_no_new_priv,
  s_sandbox,
  s_private_dev,
  s_allow_netlink,
  s_call_filter,
  s_overwrite

func descriptionOfName(name, description: string): string =
  if description != "":
    return description
  return name.replace('-', ' ').capitalizeAscii

proc addTimer*(name, description: string, options: varargs[string]) =
  var timer = @["[Unit]", "Description=" & description, "", "[Timer]"]
  timer.add options
  timer.add ["", "[Install]", "WantedBy=timers.target", ""]
  let unitName = name & ".timer"
  writeFile("/etc/systemd/system" / unitName, timer)
  enableAndStart(unitName)

proc properties(flags: set[ServiceFlags]): seq[(string, string)] =
  if s_sandbox in flags or s_no_new_priv in flags:
    result &= [
      ("CapabilityBoundingSet=", "~CAP_SYS_ADMIN"),
      ("MemoryDenyWriteExecute=", "true"),
      ("NoNewPrivileges=", "yes"),
      ("SecureBits=", "nonroot-locked"),
    ]
  if s_sandbox in flags:
    result &= [
      ("ProtectSystem=", "strict"),
      ("PrivateTmp=", "true"),
      ("ProtectControlGroups=", "yes"),
      ("ProtectKernelLogs=", "true"),
      ("ProtectKernelModules=", "yes"),
      ("ProtectKernelTunables=", "yes"),
      ("ProtectProc=", "invisible"),
      ("RestrictNamespaces=", "yes"),
      ("RestrictRealtime=", "yes"),
      ("RestrictAddressFamilies=", "AF_INET AF_INET6 AF_UNIX"),
    ]
    if s_allow_netlink in flags:
      result[^1][1] &= " AF_NETLINK"
    if s_private_dev in flags:
      result &= ("PrivateDevices=", "true")
  if s_call_filter in flags:
    result &= [
      ("SystemCallArchitectures=", "native"),
      ("SystemCallFilter=", "@system-service"),
    ]
    when defined(arm):
      result[^1][1] &= " arm_fadvise64_64"

proc addService*(name, description: string, depends: openarray[string],
                 exec: string, install="", flags: set[ServiceFlags] = {},
                 options: openarray[string] = [], serviceType="") =
  var depString = ""
  for dep in depends:
    if dep != "":
      if depString != "":
        depString &= ' '
      depString &= dep
      if '.' notin dep:
        depString &= ".service"
  var service = @["[Unit]", "Description=" & description]
  if depString != "":
    service &= "Requires=" & depString
    service &= "After=" & depString
  service.add ["", "[Service]"]
  if serviceType != "":
    service &= "Type=" & serviceType
  service &= "ExecStart=" & exec
  for (key, value) in flags.properties:
    service &= key
    service &= value
  service.add options
  if install != "":
    service.add ["", "[Install]", "WantedBy=" & install]
  service.add ""
  let serviceName = name & ".service"
  writeFile("/etc/systemd/system" / serviceName, service, s_overwrite in flags)
  if install != "":
    enableAndStart serviceName

proc overrideService*(name: string, flags: set[ServiceFlags],
                      properties: varargs[(string, string)]) =
  let dir = "/etc/systemd/system/" & name & ".service.d"
  let override = dir / "override.conf"
  var content = @[("", "[Service]")] & @properties
  content &= flags.properties
  createDir dir
  if appendMissing(override, content, true):
    systemdReload = true

proc secureService*(args: StrMap) =
  let service = args.nonEmptyParam "service"
  var flags = {s_sandbox}
  var props = @[("ReadWritePaths=", args.getOrDefault("rw", "/run/" & service))]
  if "syscall" in args:
    flags.incl s_call_filter
  if "private_dev" in args:
    flags.incl s_private_dev
  if "allow_netlink" in args:
    flags.incl s_allow_netlink
  if "01" in args:
    props &= ("CPUAffinity=", "0 1")
  overrideService service, flags, props

proc proxy*(proxy, listen, bindTo, connectTo, exitIdleTime, targetService: string,
            description = "") =
  let socketParam = proxy.split ':'
  let socketName = socketParam[0] & ".socket"
  let descriptionStr = descriptionOfName(socketParam[0], description)
  var socket = @[
    "[Unit]",
    "Description=" & descriptionStr
  ]
  if ':' in listen:
    socket.add "Requires=network-online.target"
    socket.add "After=network-online.target"
  socket.add ["",
    "[Socket]",
    "ListenStream=" & listen,
  ]
  if bindTo != "":
    socket &= "BindToDevice=" & bindTo
  if socketParam.len > 1:
    socket &= "SocketUser=" & socketParam[1]
  if socketParam.len > 2:
    socket &= "SocketGroup=" & socketParam[2]
  if socketParam.len > 3:
    socket &= "SocketMode=" & socketParam[3]

  socket &= ["", "[Install]", "WantedBy=sockets.target", ""]
  writeFile("/etc/systemd/system" / socketName, socket, force=true)
  var options = @["PrivateTmp=yes"]
  if listen.startsWith("/") and connectTo.startsWith("/"):
    options.add "PrivateNetwork=yes"
  addService(socketParam[0], descriptionStr, [targetService, socketName],
    "/usr/lib/systemd/systemd-socket-proxyd --exit-idle-time=" &
      exitIdleTime & ' ' & connectTo, "", {s_no_new_priv, s_overwrite}, options)
  enableAndStart socketName
  systemdReload = true

proc socketProxy*(args: StrMap) =
  proxy(proxy=args.nonEmptyParam "proxy",
        listen=args.nonEmptyParam "listen",
        bindTo=args.getOrDefault "bind",
        connectTo=args.nonEmptyParam "connect",
        exitIdleTime=args.getOrDefault("idle-timeout", "10min"),
        targetService=args.getOrDefault "service")
