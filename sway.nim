import std/[strformat, posix]
import cmdqueue

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
    "ExecStart=/usr/bin/ssh-agent " & compositor,
    "KillMode=control-group",
    "Restart=no",
    "StandardInput=tty-fail",
    "StandardOutput=tty",
    "StandardError=journal",
    "TTYPath=/dev/tty7",
    "TTReset=yes",
    "TTYVHangup=yes",
    "TTYVTDisallocate=yes",
    "WorkingDirectory=" & home,
    "User=" & user,
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
  writeFile("/etc/systemd/system/run-wayland.service", service)
  enableUnits.add "run-wayland.service"
  packagesToInstall.add(["openssh-client", "qtwayland5"])
  systemdReload = true

proc swayUnit*() =
  runWayland("sway", "mzz")
  packagesToInstall.add("sway")
