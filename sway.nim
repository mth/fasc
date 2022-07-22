import std/[strformat, os]
import utils, firefox

const user_config = [
  (".XCompose", """
include "%L"

<dead_tilde> <dead_tilde>: "≈"
<dead_circumflex> <n>: "ⁿ"
<dead_circumflex> <(>: "⁽"
<dead_circumflex> <)>: "⁾"
<dead_diaeresis> <m>: "µ"
"""), (".config/foot/foot.ini", """
font=Terminus:size=12,Monospace:size=12
title=Terminal
word-delimiters=,│`|\"'()[]{}<>

[mouse]
hide-when-typing=yes

[colors]
foreground=eee8aa
background=092a00
regular0=000000  # black
regular1=ee0000  # red
regular2=00ee00  # green
regular3=cdcd00  # yellow
regular4=0060dd  # blue
regular5=cd00cd  # magenta
regular6=00cdcd  # cyan
regular7=eee8aa  # white
bright0=999999   # bright black
bright1=ff0000   # bright red
bright2=00ff00   # bright green
bright3=ffff00   # bright yellow
bright4=88aaff   # bright blue
bright5=ff00ff   # bright magenta
bright6=00ffff   # bright cyan
bright7=ffffff   # bright white
"""), (".config/mpv/mpv.conf", """
hwdec=vaapi
vo=gpu
gpu-context=wayland
alang=en
sub-codepage=utf-8
vd-lavc-threads=4
"""), (".config/gammastep/config.ini", """
[redshift]
temp-day=6500
temp-night=2700
gamma=1
adjustment-method=wayland
location-provider=manual

[manual]
lat=59
lon=20
""")
]

