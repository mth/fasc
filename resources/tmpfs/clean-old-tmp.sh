#!/bin/sh

set -e
mkdir /tmp/.clean-old-tmp
mount --bind / /tmp/.clean-old-tmp
find /tmp/.clean-old-tmp/tmp -mindepth 1 -maxdepth 1 -exec rm -rf '{}' +
umount /tmp/.clean-old-tmp
rmdir /tmp/.clean-old-tmp
rm -f /etc/systemd/system/clean-old-tmp.service /var/spool/clean-old-tmp.sh
systemctl disable clean-old-tmp.service
