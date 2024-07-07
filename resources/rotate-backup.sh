#!/bin/sh

BACKUPS_DIR="/media/backupstore/client"

for CLIEND_DIR in $BACKUPS_DIR/*; do
	ACTIVE_IMAGE="$CLIENT_DIR/active/backup.img"
	if [ -e "$ACTIVE_IMAGE" ]; then
		cp --reflink "$ACTIVE_IMAGE" "$CLIENT_DIR/backup-TODO.img"
	fi
done
