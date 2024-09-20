# FASC - FAst System Configurator

Utility to configure Debian, and partially Fedora installation fast into a state that I like.

It is opionated, which means that it creates configurations that the author likes, and isn't very flexible.
The configurations are also usually very minimal.

The author takes no responsibility for any damage that the tool very likely does to your Linux installation, mental state and earthly possessions. It is strongly recommended, that you never attempt running it, and to be safe, remove any traces of this abomination from any storage you have.

It is at least for now mostly undocumented. You can run the binary and it will display a list of subcommands.

The commands try to be idempotent, meaning that running same subcommand multiple times should give the same result as running it once.

It tries to not overwrite manual configuration changes, but not consistently, so beware.

It is written in Nim, as having statically typed language compiler to catch some stupid mistakes earlier is nice, and Nim produces quite small standalone binaries. Running `./build tiny` attempts to create musl-libc linked and upx compressed binary that contains all necessary resources, is currently under ~200kB and can be copied anywhere.

## Example setup of minimal Sway desktop

1. Install minimal Debian or Fedora Sway spin with root filesystem encryption.
2. Copy fasc into somewhere in path.
3. Use fasc for setup.

If using WIFI, setup iwd.

	fasc wlan
	iwctl

Add APT or DNF configuration and remove unneeded packages. This removes network manager, if it were installed.
On Debian this additionaly setups unattended upgrades.

	fasc prune

Common system configuration. On Debian this setups ALSA and on Fedora you supposedly already have pipewire.

	fasc common

Install sway destop.

	fasc sway

This starts up without any login, since you've supposedly just entered your disc encryption password.

If sway crashes, you must login as root from console and run `systemctl restart run-wayland` manually.It might be useful to additionally run this to get few utilities.

	fasc gui-packages
