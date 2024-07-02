#import std/[parseutils, sequtils, strformat, strutils, os, tables]
#import apps, services, utils

import utils

# TODO server
# * bind mähkur mis võimaldab systemd socket activation nbd-server'ile
# * nbd-server systemd teenus mis kuulab soklit
# * on-demand systemd mount backup failisüsteemile, mida nbd-server kasutaks
# * kasutaja loomine kes saaks ssh kaudu seda soklit kasutada
# * sshd conf ChrootDirectory ja AllowStreamLocalForwarding local kasutajale

# TODO klient
...?

