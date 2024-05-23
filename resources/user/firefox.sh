#!/bin/sh

[ "${1%%=*}" != "--vdesk" ] || { FXVDESK="${1#*=}"; shift;}
MOZ_WEBRENDER=1
TERMINAL='foot '
export MOZ_WEBRENDER TERMINAL
[ -n "$FXVDESK" ] && swaymsg -t get_tree | grep -q '"app_id": "org.mozilla.firefox"' || exec setsid /usr/bin/firefox "$@"
swaymsg workspace "$FXVDESK"
