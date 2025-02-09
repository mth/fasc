#!/bin/sh

set -e

RESTIC_REPOSITORY={REPOSITORY}
RESTIC_REST_USERNAME={REST_USERNAME}
RESTIC_REST_PASSWORD={REST_PASSWORD}
RESTIC_PASSWORD_FILE="/etc/backup/.restic-repo-password"
BACKUP_DIRS="/etc /root /var /home /usr/local /srv"

case "$1" in
	backup-and-forget-no-sleep)
		while ! systemd-inhibit --what=idle:sleep:handle-lid-switch:handle-suspend-key:handle-hibernate-key \
				--who=restic-backup /bin/true; do
			sleep 1
		done
		exec systemd-inhibit --what=idle:sleep:handle-lid-switch:handle-suspend-key:handle-hibernate-key \
			--who=restic-backup "--why=Active backup" "$0" backup-and-forget;;
	backup-and-forget)
		"$0" -v backup --one-file-system $BACKUP_DIRS --exclude nobackup --exclude .cache \
			--exclude /var/cache --exclude /var/tmp --exclude /var/lib/machines --exclude .cargo/registry \
			--exclude '/home/**/target' --exclude _build --exclude '*.o' --exclude '*.class'
		"$0" forget --keep-within-weekly 1m --keep-monthly 3
		exec "$0" prune;;
esac

export RESTIC_REPOSITORY RESTIC_REST_USERNAME RESTIC_REST_PASSWORD RESTIC_PASSWORD_FILE
exec /usr/bin/restic --cacert /etc/backup/restic-server.pem "$@"
