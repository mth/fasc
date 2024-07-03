#import std/[parseutils, sequtils, strformat, strutils, os, tables]
#import apps, services, utils

import utils

proc createBackupUser(name, home: string): UserInfo =
  try:
    return name.userInfo # already exists
  except KeyError:
    let nbdGid = groupId("nbd")
    let group = if nbdGid != -1: $nbdGid
                else: ""
    addSystemUser name, group, home
    return name.userInfo

# TODO server
# * socket-activation vahendaja, et nbd-server käivitada ainult vastavalt vajadusele 
#   (using proxy function from services module)
# * nbd-server systemd teenus
# * on-demand systemd mount backup failisüsteemile, mida nbd-server kasutaks
# * kasutaja loomine kes saaks ssh kaudu seda soklit kasutada
# * sshd conf ChrootDirectory ja AllowStreamLocalForwarding local kasutajale

# TODO klient
...?

