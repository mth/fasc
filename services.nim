import std/[os, strutils, tables]
import utils

proc proxy*(proxy, listen, bindTo, connectTo, exitIdleTime, targetService: string,
            description = "") =
  let socketParam = proxy.split ':'
  let socketName = socketParam[0] & ".socket"
  let serviceName = socketParam[0] & ".service"
  let descriptionStr = if description != "": description
                       else: socketParam[0].replace('-', ' ').capitalizeAscii
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

  var serviceDep = targetService
  if serviceDep != "":
    if '.' notin serviceDep:
      serviceDep &= ".service"
    serviceDep &= ' '
  var service = @[
    "[Unit]",
    "Description=" & descriptionStr & " service",
    "Requires=" & serviceDep & socketName,
    "After=" & serviceDep & socketName,
    "",
    "[Service]",
    "ExecStart=" & "/usr/lib/systemd/systemd-socket-proxyd --exit-idle-time=" &
      exitIdleTime & ' ' & connectTo,
    "PrivateTmp=yes",
    "CapabilityBoundingSet=~CAP_SYS_ADMIN",
    "MemoryDenyWriteExecute=true",
    "NoNewPrivileges=yes",
    "SecureBits=nonroot-locked",
  ]
  if listen.startsWith("/") and connectTo.startsWith("/"):
    service &= "PrivateNetwork=yes"
  writeFile("/etc/systemd/system" / serviceName, service, force=true)
  enableAndStart socketName
  systemdReload = true

proc socketProxy*(args: StrMap) =
  proxy(proxy=args.nonEmptyParam "proxy",
        listen=args.nonEmptyParam "listen",
        bindTo=args.getOrDefault "bind",
        connectTo=args.nonEmptyParam "connect",
        exitIdleTime=args.getOrDefault("idle-timeout", "10min"),
        targetService=args.getOrDefault "service")
