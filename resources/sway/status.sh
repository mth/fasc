exec 5<> <(:)
while true; do
	OUT="`for net in /sys/class/net/wl*; do
		[ -e "$net" ] && /sbin/iw dev "${net##*/}" link | {
			while read -ra iw; do
				case "${iw[0]}" in
				signal:) signal=${iw[1]};;
				rx) rx=${iw[2]};;
				tx) tx=${iw[2]};;
				esac
			done
			if [ -n "$signal$rx" ]; then
				echo -n " 📶"
				[ -z "$signal" ] || echo -n "${signal}dBm "
				[ -z "$rx" ] || echo -n "${rx%.*}/${tx%.*}Mb/s "
			fi
		}
	done`"

	for bat in /sys/class/power_supply/BAT*; do
		[ -e "$bat/status" ] || continue
		read stat < "$bat/status"
		case "$stat" in
		Charging) OUT="$OUT ⌁";;
		Discharging) OUT="$OUT ↯";;
		*) OUT="$OUT B:"
		esac
		read bat_now < "$bat/energy_now"
		read bat_full < "$bat/energy_full"
		OUT="$OUT$((($bat_now * 100 + 49) / $bat_full))% "
	done

	printf "%s 🗓%(%e. %H:%M)T\n" "$OUT"
	read -t ${1:-1} <&5
done
