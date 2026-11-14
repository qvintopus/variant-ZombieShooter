# Shared by the vlan_*.sh scripts (sourced, not run). See README.md.
# Direct WireGuard tunnel via NetworkManager, no servers: both sides know each other's public address
# and send at the same time (keepalive), so each router/firewall lets the other's packets back in.
# Names, subnet and ports come from lan_party.cfg (lp_config.sh).

. "$(dirname "${BASH_SOURCE[0]}")/lp_config.sh"
NAME=$LP_VLAN_NAME           # NM connection + interface name (and the tunnel name on Windows)
NET=$LP_VLAN_NET             # host is .1, guests pick .2-.254 (at most 7)
PORT=${VLAN_PORT:-$LP_VLAN_PORT}  # WireGuard UDP port, same on every machine
GAME_PORT=$LP_GAME_PORT
BRAND=$LP_PREFIX-vlan        # what people see it called; also the ufw comment
STATE_HOST=$LP_STATE_BASE/$LP_PREFIX-vlan
STATE_GUEST=$LP_STATE_BASE/$LP_PREFIX-vlan-guest
CI=${LP_CODE_PREFIX}i        # invite codes: ${CI}2.<base64>
CR=${LP_CODE_PREFIX}r        # reply codes:  ${CR}2.<base64>
# Over the tunnel only the game is let in (ping is allowed by ufw's defaults).
GAME_RULE="in on $NAME to any port $GAME_PORT proto udp"
MACHINE=${MACHINE:-0}        # 1: no prompts, no clipboard, sudo never asks; a LANPARTY line ends the output
# How to get root for ufw. The game sets LANPARTY_SUDO=pkexec (a desktop password prompt); a --machine run
# without it uses "sudo -n" (never asks).
LANPARTY_SUDO=${LANPARTY_SUDO:-}
IDLE_MIN=${VLAN_IDLE_MIN:-5} # the tunnel goes down after this many minutes without game traffic (0 = never)
IDLE_BYTES=2048              # less traffic than this in a 30 s check counts as idle (a game sends far more)
IDLE_CHECK=${VLAN_IDLE_CHECK:-30}  # seconds between watchdog checks
NAME_FILE=$LP_STATE_BASE/$LP_PREFIX-vlan-name   # this PC's name on the VLAN (the game reads it too)
NAME_MAX=24                  # = LanPartyConfig.MAX_NAME_LENGTH in the game
VLAN_AUTO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vlan_auto.sh"

# Exit codes (stable, the game and the dedicated server read them):
#   0 ok, 1 usage or broken code, 2 something this PC needs is missing, 3 wrong state (not set up / other role), 4 timed out
#   (5 is the game's own: Windows asked for admin rights and they were declined)
fail() {
	local code=$1; shift
	[ -z "$*" ] || echo "$*" >&2
	[ "$MACHINE" = 1 ] && echo "LANPARTY state=error exit=$code"
	exit "$code"
}
die() { fail 1 "$*"; }

# The one machine-readable line: "LANPARTY key=value ..." (values never contain spaces).
result() { [ "$MACHINE" = 1 ] && echo "LANPARTY $*"; return 0; }

# Copy to the clipboard if a tool for it is there (Wayland, then X11). Silent otherwise.
clip() {
	[ "$MACHINE" = 1 ] && return 0
	if command -v wl-copy >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then printf '%s' "$1" | wl-copy 2>/dev/null
	elif command -v xclip >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then printf '%s' "$1" | xclip -selection clipboard 2>/dev/null
	elif command -v xsel >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then printf '%s' "$1" | xsel -b 2>/dev/null
	else return 0; fi && echo "   (copied to the clipboard)"
	return 0
}

