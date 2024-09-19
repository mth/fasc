# FASC - FAst System Configurator

Utility to configure Debian, and partially Fedora installation fast into a state that I like.

It is opionated, which means that it creates configurations that the author likes, and isn't very flexible.
The configurations are also usually very minimal.

The author takes no responsibility for any damage that the tool very likely does to your Linux installation, mental state and earthly possessions. It is strongly recommended, that you never attempt running it, and to be safe, remove any traces of this abomination from any storage you have.

It is at least for now mostly undocumented. You can run the binary and it will display a list of subcommands.

The commands try to be idempotent, meaning that running same subcommand multiple times should give the same result as running it once.

It tries to not overwrite manual configuration changes, but not consistently, so beware.

It is written in Nim, as having statically typed language compiler to catch some stupid mistakes earlier is nice, and Nim produces quite small standalone binaries. Running `./build tiny` attempts to create musl-libc linked and upx compressed binary that contains all necessary resources, is currently under ~200kB and can be copied anywhere.
