#!/bin/sh
# Starts a headless dedicated co-op server from the project folder. Windows: tools\server.cmd
#   tools/server.sh [--vlan] [--port N] [--max-players 2..8] [--save-dir PATH] [--name NAME] [--status SECONDS] [--idle-kick MIN]
# --vlan: also host the zs-vlan virtual LAN (tools/vlan/vlan_auto.sh host runs first, so a sudo
#   prompt for the firewall works here); the console then takes invite / add / guests / revoke.
# Type "help" in the server window for its commands; "stop" saves and quits.
# Godot binary: $GODOT, else `godot` on the PATH, else a Godot_v*_linux.x86_64 next to the project folder.
cd "$(dirname "$0")/.." || exit 1
if [ -z "$GODOT" ]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT=godot
	else
		GODOT=$(ls ../Godot_v*_linux.x86_64 2>/dev/null | tail -n 1)
	fi
fi
if [ -z "$GODOT" ]; then
	echo "server.sh: no Godot binary found; set GODOT=/path/to/Godot" >&2
	exit 1
fi
for a in "$@"; do
	if [ "$a" = --vlan ]; then
		tools/vlan/vlan_auto.sh host </dev/null || { echo "server.sh: the virtual LAN didn't come up (see above); fix it or start without --vlan" >&2; exit 1; }
		echo
	fi
done
# a fresh checkout has no import cache yet
if [ ! -d .godot/imported ]; then
	echo "server.sh: first start, importing the project..."
	"$GODOT" --headless --path . --import >/dev/null 2>&1
fi
exec "$GODOT" --headless --path . -- --server "$@"