# Install hint for a package, by distro family.  args: arch-name debian-name fedora-name
pkg_hint() {
	local os
	os=$(. /etc/os-release 2>/dev/null; echo "${ID:-} ${ID_LIKE:-}")
	case "$os" in
	*arch*) echo "sudo pacman -S $1" ;;
	*debian*|*ubuntu*) echo "sudo apt install $2" ;;
	*fedora*|*rhel*) echo "sudo dnf install $3" ;;
	*suse*) echo "sudo zypper install $3" ;;
	*) echo "install '$1' with your package manager" ;;
	esac
}

# Everything this PC needs; one line with the fix per problem. Fails with exit 2.
preflight() {
	local bad=0
	command -v nmcli >/dev/null 2>&1 || { echo "problem: NetworkManager (nmcli) not found -> $(pkg_hint networkmanager network-manager NetworkManager)" >&2; bad=1; }
	if [ $bad = 0 ] && ! nmcli -t general status >/dev/null 2>&1; then
		echo "problem: NetworkManager isn't running -> sudo systemctl enable --now NetworkManager" >&2; bad=1
	fi
	if [ ! -d /sys/module/wireguard ] && ! modprobe -n -q wireguard 2>/dev/null; then
		echo "problem: this kernel has no WireGuard (needs Linux 5.6 or newer) -> update the kernel and reboot" >&2; bad=1
	fi
	command -v openssl >/dev/null 2>&1 || { echo "problem: openssl not found -> $(pkg_hint openssl openssl openssl)" >&2; bad=1; }
	command -v curl >/dev/null 2>&1 || { echo "problem: curl not found -> $(pkg_hint curl curl curl)" >&2; bad=1; }
	command -v ip >/dev/null 2>&1 || { echo "problem: ip not found -> $(pkg_hint iproute2 iproute2 iproute)" >&2; bad=1; }
	command -v ping >/dev/null 2>&1 || { echo "problem: ping not found -> $(pkg_hint iputils iputils-ping iputils)" >&2; bad=1; }
	command -v flock >/dev/null 2>&1 || { echo "problem: flock not found -> $(pkg_hint util-linux util-linux util-linux)" >&2; bad=1; }
	[ $bad = 0 ] || fail 2 "fix the problems above, then run this again."
}

# Warn when the public addresses make a direct tunnel unlikely.  args: v6 v4
addr_warn() {
	if [ "$1" = - ] && [ "$2" = - ]; then
		echo "warning   : no public IPv6 and no public IPv4 found - check the internet connection"
	elif [ "$1" = - ]; then
		echo "note      : no public IPv6 here; the IPv4 fallback fails behind CGNAT or a port-changing router"
		echo "            (check both PCs at https://test-ipv6.com - IPv6 on both sides almost always works)"
	fi
}