const sway_config = [
  ("config", """
set $mod Mod4
set $left h
set $down j
set $up k
set $right l
set $term exec footclient
set $firefox_workspace 1

input * xkb_layout uml,ee
input * xkb_options grp:ctrls_toggle
output * bg #103800 solid_color

default_border pixel
client.focused #4c7899 #285577 #ffffff #2e9ef4 #daa520

hide_edge_borders --i3 smart
# hide_edge_borders --i3 both
# workspace_layout tabbed

bindsym $mod+o exec exec ~/.config/sway/firefox.sh --vdesk=$firefox_workspace
bindsym $mod+g exec /usr/games/xmahjongg
bindsym $mod+l exec swaylock -f -c 000000
bindsym $mod+s exec GRIM_DEFAULT_DIR=/tmp/downloads exec grim
bindsym XF86MonBrightnessUp exec brightnessctl -q s +2%
bindsym XF86MonBrightnessDown exec brightnessctl -q -n96 s 2%-

exec exec foot -s
exec exec gammastep -m wayland

include windows
include bindings
include idle
include bar
include touchpad
include /etc/sway/config.d/*
"""), ("idle", """
exec exec swayidle -w \
  timeout 600 'swaymsg "output * dpms off"' \
  resume 'swaymsg "output * dpms on"; pidof -q gammastep || gammastep&' \
  timeout 660 'swaylock -f -c 000000' \
  before-sleep 'swaylock -f -c 000000'
"""), ("idle2", """
exec exec swayidle -w \
  timeout 300 'swaymsg "output * dpms off"' \
  resume 'swaymsg "output * dpms on"' \
  timeout 480 'grep -q 1 /sys/class/power_supply/ACAD/online || systemctl suspend' \
  before-sleep 'swaylock -f -c 092a00' \
  after-resume 'swaymsg "output * dpms on"'
"""), ("bar", """
bar {
  position bottom
  mode overlay

  status_command exec bash ~/.config/sway/status.sh

  colors {
    statusline #ffff00
    background #05140540
    inactive_workspace #11113390 #11113370 #dddddd
  }
}
"""), ("bar2", """
bar {
  position bottom
  mode hide

  status_command exec bash ~/.config/sway/status.sh

  colors {
    statusline #ffff00
    background #000000
    inactive_workspace #111133 #111133 #dddddd
  }
}
"""), ("touchpad", """
input type:touchpad {
    dwt disabled
    tap enabled
    tap_button_map lmr
    # natural_scroll enabled
    middle_emulation enabled
}
"""), ("windows", """
for_window [app_id="firefox"] {
  move container to workspace $firefox_workspace
  workspace $firefox_workspace
}
for_window [app_id="chrome-token-signing"] floating enable
for_window [title="User Identification Request"] floating enable
for_window [title="Password Required - Mozilla Firefox"] floating enable
for_window [class="ioquake3"] {
  move container to workspace 8
  workspace 8
  fullscreen enable
}
"""), ("bindings", """
bindsym $mod+Return exec $term
bindsym $mod+t exec $term
bindsym $mod+Shift+s exec systemctl suspend

bindsym Mod1+Escape kill
floating_modifier $mod normal

bindsym $mod+Shift+c reload
bindsym $mod+Shift+e exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit sway? This will end your Wayland session.' -b 'Yes, exit sway' 'swaymsg exit'

# Move your focus around using $mod+[up|down|left|right]
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

# _move_ the focused window with the same, but add Shift
bindsym $mod+Shift+$left move left
bindsym $mod+Shift+$down move down
bindsym $mod+Shift+$up move up
bindsym $mod+Shift+$right move right
# ditto, with arrow keys
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

# switch to workspace
bindsym Mod1+Tab workspace back_and_forth
bindsym Mod4+Tab workspace next
bindsym $mod+1 workspace 1
bindsym $mod+2 workspace 2
bindsym $mod+3 workspace 3
bindsym $mod+4 workspace 4
bindsym $mod+5 workspace 5
bindsym $mod+6 workspace 6
bindsym $mod+7 workspace 7
bindsym $mod+8 workspace 8
bindsym $mod+9 workspace 9
bindsym $mod+0 workspace 10
# move focused container to workspace
bindsym $mod+Shift+1 move container to workspace 1
bindsym $mod+Shift+2 move container to workspace 2
bindsym $mod+Shift+3 move container to workspace 3
bindsym $mod+Shift+4 move container to workspace 4
bindsym $mod+Shift+5 move container to workspace 5
bindsym $mod+Shift+6 move container to workspace 6
bindsym $mod+Shift+7 move container to workspace 7
bindsym $mod+Shift+8 move container to workspace 8
bindsym $mod+Shift+9 move container to workspace 9
bindsym $mod+Shift+0 move container to workspace 10
# Note: workspaces can have any name you want, not just numbers.
# We just use 1-10 as the default.

# You can "split" the current object of your focus with
# $mod+b or $mod+v, for horizontal and vertical splits
# respectively.
bindsym $mod+b splith
bindsym $mod+v splitv

# Switch the current container between different layout styles
#bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+e layout toggle split

# Make the current focus fullscreen
bindsym $mod+f fullscreen

# Toggle the current focus between tiling and floating mode
bindsym $mod+Shift+space floating toggle

# Swap focus between the tiling area and the floating area
bindsym $mod+space focus mode_toggle

# move focus to the parent container
bindsym $mod+a focus parent

# Sway has a "scratchpad", which is a bag of holding for windows.
# You can send windows there and get them back later.

# Move the currently focused window to the scratchpad
bindsym $mod+Shift+minus move scratchpad

# Show the next scratchpad window or hide the focused scratchpad window.
# If there are multiple scratchpad windows, this command cycles through them.
bindsym $mod+minus scratchpad show

mode "resize" {
    # left will shrink the containers width
    # right will grow the containers width
    # up will shrink the containers height
    # down will grow the containers height
    bindsym $left resize shrink width 10px
    bindsym $down resize grow height 10px
    bindsym $up resize shrink height 10px
    bindsym $right resize grow width 10px

    # ditto, with arrow keys
    bindsym Left resize shrink width 10px
    bindsym Down resize grow height 10px
    bindsym Up resize shrink height 10px
    bindsym Right resize grow width 10px

    # return to default mode
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"
"""), ("status.sh", """
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
""")]

const xkb_uml = """
partial alphanumeric_keys
xkb_symbols "basic" {
    include "us(dvorak)"
    name[Group1]= "Deadkeys umlaut (Dvorak)";

    key <CAPS>  { [ dead_diaeresis, dead_tilde, dead_caron, dead_grave ] };
    #key <FK12>  { [ Next, Next ] }; 
    #key <PRSC>  { [ Prior, Prior ] };

    include "level3(ralt_switch)"
    include "kpdl(comma)"
    include "eurosign(4)"
};
"""

