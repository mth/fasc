import std/strutils
import utils

const sandbox_sh = readResource("sandbox.sh")

proc makeSandbox(invoker, asUser: UserInfo;
                 sandboxScript, runScript, unit: string) =
  sandboxScript.writeFile sandbox_sh.multiReplace(
    ("${USER}", asUser.user),
    ("${GROUP}", asUser.group),
    ("${HOME}", asUser.home),
    ("${RUNSCRIPT}", runScript),
    ("${SANDBOX}", sandboxScript),
    ("${XHOST}", ""),
    ("${UNIT}", unit))
  invoker.sudoNoPasswd "WAYLAND_DISPLAY", sandboxScript
