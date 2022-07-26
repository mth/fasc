exec 5<> <(:)
while true; do
	OUT="`for net in /sys/class/net/wl*; do
		/sbin/iw dev "${net##*/}" link | {
			while read iw; do
				parts=($iw)
				case "${iw%%:*}" in
				signal) signal=${parts[1]};;
				rx\ bitrate) rx=${parts[2]};;
				tx\ bitrate) tx=${parts[2]};;
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
	read -t 10 <&5
done
