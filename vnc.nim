import std/[strformat, strutils, tables]
import utils, services

proc installVncServer*(args: StrMap) =
  packagesToInstall.add ["tigervnc-standalone-server", "icewm"]
  commitQueue()
  let userInfo = args.userInfo
  let display = args.getOrDefault("display", "2").strip(chars={':'})
  let listenProxy = args.getOrDefault "proxy"
  discard modifyProperties("/etc/tigervnc/vncserver.users",
            [(':' & display, userInfo.user)])
  if listenProxy.len != 0:
    proxy(proxy="vnc-proxy",
          listen=listenProxy,
          bindTo=args.getOrDefault "proxy-bind",
          connectTo=fmt"127.0.0.1:{5900 + display.parseInt}",
          exitIdleTime="10min",
          targetService=fmt"tigervncserver@:{display}")
