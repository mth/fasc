import std/[sequtils, strutils, os]
import utils

iterator getReleaseTags(baseURL: string): string =
  for line in outputOfCommand("", "/usr/bin/wget", "-qO", "-",
                baseURL & ".git/info/refs?service=git-upload-pack"):
    let parts = line.split(' ', 2)
    if parts.len > 1:
      let name = parts[1]
      if name.startsWith("refs/tags/v") and '^' notin name:
        yield name[10..^1]

proc lastVersion(baseURL: string): string =
  var latestVersion: seq[string] = @[]
  for tag in getReleaseTags(baseUrl):
    let version = tag.split('.').mapIt(it.align(6, '0'))
    for i, v in version:
      if i >= latestVersion.len or v > latestVersion[i]:
        result = tag
        latestVersion = version
        break
      if v < latestVersion[i]:
        break

when defined(i386):
  const ARCH = "i686"
when defined(amd64):
  const ARCH = "x86_64"
when defined(arm):
  const ARCH = "arm"
when defined(arm64):
  const ARCH = "aarch64"

proc githubDownload(repository, target: string; nameFunc: proc(name, version: string): string) =
  let name = repository.split('/', 2)
  if name.len < 2:
    echo "Repository name '", repository, "' must contain '/'"
    quit 1
  if target.fileExists:
    echo "Not downloading an existing file: ", target
    return
  let baseUrl = "https://github.com/" & repository
  if not fileExists("/usr/bin/wget"):
    packagesToInstall.add "wget"
    commitQueue()
  let version = baseUrl.lastVersion
  let tarname = nameFunc(name[1], version)
  let fromURL = baseUrl & "/releases/download/" & version & '/' & tarname
  echo "Downloading ", fromURL, "..."
  runCmd "wget", "-O", target, fromURL

func versionedTarGz(name, version: string): string =
  name & '-' & version & '-' & ARCH & "-unknown-linux-gnu.tar.gz"

func unversionedTarXz(name, version: string): string =
  name & '-' & ARCH & "-unknown-linux-gnu.tar.xz"

#githubDownload "rustic-rs/rustic", "/tmp/rustic.tar.gz", versionedTarGz
githubDownload "rustic-rs/rustic_server", "/tmp/rustic-server.tar.gz", unversionedTarXz
