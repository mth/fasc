import std/[sequtils, strformat, strutils, os]
import utils

proc fetchTLSCerts*(url: string): seq[string] =
  if url.startsWith "http:":
    return
  let host = if url.startsWith "https://": url[8..^1].split('/')[0]
             else: url
  var in_cert = false
  for line in outputOfCommand("", true, "openssl", ["s_client", "-showcerts", "-connect", host]):
    if line == "-----BEGIN CERTIFICATE-----":
      result.add(line & '\n')
      in_cert = true
    elif in_cert:
      result[^1] &= line
      result[^1] &= '\n'
      if line == "-----END CERTIFICATE-----":
        in_cert = false

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
  const ARCH = "amd64"
when defined(arm):
  const ARCH = "arm"
when defined(arm64):
  const ARCH = "arm64"

proc githubDownload(repository, target: string; nameFunc: proc(version: string): string) =
  let baseUrl = "https://github.com/" & repository
  addPackageUnless "wget", "/usr/bin/wget", true
  let version = baseUrl.lastVersion
  let tarname = nameFunc(version[1..^1])
  let fromURL = baseUrl & "/releases/download/" & version & '/' & tarname
  echo "Downloading ", fromURL, "..."
  removeFile target
  runCmd "wget", "-O", target, fromURL

#func versionedTarGz(version: string): string =
#  "rustic-" & version & '-' & ARCH & "-unknown-linux-gnu.tar.gz"

#func unversionedTarXz(version: string): string =
#  "rustic_server-" & ARCH & "-unknown-linux-gnu.tar.xz"

proc githubExtract(repository, tmpFile, inTar, target: string, nameFunc: proc(version: string): string) =
  createDir target
  defer: removeFile tmpFile
  githubDownload repository, tmpFile, nameFunc
  let opt = if tmpFile.endsWith("xz"): "-xJf"
            else: "-xzf"
  runCmd "tar", "-C", target, opt, tmpFile, inTar

#githubDownload "rustic-rs/rustic", "/tmp/rustic.tar.gz", versionedTarGz
#githubDownload "rustic-rs/rustic_server", "/tmp/rustic-server.tar.gz", unversionedTarXz

func resticServerTarGz(version: string): string =
  fmt"rest-server_{version}_linux_{ARCH}.tar.gz"

proc downloadResticServer*(user: UserInfo) =
  let filename = "rest-server"
  let destDir = "/opt/restic" 
  let destFile = destDir / filename
  if destFile.fileExists:
    echo "Not downloading an existing file: ", destFile
    return
  let tarDir = "rest-server_0.13.0_linux_" & ARCH
  githubExtract "restic/rest-server", "/tmp/restic-server.tar.gz",
                tarDir / filename, destDir, resticServerTarGz
  moveFile destDir / tarDir / filename, destFile
  removeDir destDir / tarDir
  setPermissions destDir, 0, user.gid, 0o750
  setPermissions destDir / filename, 0, user.gid, 0o650

