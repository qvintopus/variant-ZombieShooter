#!/usr/bin/env bash
# Dedicated co-op server control, Linux. Windows: tools\server.cmd. See tools/vlan/README.md.
#   tools/server.sh                  menu: start / stop / restart, status, players, log, console, settings
#   tools/server.sh start [options]  start it in the background (saved settings, plus these options)
#   tools/server.sh stop             save the run, tell the players, quit
#   tools/server.sh restart          stop, then start
#   tools/server.sh status           running or not, room, players, uptime, settings
#   tools/server.sh players          who is connected
#   tools/server.sh log              follow the server's log (Ctrl+C goes back)
#   tools/server.sh console          type server commands (help lists them) into the running server
#   tools/server.sh send <command>   one server command, e.g. send kick 2
#   tools/server.sh settings         change the saved settings (port, name, players, idle kick, VLAN)
#   tools/server.sh run [options]    run it in this window instead (also: server.sh --port ... as before)
# Options: --vlan --port N --max-players 2..8 --save-dir PATH --name NAME --status SECONDS --idle-kick MIN
# The server runs in the background until stopped (closing the menu leaves it running); its log is in
# ~/.local/state/zs-server/server.log. The menu talks to it over 127.0.0.1 with a token only this user
# can read. Godot: $GODOT, else `godot` on the PATH, else a Godot binary near the project (see find_godot).
set -u
cd "$(dirname "$0")/.." || exit 1
DIR=${XDG_STATE_HOME:-$HOME/.local/state}/zs-server
CONTROL=$DIR/control
LOG=$DIR/server.log
SETTINGS=$DIR/settings
SELF=tools/server.sh
mkdir -p "$DIR" && chmod 700 "$DIR"

