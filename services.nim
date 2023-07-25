import std/[os, strutils, tables]
import utils

type ServiceFlags* = enum
  s_no_new_priv,
  s_sandbox,
  s_allow_devices,
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

proc setProperties(service: var seq[string], flags: set[ServiceFlags]) =
  if s_sandbox in flags or s_no_new_priv in flags:
    service &= [
      "CapabilityBoundingSet=~CAP_SYS_ADMIN",
      "MemoryDenyWriteExecute=true",
      "NoNewPrivileges=yes",
      "SecureBits=nonroot-locked",
    ]
  if s_sandbox in flags:
    service &= [
      "ProtectSystem=strict",
      "PrivateTmp=true",
      "ProtectControlGroups=yes",
      "ProtectKernelLogs=true",
      "ProtectKernelLogs=true",
      "ProtectKernelModules=yes",
      "ProtectKernelTunables=yes",
      "ProtectProc=invisible",
      "RestrictNamespaces=yes",
      "RestrictRealtime=yes",
      "RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX",
    ]
    if s_allow_netlink in flags:
      service &= " AF_NETLINK"
    if not (s_allow_devices in flags):
      service &= "PrivateDevices=true"
  if s_call_filter in flags:
    service &= [
      "SystemCallArchitectures=native",
      "SystemCallFilter=@system-service"
    ]
    when defined(arm):
      service &= " 270"

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
  service.setProperties flags
  service.add options
  if install != "":
    service.add ["", "[Install]", "WantedBy=" & install]
  service.add ""
  let serviceName = name & ".service"
  writeFile("/etc/systemd/system" / serviceName, service, s_overwrite in flags)
  if install != "":
    enableAndStart serviceName

proc overrideService*(name: string, flags: set[ServiceFlags],
                      properties: varargs[string]) =
  let override = "/etc/systemd/system/" & name & ".service.d/override.conf"
  var content = @["[Service]"] & @properties
  content.setProperties flags
  writeFile(override, content)
  systemdReload = true

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
