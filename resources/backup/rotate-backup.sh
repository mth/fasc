#!/bin/bash

set -e

for CLIENT_DIR in /media/backupstore/client/*; do
	ACTIVE_IMAGE="$CLIENT_DIR/active/backup.image"
	if [ -e "$ACTIVE_IMAGE" ]; then
		# % is bash
		NUMBER="$(("$(/bin/date +%m)" % 3))"
		/bin/cp -v --reflink "$ACTIVE_IMAGE" "$CLIENT_DIR/backup-$NUMBER.image" || true
	fi
done
