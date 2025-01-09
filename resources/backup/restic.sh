#!/bin/sh

set -e

RESTIC_REPOSITORY={REPOSITORY_URL}
RESTIC_REST_USERNAME={REST_USERNAME}
RESTIC_REST_PASSWORD={REST_PASSWORD}

case "$1" in
	backup-and-forget-no-sleep)
		while ! systemd-inhibit --what=idle:sleep:handle-lid-switch:handle-suspend-key:handle-hibernate-key \
				--who=restic-backup /bin/true; do
			sleep 1
		done
		exec systemd-inhibit --what=idle:sleep:handle-lid-switch:handle-suspend-key:handle-hibernate-key \
			--who=restic-backup "--why=Active backup" "$0" backup-and-forget;;
	backup-and-forget)
		"$0" backup
		"$0" forget --keep-within-weekly 1m --keep-monthly 3
		exec "$0" prune;;
esac

export RESTIC_REPOSITORY RESTIC_REST_USERNAME RESTIC_REST_PASSWORD
exec /usr/bin/restic --cacert /etc/ssl/restic-server.pem "$@"
