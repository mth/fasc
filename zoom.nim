import std/[os, strutils, tables]
import utils

const sandbox_sh = readResource("sandbox.sh")
const zoom_url = "https://zoom.us/client/latest/zoom_x86_64.tar.xz"

proc makeSandbox(invoker, asUser: UserInfo; unit, sandboxScript, command: string) =
  sandboxScript.writeFile sandbox_sh.multiReplace(
    ("${USER}", asUser.user),
    ("${GROUP}", $asUser.gid),
    ("${HOME}", asUser.home),
    ("${COMMAND}", command),
    ("${SANDBOX}", sandboxScript),
    ("${UNIT}", unit))
  invoker.sudoNoPasswd "DISPLAY WAYLAND_DISPLAY", sandboxScript

proc downloadZoom(zoomUser: UserInfo, args: StrMap) =
  let tarPath = "/tmp/zoom.tar.xz"
  runCmd "wget", "-O", tarPath, args.getOrDefault("zoom", zoom_url)
  removeDir(zoomUser.home / "zoom")
  echo "Extracting ", tarPath, " into ", zoomUser.home
  runCmd "sudo", "-u", zoomUser.user,
         "tar", "-C", zoomUser.home, "-xf", tarPath, "zoom/"
  removeFile tarPath

proc zoomSandbox*(args: StrMap) =
  let invoker = args.userInfo
  let asUser =
    try:
      userInfo("zoom")
    except KeyError:
      runCmd("useradd", "-mNg", $invoker.gid, "-G", "audio,render,video",
             "-f", "0", "-d", "/var/lib/zoom", "-s", "/bin/false", "zoom")
      userInfo("zoom")
  if not fileExists(asUser.home / "zoom/zoom"):
    asUser.downloadZoom args
  setPermissions(asUser.home, 0o700)
  invoker.makeSandbox(asUser, "Zoom", "/usr/local/bin/zoom",
                      asUser.home / "zoom/ZoomLauncher")
  packagesToInstall &= ["libxcb-xtest0", "libxtst6", "x11-xserver-utils"]

proc updateZoom*(args: StrMap) =
  userInfo("zoom").downloadZoom args
