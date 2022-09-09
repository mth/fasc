import std/[os, strutils, tables]
import utils

type ServiceFlags* = enum
  s_sandbox,
  s_overwrite

func descriptionOfName(name, description: string): string =
  if description != "":
    return description
  return name.replace('-', ' ').capitalizeAscii

proc addService*(name, description: string, depends: openarray[string],
                 exec: string, install="", flags: set[ServiceFlags] = {},
                 options: openarray[string] = [], serviceType="") =
  var depString = ""
  for dep in depends:
    if dep != "":
      if depString != "":
        depString &= ' '
      depString &= dep
      if '.' notin name:
        depString &= ".service"
  var service = @["[Unit]", "Description=" & description]
  if depString != "":
    service &= "Requires=" & depString
    service &= "After=" & depString
  service.add ["", "[Service]"]
  if serviceType != "":
    service &= "Type=" & serviceType
  service &= "ExecStart=" & exec
  if s_sandbox in flags:
    service &= [
      "CapabilityBoundingSet=~CAP_SYS_ADMIN",
      "MemoryDenyWriteExecute=true",
      "NoNewPrivileges=yes",
      "SecureBits=nonroot-locked",
    ]
  service.add options
  if install != "":
    service.add ["", "[Install]", "WantedBy=" & install]
  service.add ""
  let serviceName = name & ".service"
  writeFile("/etc/systemd/system" / serviceName, service, s_overwrite in flags)
  if install != "":
    enableAndStart serviceName

proc proxy*(proxy, listen, bindTo, connectTo, exitIdleTime, targetService: string,
            description = "") =
  let socketParam = proxy.split ':'
  let socketName = socketParam[0] & ".socket"
  let descriptionStr = descriptionOfName(socketParam[0], description)
  var socket = @[
    "[Unit]",
    "Description=" & descriptionStr,
    "",
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
      exitIdleTime & ' ' & connectTo, "", {s_sandbox, s_overwrite}, options)
  enableAndStart socketName
  systemdReload = true

proc socketProxy*(args: StrMap) =
  proxy(proxy=args.nonEmptyParam "proxy",
        listen=args.nonEmptyParam "listen",
        bindTo=args.getOrDefault "bind",
        connectTo=args.nonEmptyParam "connect",
        exitIdleTime=args.getOrDefault("idle-timeout", "10min"),
        targetService=args.getOrDefault "service")