# Godot: $GODOT, `godot` on the PATH, else a binary in the project folder, the folder above it, tools/, or a
# Godot* folder in those. Names: Godot_v*_linux.x86_64 (as it comes in the zip), godot, godot.x86_64.
find_godot() {
	local d n f want near=()
	want=$(sed -n 's/^config\/features=PackedStringArray("\([0-9]*\.[0-9]*\)".*/\1/p' project.godot 2>/dev/null)
	if [ -n "${GODOT:-}" ]; then
		if [ -f "$GODOT" ] || command -v "$GODOT" >/dev/null 2>&1; then return 0; fi
		echo "GODOT is set to '$GODOT', but there's no such file; looking in the usual places instead." >&2
		GODOT=
	fi
	if command -v godot >/dev/null 2>&1; then GODOT=godot; return 0; fi
	local dirs=(. .. tools)
	for d in . .. tools; do for f in "$d"/Godot*/; do [ -d "$f" ] && dirs+=("${f%/}"); done; done
	for n in 'Godot_v*_linux.x86_64' godot godot.x86_64; do
		for d in "${dirs[@]}"; do
			# shellcheck disable=SC2086
			f=$(ls -d "$d"/$n 2>/dev/null | sort -V | tail -n 1)
			[ -n "$f" ] && [ -f "$f" ] && { [ -x "$f" ] || chmod +x "$f"; GODOT=$f; return 0; }
		done
	done
	{
		echo "no Godot found. Put the Godot ${want:-4} binary for Linux in the project folder or the folder above it:"
		echo "  $(pwd)"
		echo "  $(cd .. && pwd)"
		echo "  name: Godot_v${want:-4}.x-stable_linux.x86_64 (as it comes in the zip), or godot / godot.x86_64"
		echo "  or set GODOT=/path/to/godot"
		for d in "${dirs[@]}"; do for f in "$d"/*[gG]odot*; do [ -f "$f" ] && [[ $f != *.godot ]] && near+=("$(realpath "$f")"); done; done
		if [ ${#near[@]} -gt 0 ]; then
			echo "found these, but their names don't match:"
			printf '  %s\n' "${near[@]}"
		fi
	} >&2
	return 1
}

# ---------------------------------------------------------------- settings

load_settings() {
	S_PORT=24565; S_NAME=Server; S_MAX=8; S_IDLE=5; S_VLAN=no
	local k v
	[ -f "$SETTINGS" ] || return 0
	while IFS='=' read -r k v; do
		case "$k" in
		port) [[ $v =~ ^[0-9]+$ ]] && S_PORT=$v ;;
		name) [ -n "$v" ] && S_NAME=$v ;;
		max_players) [[ $v =~ ^[2-8]$ ]] && S_MAX=$v ;;
		idle_kick) [[ $v =~ ^[0-9]+([.][0-9]+)?$ ]] && S_IDLE=$v ;;
		vlan) [[ $v =~ ^(yes|no)$ ]] && S_VLAN=$v ;;
		esac
	done <"$SETTINGS"
}
save_settings() {
	printf 'port=%s\nname=%s\nmax_players=%s\nidle_kick=%s\nvlan=%s\n' "$S_PORT" "$S_NAME" "$S_MAX" "$S_IDLE" "$S_VLAN" >"$SETTINGS"
}
settings_line() {
	local idle="idle kick $S_IDLE min"; [ "$S_IDLE" = 0 ] && idle="no idle kick"
	echo "port $S_PORT, name \"$S_NAME\", up to $S_MAX players, $idle, virtual LAN $([ "$S_VLAN" = yes ] && echo on || echo off)"
}
server_args() {
	ARGS=(--port "$S_PORT" --name "$S_NAME" --max-players "$S_MAX" --idle-kick "$S_IDLE")
	[ "$S_VLAN" = yes ] && ARGS+=(--vlan)
	return 0
}

# ---------------------------------------------------------------- the running server

# control file: key=value lines written by the server (pid, control_port, token, port, started, name)
control_get() { sed -n "s/^$1=//p" "$CONTROL" 2>/dev/null | head -n 1; }
server_pid() {
	local pid
	pid=$(control_get pid)
	if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && grep -qa -- "--server" "/proc/$pid/cmdline" 2>/dev/null; then echo "$pid"; return 0; fi
	rm -f "$CONTROL"   # left by a server that was killed
	return 1
}
running() { server_pid >/dev/null; }

# One command to the running server; prints its answer (without the echoed "> command" line).
request() {
	local port token
	port=$(control_get control_port); token=$(control_get token)
	[ -n "$port" ] || { echo "the server isn't running"; return 1; }
	exec 3<>"/dev/tcp/127.0.0.1/$port" 2>/dev/null || { echo "the server doesn't answer (port $port)"; return 1; }
	printf 'TOKEN %s\n%s\n' "$token" "$*" >&3
	timeout 120 cat <&3 | sed '1{/^> /d}'
	exec 3<&- 3>&-
}

# info -> I_ROOM I_PLAYERS I_ACTIVE I_UP I_PORT I_MAX I_IDLE I_VLAN I_NAME ("" when not running)
read_info() {
	local line kv
	I_ROOM=""; I_PLAYERS=""; I_ACTIVE=""; I_UP=0; I_PORT=""; I_MAX=""; I_IDLE=""; I_VLAN="-"; I_NAME=""
	line=$(request info 2>/dev/null | grep '^INFO ' | head -n 1) || true
	[ -n "$line" ] || return 1
	I_NAME=${line#* name=}
	for kv in ${line% name=*}; do
		case "$kv" in
		room=*) I_ROOM=${kv#*=} ;; players=*) I_PLAYERS=${kv#*=} ;; active=*) I_ACTIVE=${kv#*=} ;;
		up=*) I_UP=${kv#*=} ;; port=*) I_PORT=${kv#*=} ;; max=*) I_MAX=${kv#*=} ;;
		idle_kick=*) I_IDLE=${kv#*=} ;; vlan=*) I_VLAN=${kv#*=} ;;
		esac
	done
}
duration() { local s=$1; if [ "$s" -ge 3600 ]; then echo "$((s / 3600))h $((s % 3600 / 60))m"; elif [ "$s" -ge 60 ]; then echo "$((s / 60))m"; else echo "${s}s"; fi; }
room_name() {
	case "$1" in
	room_H00) echo "home base" ;; "") echo "starting" ;; *) echo "${1#room_}" ;;
	esac
}

# One line: running or not, with room and players.
state_line() {
	local pid
	if ! pid=$(server_pid); then echo "stopped"; return; fi
	if read_info; then
		echo "RUNNING for $(duration "$I_UP") (pid $pid) - $(room_name "$I_ROOM"), $I_PLAYERS of $I_MAX player(s), port $I_PORT$([ "$I_VLAN" != - ] && echo ", VLAN $I_VLAN")"
	else
		echo "RUNNING (pid $pid), starting up or busy"
	fi
}

# ---------------------------------------------------------------- commands

start() {
	local extra=("$@") pid waited=0
	if pid=$(server_pid); then echo "already running (pid $pid). Stop it first, or restart."; return 0; fi
	find_godot || return 1
	load_settings; server_args
	ARGS+=("${extra[@]+"${extra[@]}"}")
	if [[ " ${ARGS[*]} " == *" --vlan "* ]]; then
		echo "virtual LAN first (tools/vlan/vlan_auto.sh host):"
		tools/vlan/vlan_auto.sh host </dev/null || { echo "the virtual LAN didn't come up (see above); fix it, or turn it off in settings" >&2; return 1; }
		echo
	fi
	if [ ! -d .godot/imported ]; then
		echo "first start, importing the project..."
		"$GODOT" --headless --path . --import >/dev/null 2>&1
	fi
	[ -f "$LOG" ] && mv -f "$LOG" "$LOG.1"
	rm -f "$CONTROL"
	setsid nohup "$GODOT" --headless --path . -- --server --control "$CONTROL" "${ARGS[@]}" >"$LOG" 2>&1 </dev/null &
	echo "starting the server ($(printf '%s ' "${ARGS[@]}"))"
	while [ $waited -lt 120 ]; do
		if grep -q "hosting on port .* - OK" "$LOG" 2>/dev/null && [ -s "$CONTROL" ]; then
			echo "server is up. Players join at:"
			grep "join .* at" "$LOG" | sed 's/^DedicatedServer \[INFO\]: /  /'
			return 0
		fi
		if grep -q "hosting on port .* - " "$LOG" 2>/dev/null && ! grep -q "hosting on port .* - OK" "$LOG"; then
			echo "the server couldn't open its port:"; grep "hosting on port" "$LOG"; stop_now; return 1
		fi
		if [ $waited -gt 4 ] && ! running && ! pgrep -f -- "--control $CONTROL" >/dev/null; then
			echo "the server quit while starting. The end of its log:"; tail -n 20 "$LOG"; return 1
		fi
		sleep 0.5; waited=$((waited + 1))
	done
	echo "the server is slow to start; check: $SELF log"
}

stop_now() {
	local pid
	pid=$(control_get pid); [ -n "$pid" ] || pid=$(pgrep -f -- "--control $CONTROL" | head -n 1)
	[ -n "$pid" ] && kill "$pid" 2>/dev/null
	rm -f "$CONTROL"
}

stop() {
	local pid n=0
	if ! pid=$(server_pid); then echo "the server isn't running."; return 0; fi
	echo "stopping the server (the run is saved, players are told)..."
	request stop >/dev/null
	while kill -0 "$pid" 2>/dev/null && [ $n -lt 30 ]; do sleep 0.5; n=$((n + 1)); done
	if kill -0 "$pid" 2>/dev/null; then
		echo "it didn't stop in 15 s; ending it (the run keeps its last checkpoint)"
		kill "$pid" 2>/dev/null; sleep 1; kill -9 "$pid" 2>/dev/null
	fi
	rm -f "$CONTROL"
	echo "stopped."
}

status() {
	local pid
	load_settings
	echo "server   : $(state_line)"
	if pid=$(server_pid) && read_info; then
		echo "name     : $I_NAME"
		echo "players  : $I_PLAYERS connected, $I_ACTIVE active"
		echo "idle kick: $([ "${I_IDLE%.0}" = 0 ] && echo off || echo "${I_IDLE%.0} min (ghosts 3x)")"
	fi
	echo "settings : $(settings_line)"
	echo "log      : $LOG"
}

players() {
	running || { echo "the server isn't running."; return 0; }
	request players
}

follow_log() {
	[ -f "$LOG" ] || { echo "no log yet (start the server first)"; return 0; }
	echo "== $LOG (Ctrl+C goes back) =="
	trap ':' INT
	tail -n 40 -F "$LOG" 2>/dev/null
	trap - INT
	echo
}

console() {
	local line
	running || { echo "the server isn't running."; return 0; }
	echo "server console: type a command (help lists them), Enter on an empty line goes back."
	while read -r -e -p "server> " line; do
		[ -n "$line" ] || break
		[[ $line =~ ^(back|q)$ ]] && break
		request "$line"
		running || { echo "(the server has stopped)"; break; }
	done
}

ask() {   # prompt default -> REPLY (the default on Enter)
	read -r -e -p "$1 [$2]: " REPLY || REPLY=""
	[ -n "$REPLY" ] || REPLY=$2
}

settings() {
	local c
	load_settings
	while :; do
		echo
		echo "== settings (used on the next start) =="
		echo "  1  port          $S_PORT"
		echo "  2  name          $S_NAME"
		echo "  3  max players   $S_MAX"
		echo "  4  idle kick     $([ "$S_IDLE" = 0 ] && echo off || echo "$S_IDLE min")"
		echo "  5  virtual LAN   $([ "$S_VLAN" = yes ] && echo "on (hosts zs-vlan, see tools/vlan/README.md)" || echo off)"
		echo "  b  back"
		read -r -p "change: " c || break
		case "$c" in
		1) ask "port (1024-65535)" "$S_PORT"; [[ $REPLY =~ ^[0-9]+$ ]] && [ "$REPLY" -ge 1024 ] && [ "$REPLY" -le 65535 ] && S_PORT=$REPLY || echo "not a port" ;;
		2) ask "server name" "$S_NAME"; S_NAME=$(printf '%s' "$REPLY" | tr -d '[:cntrl:]' | cut -c1-24) ;;
		3) ask "max players (2-8)" "$S_MAX"; [[ $REPLY =~ ^[2-8]$ ]] && S_MAX=$REPLY || echo "2 to 8" ;;
		4) ask "idle kick minutes (0 = off)" "$S_IDLE"; [[ $REPLY =~ ^[0-9]+([.][0-9]+)?$ ]] && S_IDLE=$REPLY || echo "a number of minutes" ;;
		5) if [ "$S_VLAN" = yes ]; then S_VLAN=no; else S_VLAN=yes; fi ;;
		b|B|q|"") break ;;
		*) echo "pick 1-5 or b" ;;
		esac
		save_settings
	done
	running && echo "the server is running: restart it to use the new settings."
	return 0
}

menu() {
	local c
	while :; do
		load_settings
		echo
		echo "== Zombie Shooter dedicated server =="
		echo "  server   : $(state_line)"
		echo "  settings : $(settings_line)"
		echo
		if running; then
			echo "  1  stop          2  restart"
		else
			echo "  1  start"
		fi
		echo "  3  status        4  players       5  follow the log"
		echo "  6  console       7  settings$([ "$S_VLAN" = yes ] && echo "      8  VLAN guests + invite")"
		echo "  q  quit this menu (the server keeps running)"
		read -r -p "choose: " c || { echo; break; }
		echo
		case "$c" in
		1) if running; then stop; else start; fi ;;
		2) running && { stop; start; } || echo "not running (1 starts it)" ;;
		3) status ;;
		4) players ;;
		5) follow_log ;;
		6) console ;;
		7) settings ;;
		8) running && request guests || echo "the server isn't running." ;;
		q|Q) break ;;
		"") ;;
		*) echo "pick one of the numbers, or q" ;;
		esac
	done
}

# the old way: the server in this window, typing into it
run_here() {
	local a
	find_godot || exit 1
	for a in "$@"; do
		if [ "$a" = --vlan ]; then
			tools/vlan/vlan_auto.sh host </dev/null || { echo "server.sh: the virtual LAN didn't come up (see above); fix it or start without --vlan" >&2; exit 1; }
			echo
		fi
	done
	if [ ! -d .godot/imported ]; then
		echo "server.sh: first start, importing the project..."
		"$GODOT" --headless --path . --import >/dev/null 2>&1
	fi
	exec "$GODOT" --headless --path . -- --server "$@"
}

case "${1:-}" in
"") if [ -t 0 ]; then menu; else status; fi ;;
menu) menu ;;
start) shift; start "$@" ;;
stop) stop ;;
restart) stop; shift; start "$@" ;;
status) status ;;
players) players ;;
log) follow_log ;;
console) console ;;
send) shift; [ $# -gt 0 ] || { echo "usage: $SELF send <command>"; exit 1; }; running || { echo "the server isn't running."; exit 3; }; request "$@" ;;
settings) settings ;;
-h|--help|help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' ;;
run) shift; run_here "$@" ;;
--*) run_here "$@" ;;
*) echo "unknown command '$1' (try: $SELF help)" >&2; exit 1 ;;
esac
