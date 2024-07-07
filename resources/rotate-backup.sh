#!/bin/sh

for CLIENT_DIR in /media/backupstore/client/*; do
	ACTIVE_IMAGE="$CLIENT_DIR/active/backup.img"
	if [ -e "$ACTIVE_IMAGE" ]; then
		NUMBER="$(("$(/bin/date +%j)" / 28 % 3))"
		/bin/cp --reflink "$ACTIVE_IMAGE" "$CLIENT_DIR/backup-$NUMBER.img"
	fi
done
