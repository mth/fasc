import std/[os, posix, strutils]

const TAR_FILE_TYPE* = '0'
const TAR_DIR_TYPE*  = '5'

type TarRecord* = tuple[name: string; flag: char; mode: int; user, group, content: string]

proc tar*(records: varargs[TarRecord]): string =
  var ts: Timespec
  discard clock_gettime(CLOCK_REALTIME, ts)
  for record in records:
    let name = record.name.splitPath
    var h = name.tail.alignLeft(100, '\0') &
      record.mode.toOct(7) & "\x000000000\x000000000\0" &
      record.content.len.toOct(11) & '\0' &
      ts.tv_sec.BiggestInt.toOct(11) & '\0' & spaces(8) &
      record.flag & repeat('\0', 100) & "ustar\x0000" &
      record.user.alignLeft(32, '\0') &
      record.group.alignLeft(32, '\0') &
      "0000000\x000000000\x00" & # device
      name.head.alignLeft(167, '\0')
    var checksum: uint = 0
    for ch in h:
      checksum += ch.uint8
    h[148..154] = checksum.int.toOct(6) & '\0'
    result &= h
    let fullLen = record.content.len div 512 * 512
    result &= record.content[0..<fullLen]
    if fullLen < record.content.len:
      result &= record.content[fullLen..^1].alignLeft(512, '\0')
  result &= repeat('\0', 1024)

proc tarRecords*(files: openarray[(string, int, string)],
                 user = "root", group = "root"): seq[TarRecord] =
  for (path, mode, content) in files:
    let (name, flag) = if path.endsWith '/': (path[0..^2], TAR_DIR_TYPE)
                       else: (path, TAR_FILE_TYPE)
    result &= (name: name, flag: flag, mode: mode,
               user: user, group: group, content: content)
