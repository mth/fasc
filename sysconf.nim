import std/[parsecfg, posix, strformat, strutils, tables, os, osproc]

proc runCmd(command: string, args: varargs[string]) =
  let process = startProcess(command, "", args, nil, {poParentStreams, poUsePath})
  let exitCode = process.waitForExit
  if exitCode != 0:
    echo fmt"Executing {command} with {args} failed with exit code {exitCode}"
    quit 1

proc runWayland(compositor, user: string) =
  let pw = user.getpwnam
  if pw == nil:
    echo fmt"Unknown user {user}"
    quit 1
  let groupId = pw.pw_gid
  let home = $pw.pw_dir
  var service = [
    "[Unit]",
    "Description=Runs wayland desktop",
    "Wants=usb-gadget.target",
    "After=systemd-user-sessions.service plymouth-quit-wait.service usb-gadget.target",
    "",
    "[Service]",
    fmt"ExecStartPre=/usr/bin/install -m 700 -o {user} -g {user} -d /tmp/.{user}-cache",
    "ExecStart=/usr/bin/ssh-agent ${compositor}",
    "KillMode=control-group",
    "Restart=no",
    "StandardInput=tty-fail",
    "StandardOutput=tty",
    "StandardError=journal",
    "TTYPath=/dev/tty7",
    "TTReset=yes",
    "TTYVHangup=yes",
    "TTYVTDisallocate=yes",
    "WorkingDirectory={home}",
    fmt"User={user}",
    fmt"Group={groupId}",
    "PAMName=login",
    "UtmpIdentifier=tty7",
    "UtmpMode=user",
    "Environment=GDK_BACKEND=wayland QT_QPA_PLATFORM=wayland-egl XDG_SESSION_TYPE=wayland MOZ_WEBRENDER=1 LANG=et_EE.utf8",
    "",
    "[Install]",
    "WantedBy=graphical.target",
    ""
  ]
  echo service.join("\n")

proc sway() =
  runWayland("sway", "mzz")
  runCmd("apt", "install", "sway", "openssh-client", "qtwayland5")

let tasks = {
  "sway": ("Configure sway desktop startup", sway)
}.toTable

if not (paramStr(1) in tasks):
  echo "Unknown task: ", paramStr(1)
else:
  tasks[paramStr(1)][1]()
