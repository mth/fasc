#!/bin/sh

[ "${1%%=*}" != "--vdesk" ] || { FXVDESK="${1#*=}"; shift;}
MOZ_WEBRENDER=1
export MOZ_WEBRENDER
[ -n "$FXVDESK" ] && swaymsg -t get_tree | grep -q '"app_id": "firefox-esr"' || exec /usr/bin/firefox-esr "$@"
swaymsg workspace "$FXVDESK"
