import std/[sequtils, strutils]
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

echo lastVersion("https://github.com/rustic-rs/rustic")
