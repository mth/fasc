import std/strutils
import utils

const sandbox_sh = readResource("sandbox.sh")

proc makeSandbox(invoker, asUser: UserInfo;
                 unit, sandboxScript, command, env: string) =
  sandboxScript.writeFile sandbox_sh.multiReplace(
    ("${USER}", asUser.user),
    ("${GROUP}", asUser.group),
    ("${HOME}", asUser.home),
    ("${COMMAND}", command),
    ("${SANDBOX}", sandboxScript),
    ("${XHOST}", ""),
    ("${ENV}", env),
    ("${UNIT}", unit))
  invoker.sudoNoPasswd "WAYLAND_DISPLAY", sandboxScript

proc zoomSandbox(invoker: UserInfo) =
  let asUser = (user: "zoom", home: "/home/zoom", )
  invoker.makeSandbox(
