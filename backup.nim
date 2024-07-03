#import std/[parseutils, sequtils, strformat, strutils, os, tables]
#import apps, services, utils

import utils

# Create useradd function into utils that invokes useradd command
# (useradd should work across different distributions).

# TODO server
# * socket-activation vahendaja, et nbd-server käivitada ainult vastavalt vajadusele 
# * nbd-server systemd teenus
# * on-demand systemd mount backup failisüsteemile, mida nbd-server kasutaks
# * kasutaja loomine kes saaks ssh kaudu seda soklit kasutada
# * sshd conf ChrootDirectory ja AllowStreamLocalForwarding local kasutajale

# TODO klient
...?