# X25519 keys with openssl (no wireguard-tools needed): raw 32 bytes, base64.
b64key() { tail -c 32 | base64; }
genpriv() { openssl genpkey -algorithm X25519 -outform DER | b64key; }
pubkey() { base64 -d <<<"$1" | cat <(printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x6e\x04\x22\x04\x20') - \
	| openssl pkey -inform DER -pubout -outform DER | b64key; }

# Public IPv6 = the source address the kernel uses toward the internet (no external lookup). "-" if none.
my_v6() {
	local a
	a=$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | sed -n 's/.* src \([0-9a-f:]*\).*/\1/p')
	[[ -n $a && $a != fe80* && $a != fc* && $a != fd* ]] && echo "$a" || echo -
}
# Public IPv4 (fallback only): VLAN_IPV4=addr sets it, VLAN_IPV4=none skips; else one lookup at api.ipify.org.
my_v4() {
	local a
	if [ -n "${VLAN_IPV4:-}" ]; then [ "$VLAN_IPV4" = none ] && echo - || echo "$VLAN_IPV4"; return; fi
	a=$(curl -s4 --max-time 4 https://api.ipify.org 2>/dev/null || true)
	[[ $a =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$a" || echo -
}

# Invite/reply lines: "<prefix>.<base64 of space-separated fields>" - only public keys, addresses and a
# name, safe for chat. Version 2 (<p>i2/<p>r2) adds the sender's name as the last field (it may hold
# spaces); version 1 codes (no name) are still read. Made with: enc ${CI}2 "fields".
enc() { printf '%s.%s' "$1" "$(printf '%s' "$2" | base64 -w0)"; }
# dec reports a bad code on stderr and returns 1 (callers: fields=$(dec ...) || fail 1).  args: $CI|$CR code
dec() {
	[[ $2 =~ ^$1[12]\. ]] || { echo "not a ${1}2 code: $2" >&2; return 1; }
	base64 -d <<<"${2#*.}" 2>/dev/null || { echo "broken ${1}2 code (copy the whole line)" >&2; return 1; }
}

# ---- names: optional, default the computer name; the same name twice becomes Name#2, Name#3, ...
# Printable, single spaces, at most NAME_MAX characters ("" when nothing is left).
clean_name() {
	local LC_ALL=C.UTF-8 s
	s=$(printf '%s' "$1" | tr -d '[:cntrl:]' | tr -s ' ')
	s=${s#"${s%%[! ]*}"}; s=${s:0:$NAME_MAX}; s=${s%"${s##*[! ]}"}
	printf '%s' "$s"
}
# The computer name; a distro's stock one (archlinux, ubuntu, ...) gets the login name in front.
default_name() {
	local LC_ALL=C.UTF-8 h
	h=$(hostnamectl hostname 2>/dev/null || true)
	[ -n "$h" ] || h=$(cat /etc/hostname 2>/dev/null || uname -n 2>/dev/null || true)
	h=$(clean_name "$h")
	case "${h,,}" in
	""|localhost*|arch|archlinux|ubuntu|debian|fedora|linux|raspberrypi|manjaro|mint|linuxmint|pop-os|kali|nixos|endeavouros|garuda|cachyos|omarchy|opensuse|steamdeck)
		h=$(clean_name "${USER:-player}-${h:-pc}") ;;
	esac
	printf '%s' "$h"
}
my_name() {
	local n
	n=$(clean_name "$(cat "$NAME_FILE" 2>/dev/null || true)")
	[ -n "$n" ] || n=$(default_name)
	printf '%s' "$n"
}
save_name() {
	local n
	n=$(clean_name "$1"); [ -n "$n" ] || n=$(default_name)
	mkdir -p "${NAME_FILE%/*}"; printf '%s\n' "$n" >"$NAME_FILE"
}
# Ask for this PC's name, showing the current one (or the computer name) as the suggestion.
# --name NAME sets it without asking; with no terminal (or --machine) the current one is kept.  arg: who sees it
ask_name() {
	local cur line
	if [ -n "${SET_NAME:-}" ]; then save_name "$SET_NAME"; return 0; fi
	cur=$(my_name)
	if [ "$MACHINE" = 1 ] || [ ! -t 0 ]; then save_name "$cur"; return 0; fi
	echo "your name on the virtual LAN - $1."
	echo "suggested: $cur   (type another name to change it)"
	read -r -p "name [Enter keeps \"$cur\"]: " line || line=""
	save_name "${line:-$cur}"
	echo "you are \"$(my_name)\""; echo
}
# name, unless one of the taken names already is it (any case): then Name#2, Name#3, ...
# A name ending in #N counts from its base (Player#2 taken -> Player#3).  args: name taken...
unique_name() {
	local LC_ALL=C.UTF-8 name=$1 base c n; shift
	name_taken "$name" "$@" || { printf '%s' "$name"; return; }
	base=$name; [[ $base =~ ^(.+)#[0-9]+$ ]] && base=${BASH_REMATCH[1]}
	for ((n = 2; ; n++)); do
		c=${base:0:$((NAME_MAX - ${#n} - 1))}; c="${c%"${c##*[! ]}"}#$n"
		name_taken "$c" "$@" || { printf '%s' "$c"; return; }
	done
}
name_taken() { local LC_ALL=C.UTF-8 want=${1,,} x; shift; for x in "$@"; do [ "${x,,}" = "$want" ] && return 0; done; return 1; }
# A name as a LANPARTY value (values never hold spaces): % and space escaped.
pct() { local s=${1//%/%25}; printf '%s' "${s// /%20}"; }

# Endpoint for a peer: IPv6 when both sides have it, else the peer's IPv4.  args: peer_v6 peer_v4 peer_port my_v6
pick_ep() {
	if [ "$1" != - ] && [ "$4" != - ]; then echo "[$1]:$3"
	elif [ "$2" != - ]; then echo "$2:$3"
	else return 1; fi
}

conn_exists() { command -v nmcli >/dev/null 2>&1 && nmcli -g NAME connection show | grep -qx "$NAME"; }
dev_state() { nmcli -g GENERAL.STATE device show "$NAME" 2>/dev/null || echo down; }

# Replace the NM connection with the WireGuard config on stdin.
nm_apply() {
	local tmp="$STATE/$NAME.conf"   # NM names the connection after the file
	(umask 077; cat >"$tmp")
	if conn_exists; then nmcli connection delete "$NAME" >/dev/null; fi
	nmcli connection import type wireguard file "$tmp" >/dev/null || { rm -f "$tmp"; fail 2 "nmcli import failed (does this NetworkManager have WireGuard? needs 1.16+)"; }
	rm -f "$tmp"   # private key now only in NM's root-only store (and $STATE/*.key)
	nmcli connection modify "$NAME" ipv6.method disabled
	tunnel_up
}

# Bring the tunnel up (never at boot: a restart leaves it off until vlan_auto runs again) and start
# the idle watchdog. autoconnect is cleared here too, for connections made by older versions.
tunnel_up() {
	nmcli connection modify "$NAME" connection.autoconnect no
	nmcli connection up "$NAME" >/dev/null
	watch_start
}
tunnel_on() { [ -d "/sys/class/net/$NAME" ]; }

# Public addresses now vs. the ones the codes were made with ($STATE/public: "v6 v4").
# Sets V6 V4 (current) and PUB_OLD (the saved ones when they differ, else empty), then saves the current.
# pub_compare only compares; pub_check also saves the current ones (when the tunnel is started).
pub_compare() {
	local saved
	V6=$(my_v6); V4=$(my_v4); PUB_OLD=""
	saved=$(cat "$STATE/public" 2>/dev/null || true)
	if [ -n "$saved" ] && [ "$saved" != "$V6 $V4" ]; then PUB_OLD=$saved; fi
}
pub_check() { pub_compare; echo "$V6 $V4" >"$STATE/public"; }

# ---- idle watchdog: "vlan_auto.sh watch" runs detached while the tunnel is up (see vlan_auto.sh)
watch_running() { [ -e "$STATE/watch.lock" ] && ! flock -n "$STATE/watch.lock" true 2>/dev/null; }
watch_start() {
	[[ $IDLE_MIN =~ ^[0-9]+$ ]] && [ "$IDLE_MIN" -gt 0 ] || return 0
	rm -f "$STATE/idle_down"
	watch_running && return 0
	# a user unit survives the terminal closing; plain setsid where there's no systemd user session
	systemd-run --user --quiet --collect --unit "$NAME-idle" ${XDG_STATE_HOME:+--setenv=XDG_STATE_HOME} bash "$VLAN_AUTO" watch "$IDLE_MIN" >/dev/null 2>&1 \
		|| { setsid nohup bash "$VLAN_AUTO" watch "$IDLE_MIN" >/dev/null 2>&1 </dev/null & }
	return 0
}
watch_stop() {
	local p
	p=$(cat "$STATE/watch.pid" 2>/dev/null || true)
	[ -n "$p" ] && grep -qa vlan_auto "/proc/$p/cmdline" 2>/dev/null && kill "$p" 2>/dev/null
	return 0
}
# Bytes through the tunnel so far (inner packets: keepalives don't count), -1 when it's down.
traffic() {
	local d=/sys/class/net/$NAME/statistics
	[ -r "$d/rx_bytes" ] || { echo -1; return; }
	echo $(( $(cat "$d/rx_bytes") + $(cat "$d/tx_bytes") ))
}
# A game or dedicated server listens on this PC: its friends can come any time, so that isn't idle.
hosting_game() { ss -Hlun "sport = :$GAME_PORT" 2>/dev/null | grep -q .; }

# A ufw rule is already there.  arg: rule as given to "ufw allow"
fw_has() {
	if [[ $1 == "in on "*" to any port "* ]]; then
		local on=${1#in on }; on=${on%% *}
		local p=${1#* port }; p=${p%% *}
		grep -q "^$p/udp on $on " <<<"$2"
	elif [[ $1 == "in on "* ]]; then grep -q "^Anywhere on ${1#in on } " <<<"$2"
	else grep -q "^$1 " <<<"$2"; fi
}

# Open ufw rules (sudo) if ufw is active; remember which ones we added so teardown removes only those.
# One root call for all of them, so pkexec asks once.
fw_open() {
	local added
	if ! systemctl is-active -q ufw 2>/dev/null; then echo "ufw inactive, nothing changed" >"$STATE/firewall"; return; fi
	echo "ufw is active: root needed to allow: $*"
	# prints each rule it added; exit 1: no root
	# shellcheck disable=SC2016
	added=$(as_root bash -c "$(declare -f fw_has)"'
		st=$(ufw status) || exit 1
		for r in "$@"; do
			fw_has "$r" "$st" && continue
			ufw allow $r comment "$BRAND" >/dev/null && echo "$r"
		done' bash "$@") || { echo "no root (sudo/pkexec failed), ufw untouched - peers may be blocked (rerun vlan_auto.sh in a terminal)" | tee "$STATE/firewall"; return; }
	[ -z "$added" ] || echo "$added" >>"$STATE/ufw_rules"
	if [ -s "$STATE/ufw_rules" ]; then echo "ufw rules added: $(paste -sd, "$STATE/ufw_rules")" >"$STATE/firewall"
	else echo "ufw already allowed it, nothing changed" >"$STATE/firewall"; fi
}

# Run a command as root for ufw: LANPARTY_SUDO (the game: pkexec), else sudo (sudo -n with --machine: never asks).
as_root() {
	if [ -n "$LANPARTY_SUDO" ]; then $LANPARTY_SUDO "$@"
	elif [ "$MACHINE" = 1 ]; then sudo -n "$@"
	else sudo "$@"; fi
}

# Undo everything for one role: NM connection, ufw rules we added, keys/state.
teardown() {
	watch_stop
	if conn_exists; then nmcli connection delete "$NAME" >/dev/null && echo "removed NM connection $NAME"; else echo "no NM connection $NAME"; fi
	if [ -s "$STATE/ufw_rules" ]; then
		echo "removing ufw rules (root)"
		# shellcheck disable=SC2016
		as_root bash -c 'while IFS= read -r r; do
			ufw delete allow $r >/dev/null && echo "  removed ufw: $r" || echo "  FAILED ufw: $r (fix by hand: sudo ufw status numbered)"
		done' <"$STATE/ufw_rules" || echo "  no root (sudo/pkexec failed): the $BRAND ufw rules are still there (sudo ufw status numbered)"
	fi
	if [ -d "$STATE" ]; then rm -rf "$STATE" && echo "removed $STATE"; fi
}

ping_st() { ping -c1 -W1 "$1" >/dev/null 2>&1 && echo "online" || echo "no reply"; }

# Wait until an address answers ping.  args: ip seconds   (prints dots; 0 = answered)
wait_online() {
	local left=$2
	while [ "$left" -gt 0 ]; do
		ping -c1 -W1 "$1" >/dev/null 2>&1 && { [ "$MACHINE" = 1 ] || echo; return 0; }
		[ "$MACHINE" = 1 ] || printf '.'
		sleep 1; left=$((left - 2))
	done
	[ "$MACHINE" = 1 ] || echo
	return 1
}