const font_auto_hinting = """
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
 <match target="font" >
  <edit mode="assign" name="hinting" >
   <bool>true</bool>
  </edit>
 </match>
 <match target="font" >
  <edit mode="assign" name="autohinting" >
   <bool>true</bool>
  </edit>
 </match>
 <match target="font" >
  <edit mode="assign" name="hintstyle" >
   <const>hintmedium</const>
  </edit>
 </match>
 <match target="font">
  <edit mode="assign" name="rgba">
   <const>rgb</const>
  </edit>
 </match>
</fontconfig>
"""

proc runWayland(compositor, user: string, info: UserInfo) =
  let gid = info.gid
  var service = [
    "[Unit]",
    "Description=Runs wayland desktop",
    "Wants=sysinit.target usb-gadget.target",
    "After=systemd-user-sessions.service plymouth-quit-wait.service sysinit.target usb-gadget.target",
    "",
    "[Service]",
    fmt"ExecStartPre=/usr/bin/install -m 700 -o {user} -g {gid} -d /tmp/.{user}-cache",
    fmt"ExecStartPre=/usr/bin/install -m 700 -o {user} -g {gid} -d /tmp/downloads",
    "ExecStart=" & compositor,
    "KillMode=control-group",
    "Restart=no",
    "StandardInput=tty-fail",
    "StandardOutput=tty",
    "StandardError=journal",
    "TTYPath=/dev/tty7",
    "TTYReset=yes",
    "TTYVHangup=yes",
    "TTYVTDisallocate=yes",
    "WorkingDirectory=" & info.home,
    "User=" & user,
    fmt"Group={info.gid}",
    "PAMName=login",
    "UtmpIdentifier=tty7",
    "UtmpMode=user",
    "Environment=GDK_BACKEND=wayland" &
    " QT_QPA_PLATFORM=wayland-egl" &
    " XDG_SESSION_TYPE=wayland" &
    " MOZ_WEBRENDER=1" &
    " LANG=et_EE.utf8", # should be read from /etc/default/locale
    "",
    "[Install]",
    "WantedBy=graphical.target",
    ""
  ]
  writeFile("/etc/systemd/system/run-wayland.service", service)
  writeFile("/etc/fonts/conf.d/10-autohinting.conf", [font_auto_hinting])
  enableUnits.add "run-wayland.service"
  packagesToInstall.add(["qtwayland5", "xwayland"])
  systemdReload = true
  runCmd("usermod", "-G",
    "adm,audio,cdrom,input,kvm,video,render,systemd-journal", user)

proc configureSway(user: UserInfo) =
  for (file, conf) in user_config:
    writeAsUser(user, file, conf)
  for (file, conf) in sway_config:
    writeAsUser(user, ".config/sway" / file, conf)
  user.firefoxConfig

proc swayConf*(args: Strs) =
  let user = "mzz" # TODO
  echo "swayConf called."
  configureSway user.userInfo

proc swayUnit*(args: Strs) =
  let user = "mzz" # TODO
  let info = user.userInfo
  writeFile("/usr/share/X11/xkb/symbols/uml", @[xkb_uml])
  configureSway info
  runWayland("/usr/bin/ssh-agent /usr/bin/sway", "mzz", info)
  let ytdlAlias = "/usr/local/bin/youtube-dl"
  if not ytdlAlias.fileExists:
    try:
      createSymlink("/usr/bin/yt-dlp", ytdlAlias)
    except:
      echo("Cannot link /usr/bin/yt-dlp to ", ytdlAlias)
  addFirefoxESR()
  # fonts-dejavu? fonts-liberation? fonts-freefont-ttf?
  packagesToInstall.add ["sway", "swayidle", "openssh-client", "foot",
                         "evince", "gammastep", "grim", "mpv", "yt-dlp",
                         "fonts-terminus-otb", "fonts-unifont"]
  if listDir("/sys/class/backlight").len != 0:
    packagesToInstall.add ["brightnessctl", "brightness-udev"]
