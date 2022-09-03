#!/bin/sh
# Defaults!/usr/local/bin/zoom env_keep=WAYLAND_DISPLAY

if [ "`id -u`" != 0 ]; then
	xhost +si:localuser:${USER}
	exec sudo ${SANDBOX}
fi

stop_zoom() {
	systemctl stop ${UNIT} >/dev/null 2>&1
}

stop_zoom
trap stop_zoom INT EXIT

XDG_RUNTIME_DIR="/run/user/`id -u ${USER}`"
chmod 770 "/run/user/$SUDO_UID/$WAYLAND_DISPLAY"
/usr/bin/install -d -o ${USER} -g ${GROUP} -m 700 "$XDG_RUNTIME_DIR"
systemd-run -P -G --no-ask-password --unit=${UNIT} \
	-p ProtectSystem=strict \
	-p ProtectKernelTunables=true \
	-p ProtectKernelModules=true \
	-p ProtectControlGroups=true \
	-p NoNewPrivileges=true \
	-p CapabilityBoundingSet=~CAP_SYS_ADMIN \
	-p 'ReadWritePaths=${HOME} /tmp' \
	-p User=${USER} -p Group=${GROUP} \
	-p "BindPaths=/run/user/$SUDO_UID/$WAYLAND_DISPLAY:$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" \
	-p "Environment=HOME=${HOME} XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY QT_QPA_PLATFORM=wayland-egl XDG_SESSION_TYPE=wayland" \
	${COMMAND} "$@"
