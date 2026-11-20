#!/usr/bin/env bash
# zs-vlan, guided, Linux (NetworkManager). Windows: vlan_auto.cmd. See README.md.
#   vlan_auto.sh                     guided: host or join (or continue / switch / stop what this PC has), then each next step
#   vlan_auto.sh <code>              paste whatever you got: an invite (zsi2.) joins, a reply (zsr2.) adds that guest
#   vlan_auto.sh host                create the virtual LAN (or show it) + the invite (one for all guests)
#   vlan_auto.sh host add <reply>    add a guest from the reply they sent back
#   vlan_auto.sh host remove <N>     remove guest 10.77.0.N
#   vlan_auto.sh join <invite>       join a host's virtual LAN; prints the reply to send back
#   vlan_auto.sh newaddress          guest: pick another address (when the host says yours is taken)
#   vlan_auto.sh start               start the last virtual LAN again (after a restart or going idle)
#   vlan_auto.sh name [NEW]          this PC's name on the virtual LAN (default: the computer name)
#   vlan_auto.sh status              what this PC is, who is online, the code to send
#   vlan_auto.sh off                 take the tunnel down, keep everything (start brings it back)
#   vlan_auto.sh stop                remove everything this made (host or guest)
# --name NAME anywhere: use that name without asking (host and join ask for one on a terminal).
# The same name twice on one virtual LAN becomes Name#2, Name#3, ...
# --machine anywhere: no prompts, no clipboard, short waits, and a last line "ZSVLAN key=value ..."
# (exit codes in lib.sh). The dedicated server console and the game's Co-op dialog use it.
# The tunnel never starts at boot, and goes off after VLAN_IDLE_MIN (5) minutes without game traffic.
# Starting it again checks the public address: unchanged, the old codes still work; changed, it says
# which new code to send.
set -euo pipefail
MACHINE=0
ARGS=()
SET_NAME=""
while [ $# -gt 0 ]; do
	case "$1" in
	--machine) MACHINE=1 ;;
	--name) SET_NAME=${2:-}; shift ;;
	--name=*) SET_NAME=${1#--name=} ;;
	*) ARGS+=("$1") ;;
	esac
	shift || true
done
set -- "${ARGS[@]+"${ARGS[@]}"}"
. "$(dirname "$0")/lib.sh"
SELF="tools/vlan/vlan_auto.sh"

role() {
	if [ -d "$STATE_HOST" ]; then echo host
	elif [ -d "$STATE_GUEST" ]; then echo guest
	else echo none; fi
}

# ---------------------------------------------------------------- host

host_conf() {
	local f pub ep
	printf '[Interface]\nPrivateKey = %s\nAddress = %s.1/24\nListenPort = %s\n' "$(cat "$STATE/host.key")" "$NET" "$PORT"
	for f in "$STATE"/peers/*; do
		[ -e "$f" ] || continue
		read -r pub ep _ <"$f"
		printf '\n[Peer]\nPublicKey = %s\nAllowedIPs = %s.%s/32\nEndpoint = %s\nPersistentKeepalive = 25\n' "$pub" "$NET" "${f##*/}" "$ep"
	done
}

# Guests pick their own address (10.77.0.2-254) from the one shared invite; at most MAX_GUESTS of them.
MAX_GUESTS=7
guest_count() { local f n=0; for f in "$STATE"/peers/*; do [ -e "$f" ] && n=$((n + 1)); done; echo $n; }

host_up() {
	[ "$(role)" = guest ] && fail 3 "this PC has joined someone else's virtual LAN; to host instead run: $SELF stop"
	STATE=$STATE_HOST
	if [ -f "$STATE/host.key" ] && conn_exists; then
		pub_check
		if tunnel_on; then watch_start; return; fi
		tunnel_up
		echo "started the virtual LAN again (same keys and guests) - this PC is $NET.1"; echo
		return
	fi
	preflight
	conn_exists && fail 3 "a connection named $NAME exists but $STATE is missing; run: $SELF stop   and try again"
	ask_name "guests see it next to $NET.1"
	mkdir -p "$STATE/peers"; chmod 700 "$STATE"
	[ -f "$STATE/host.key" ] || (umask 077; genpriv >"$STATE/host.key")
	pub_check
	conf=$(host_conf); nm_apply <<<"$conf"
	fw_open "$PORT/udp" "$GAME_RULE"
	echo "created the virtual LAN - this PC is $NET.1"; echo
}

# Why the tunnel is off, for status.
off_reason() { cat "$STATE/idle_down" 2>/dev/null || echo "not started since the PC restarted, or taken down"; }

host_show() {
	local v6 v4 f pub ep gname st n=0 list="" code slot hpub moved=no me
	STATE=$STATE_HOST
	me=$(my_name)
	[ -n "${V6:-}" ] || pub_compare
	v6=$V6; v4=$V4
	echo "== zs-vlan: this PC hosts =="
	echo "this PC   : $NET.1  \"$me\"   (interface $NAME: $(dev_state))"
	echo "public    : IPv6 $v6   IPv4 $v4"
	addr_warn "$v6" "$v4"
	echo "firewall  : $(cat "$STATE/firewall" 2>/dev/null || echo "not touched")"
	if ! conn_exists; then
		echo
		echo "the tunnel is gone (removed outside vlan_auto). Recreate it: $SELF host   or clean up: $SELF stop"
		result "role=host state=down ip=$NET.1"
		return
	fi
	if ! tunnel_on; then
		echo
		echo "the virtual LAN is off ($(off_reason))."
		echo "start it again: $SELF   (same keys and guests; each guest starts theirs too)"
		result "role=host state=off ip=$NET.1"
		return
	fi
	hpub=$(pubkey "$(cat "$STATE/host.key")")
	echo "guests    :"
	for f in "$STATE"/peers/*; do
		[ -e "$f" ] || continue
		read -r pub ep gname <"$f"; n=1
		gname=${gname:-guest ${f##*/}}
		st=$(ping_st "$NET.${f##*/}")
		echo "  $NET.${f##*/}  \"$gname\"  via $ep  ($st)"
		list+="${list:+,}${f##*/}:${st// /-}:$(pct "$gname")"
	done
	[ $n = 1 ] || echo "  none yet"
	echo
	# the guests' tunnels point at the old public address: each needs an invite with the new one
	if [ -n "${PUB_OLD:-}" ] && [ $n = 1 ]; then
		moved=yes
		echo "this PC's public address changed (was IPv6 ${PUB_OLD% *}  IPv4 ${PUB_OLD#* }), so guests can't reach it."
		echo "send your guests the invite below again; they paste it into vlan_auto (same address, no new"
		echo "reply needed unless their public address changed too)."
		echo
	fi
	if [ "$(guest_count)" -ge $MAX_GUESTS ]; then
		slot=- code=-
		echo "all $MAX_GUESTS guest places are used ($SELF host remove <N> frees one)"
	else
		slot=open
		code=$(enc zsi2 "$hpub $PORT 0 $v6 $v4 $me")
		echo "1. send this invite to your friends - the same one to everyone (it holds only public info):"
		echo
		echo "$code"
		clip "$code"
		echo
		echo "2. each runs vlan_auto with it and sends you back their own reply code"
		echo "3. you paste each reply as it comes:  $SELF <reply>"
	fi
	echo
	echo "game: host from the Comms Terminal, or run tools/server.sh - friends join  $NET.1"
	result "role=host state=up ip=$NET.1 name=$(pct "$me") game=$NET.1:$GAME_PORT next=${slot} code=$code guests=${list:--} moved=$moved"
}

host_add() {
	local slot gpub gport gv6 gv4 gname ep old other wait=60 fields f taken=() asked name
	[ "$(role)" = host ] || fail 3 "this PC doesn't host a virtual LAN; run: $SELF host   first"
	STATE=$STATE_HOST
	fields=$(dec zsr "$1") || fail 1
	read -r slot gpub gport gv6 gv4 gname <<<"$fields"
	slot_ok "$slot" && [[ ${#gpub} = 44 && $gport =~ ^[0-9]+$ ]] || die "broken reply code (copy the whole line)"
	if [ -e "$STATE/peers/$slot" ]; then
		read -r old _ other <"$STATE/peers/$slot"
		[ "$old" = "$gpub" ] || fail 3 "$NET.$slot is already taken by \"${other:-guest $slot}\". Ask the new guest to run:  vlan_auto newaddress   and send you the reply it prints"
	else
		# the same guest under a new address (it picked another one): it moves
		for f in "$STATE"/peers/*; do
			[ -e "$f" ] || continue
			read -r old _ <"$f"
			if [ "$old" = "$gpub" ]; then rm "$f"; echo "(this guest was $NET.${f##*/} before)"; fi
		done
		[ "$(guest_count)" -lt $MAX_GUESTS ] || fail 3 "all $MAX_GUESTS guest places are used ($SELF host remove <N> frees one)"
	fi
	ep=$(pick_ep "$gv6" "$gv4" "$gport" "$(my_v6)") || fail 3 "the guest sent no address usable from here (no IPv6 on one side and no IPv4 from them)"
	# their name, made unique among this PC and the other guests (an update of the same slot doesn't count)
	asked=$(clean_name "$gname"); [ -n "$asked" ] || asked="guest $slot"
	taken=("$(my_name)")
	for f in "$STATE"/peers/*; do
		[ -e "$f" ] && [ "${f##*/}" != "$slot" ] || continue
		read -r _ _ gname <"$f"; taken+=("${gname:-guest ${f##*/}}")
	done
	name=$(unique_name "$asked" "${taken[@]}")
	mkdir -p "$STATE/peers"
	echo "$gpub $ep $name" >"$STATE/peers/$slot"
	conf=$(host_conf); nm_apply <<<"$conf"
	if [ "$name" = "$asked" ]; then echo "guest $NET.$slot \"$name\" added (via $ep), waiting for it to answer"
	else echo "guest $NET.$slot \"$name\" added (they called themselves \"$asked\", which is taken) (via $ep), waiting for it to answer"; fi
	[ "$MACHINE" = 1 ] && wait=20
	if wait_online "$NET.$slot" "$wait"; then
		echo "guest $NET.$slot is online - they join the game at $NET.1"
		result "role=host state=added slot=$slot name=$(pct "$name") online=yes"
	else
		echo "guest $NET.$slot doesn't answer yet. It connects once their side is up too;"
		echo "check later with: $SELF status   (both PCs need IPv6, or routers that keep UDP ports)"
		result "role=host state=added slot=$slot name=$(pct "$name") online=no"
	fi
}

host_remove() {
	slot_ok "${1:-}" || die "usage: $SELF host remove <N>   (guest 10.77.0.N, see: $SELF status)"
	STATE=$STATE_HOST
	[ -e "$STATE/peers/$1" ] || fail 3 "no guest $NET.$1"
	rm "$STATE/peers/$1"; conf=$(host_conf); nm_apply <<<"$conf"
	echo "guest $NET.$1 removed"
	result "role=host state=removed slot=$1"
}

# Guided host: show, then take replies as they come in.
host_loop() {
	local line
	host_show
	[ -t 0 ] || return 0
	while :; do
		echo
		read -r -p "paste a reply code here when it arrives (Enter = done): " line || break
		line=$(tr -d '[:space:]' <<<"$line")
		[ -n "$line" ] || break
		( host_add "$line" ) || true
		echo; host_show
	done
}

# ---------------------------------------------------------------- guest

guest_conf() {
	local hpub hport slot hv6 hv4 ep
	read -r hpub hport _ hv6 hv4 _ <<<"$(dec zsi "$(cat "$STATE/invite")")"
	slot=$(my_slot)
	ep=$(pick_ep "$hv6" "$hv4" "$hport" "$(my_v6)") || fail 3 "the host has no address usable from here (no IPv6 on one side, and no IPv4 in the invite)"
	printf '[Interface]\nPrivateKey = %s\nAddress = %s.%s/24\nListenPort = %s\n' "$(cat "$STATE/guest.key")" "$NET" "$slot" "$PORT"
	printf '\n[Peer]\nPublicKey = %s\nAllowedIPs = %s.1/32\nEndpoint = %s\nPersistentKeepalive = 25\n' "$hpub" "$NET" "$ep"
}

guest_join() {
	local hpub hport slot hv6 hv4 hname fields
	[ "$(role)" = host ] && fail 3 "this PC hosts a virtual LAN; to join someone instead run: $SELF stop"
	STATE=$STATE_GUEST
	fields=$(dec zsi "$1") || fail 1
	read -r hpub hport slot hv6 hv4 hname <<<"$fields"
	{ [ "$slot" = 0 ] || slot_ok "$slot"; } && [[ ${#hpub} = 44 && $hport =~ ^[0-9]+$ ]] || die "broken invite code (copy the whole line)"
	pick_ep "$hv6" "$hv4" "$hport" "$(my_v6)" >/dev/null || fail 3 "the host has no address usable from here: they have no IPv4 in the invite and this PC has no IPv6"
	preflight
	mkdir -p "$STATE"; chmod 700 "$STATE"
	printf '%s\n' "$1" >"$STATE/invite"
	# an open invite (slot 0): this PC picks its own address, kept with the key for rejoins and new invites
	[ "$slot" != 0 ] || [ -f "$STATE/slot" ] || echo $((RANDOM % 253 + 2)) >"$STATE/slot"
	echo "invite from \"$(clean_name "${hname:-the host}")\" - you'll be $NET.$(my_slot) on their virtual LAN"; echo
	ask_name "the host sees it in their guest list"
	[ -f "$STATE/guest.key" ] || (umask 077; genpriv >"$STATE/guest.key")   # same key on rejoin, so the host's entry stays valid
	pub_check
	conf=$(guest_conf); nm_apply <<<"$conf"
	[ -f "$STATE/firewall" ] || fw_open "$PORT/udp" "$GAME_RULE"   # this PC can host the game for the VLAN host too
	echo "tunnel set up."; echo
}

# Start the joined tunnel again (after a restart or going idle).
guest_up() {
	STATE=$STATE_GUEST
	[ -f "$STATE/invite" ] && conn_exists || return 0   # gone: guest_show says what to do
	pub_check
	if tunnel_on; then watch_start; return; fi
	tunnel_up
	echo "started the tunnel again (same slot and key)"; echo
}

guest_show() {
	local hpub hport slot hv6 hv4 hname v6 v4 reply st fields me
	STATE=$STATE_GUEST
	[ -f "$STATE/invite" ] || fail 3 "not joined yet; run: $SELF <invite code from the host>"
	fields=$(dec zsi "$(cat "$STATE/invite")") || fail 1
	read -r hpub hport _ hv6 hv4 hname <<<"$fields"
	slot=$(my_slot)
	hname=$(clean_name "${hname:-host}"); me=$(my_name)
	[ -n "${V6:-}" ] || pub_compare
	v6=$V6; v4=$V4
	st=$(ping_st "$NET.1")
	echo "== zs-vlan: this PC joined =="
	echo "this PC   : $NET.$slot  \"$me\"   (interface $NAME: $(dev_state))"
	echo "host      : $NET.1  \"$hname\"  via $(pick_ep "$hv6" "$hv4" "$hport" "$v6" || echo "?")  ($st)"
	addr_warn "$v6" "$v4"
	echo "firewall  : $(cat "$STATE/firewall" 2>/dev/null || echo "not touched")"
	echo
	if ! conn_exists; then
		echo "the tunnel is gone (removed outside vlan_auto). Join again with the invite: $SELF <invite>"
		echo "or clean up with: $SELF stop"
		result "role=guest state=down ip=$NET.$slot"
		return
	fi
	if ! tunnel_on; then
		echo "the tunnel is off ($(off_reason))."
		echo "start it again: $SELF   (once the host has started theirs)"
		result "role=guest state=off ip=$NET.$slot"
		return
	fi
	reply=$(enc zsr2 "$slot $(pubkey "$(cat "$STATE/guest.key")") $PORT $v6 $v4 $me")
	if [ "$st" = online ]; then
		echo "connected. In the game: Comms Terminal -> Join ->  $NET.1"
		clip "$NET.1"
		echo "   (the host's game must be running: Comms Terminal -> Host, or the dedicated server."
		echo "    The tunnel works but the game can't join? A Windows host runs:  vlan_auto.cmd firewall)"
	else
		[ -z "${PUB_OLD:-}" ] || echo "this PC's public address changed since your last reply, so the host needs the new one."
		echo "1. send this reply back to the host:"
		echo
		echo "$reply"
		clip "$reply"
		echo
		echo "2. the host pastes it into vlan_auto (or the dedicated server console)"
		echo "3. once connected, join in the game at  $NET.1"
	fi
	result "role=guest state=up ip=$NET.$slot name=$(pct "$me") host_name=$(pct "$hname") game=$NET.1:$GAME_PORT host=${st// /-} code=$reply"
}

guest_wait() {
	[ "$MACHINE" = 1 ] && return 0
	tunnel_on || return 0
	[ "$(ping_st "$NET.1")" = online ] && return 0
	echo
	echo "waiting for the host to add your reply (up to 2 min; Ctrl+C stops waiting, the tunnel stays)"
	if wait_online "$NET.1" 120; then
		echo
		echo "online! In the game: Comms Terminal -> Join ->  $NET.1"
		clip "$NET.1"
		echo "   (the host's game must be running: Comms Terminal -> Host, or the dedicated server."
		echo "    The tunnel works but the game can't join? A Windows host runs:  vlan_auto.cmd firewall)"
	else
		echo "no answer from the host yet. Check that:"
		echo "  - the host started their virtual LAN and pasted your reply (vlan_auto, or 'add <reply>' on the server console)"
		echo "  - the host's public address didn't change: if it did, their vlan_auto shows a new invite for you"
		echo "  - both PCs have IPv6 (https://test-ipv6.com); without it the IPv4 fallback fails behind CGNAT"
		echo "rerun '$SELF status' any time - it shows when the host answers."
		exit 4
	fi
}

# ---------------------------------------------------------------- common

slot_ok() { [[ ${1:-} =~ ^[0-9]+$ ]] && [ "$1" -ge 2 ] && [ "$1" -le 254 ]; }

# This guest's address: the slot a per-guest invite gave, else the one it picked for an open invite.
my_slot() {
	local s
	s=$(dec zsi "$(cat "$STATE/invite")" | cut -d' ' -f3)
	if [ "$s" = 0 ]; then cat "$STATE/slot" 2>/dev/null || echo 0; else echo "$s"; fi
}

# The host said this address is taken: pick another one and show the new reply.
newaddress() {
	local old s
	[ "$(role)" = guest ] || fail 3 "only a guest picks its address; this PC hasn't joined a virtual LAN"
	STATE=$STATE_GUEST
	old=$(my_slot)
	[ "$(dec zsi "$(cat "$STATE/invite")" | cut -d' ' -f3)" = 0 ] || fail 3 "the host's invite gave this PC $NET.$old; ask the host for a new invite"
	s=$old; while [ "$s" = "$old" ]; do s=$((RANDOM % 253 + 2)); done
	echo "$s" >"$STATE/slot"
	conf=$(guest_conf); nm_apply <<<"$conf"
	echo "this PC is now $NET.$s (was $NET.$old). Send the host the new reply."; echo
	guest_show; guest_wait
}

status() {
	case "$(role)" in
	host) host_show ;;
	guest) guest_show ;;
	*)
		echo "this PC isn't in a virtual LAN."
		echo "  host:  $SELF host"
		echo "  join:  $SELF <invite code from the host>"
		result "role=none state=down" ;;
	esac
}

# Start whichever role this PC has again, without prompts.
start() {
	case "$(role)" in
	host) host_up; host_show ;;
	guest) guest_up; guest_show ;;
	*) fail 3 "nothing to start: this PC isn't in a virtual LAN (host: $SELF host   join: $SELF <invite>)" ;;
	esac
}

# Idle watchdog, run detached by watch_start (one per PC, via the lock). Every 30 s it looks at the
# tunnel's traffic; after <minutes> without a game on it (and no game hosted here) it takes the
# tunnel down. Ends when the tunnel is down or removed.
watch() {
	local min=${1:-$IDLE_MIN} idle=0 off=0 last now
	case "$(role)" in host) STATE=$STATE_HOST ;; guest) STATE=$STATE_GUEST ;; *) return 0 ;; esac
	exec 9>"$STATE/watch.lock"
	flock -n 9 || return 0
	echo $$ >"$STATE/watch.pid"
	last=$(traffic)
	while sleep "$IDLE_CHECK"; do
		{ [ -d "$STATE" ] && conn_exists; } || return 0
		now=$(traffic)
		if [ "$now" -lt 0 ]; then   # down: by hand, or for a moment while a guest is added
			off=$((off + 1)); [ $off -lt 2 ] || return 0; continue
		fi
		off=0
		if [ "$last" -lt 0 ] || [ $((now - last)) -lt 0 ] || [ $((now - last)) -ge "$IDLE_BYTES" ] || hosting_game; then idle=0
		else idle=$((idle + IDLE_CHECK)); fi
		last=$now
		if [ $idle -ge $((min * 60)) ]; then
			nmcli connection down "$NAME" >/dev/null 2>&1 || true
			echo "idle for $min min, at $(date '+%H:%M')" >"$STATE/idle_down"
			if command -v notify-send >/dev/null 2>&1; then
				notify-send zs-vlan "The virtual LAN went off after $min idle minutes. Run vlan_auto to start it again." 2>/dev/null || true
			fi
			return 0
		fi
	done
}

# Take the tunnel down but keep keys, guests and the join ("start" brings it back), like going idle.
off() {
	local r
	r=$(role)
	case "$r" in host) STATE=$STATE_HOST ;; guest) STATE=$STATE_GUEST ;; *) echo "this PC isn't in a virtual LAN."; result "role=none state=down"; return 0 ;; esac
	watch_stop
	if tunnel_on; then nmcli connection down "$NAME" >/dev/null 2>&1 || true; echo "the virtual LAN is off (start it again: $SELF start)"
	else echo "the virtual LAN was already off"; fi
	echo "taken down at $(date '+%H:%M')" >"$STATE/idle_down"
	result "role=$r state=off"
}

# Show or change this PC's name. Guests send a fresh reply so the host sees it; hosts' new invites carry it.
name_cmd() {
	local r reply
	r=$(role)
	if [ -n "${1:-}" ]; then save_name "$1"
	elif [ -n "$SET_NAME" ]; then save_name "$SET_NAME"
	elif [ "$MACHINE" = 0 ] && [ -t 0 ]; then ask_name "$( [ "$r" = guest ] && echo "the host sees it in their guest list" || echo "guests see it next to $NET.1")"
	fi
	echo "name: \"$(my_name)\""
	case "$r" in
	host) echo "the next invites carry it; guests who already joined still see the old one until they get a new invite." ;;
	guest)
		if [ -n "${1:-}${SET_NAME}" ] || { [ "$MACHINE" = 0 ] && [ -t 0 ]; }; then
			echo "the host only sees it from a new reply:"; echo
			STATE=$STATE_GUEST
			reply=$(enc zsr2 "$(my_slot) $(pubkey "$(cat "$STATE/guest.key")") $PORT $(cat "$STATE/public" 2>/dev/null || echo "- -") $(my_name)")
			echo "$reply"; clip "$reply"
			echo; echo "the host pastes it into vlan_auto (or the dedicated server console)"
		fi ;;
	esac
	result "role=$r state=name name=$(pct "$(my_name)")"
}

stop() {
	local r=0
	if [ -d "$STATE_HOST" ]; then STATE=$STATE_HOST; teardown; r=1; fi
	if [ -d "$STATE_GUEST" ]; then STATE=$STATE_GUEST; teardown; r=1; fi
	if [ $r = 0 ] && conn_exists; then nmcli connection delete "$NAME" >/dev/null && echo "removed NM connection $NAME"; r=1; fi
	if [ -f "$NAME_FILE" ]; then rm -f "$NAME_FILE"; echo "removed the name ($NAME_FILE)"; r=1; fi
	[ $r = 1 ] || echo "nothing to remove."
	echo "done."
	result "role=none state=down"
}

# A pasted code: an invite joins, a reply adds a guest.
code() {
	case "$1" in
	zsi[12].*) guest_join "$1"; guest_show; guest_wait ;;
	zsr[12].*) host_add "$1" ;;
	*) die "that isn't a zs-vlan code (invites start with zsi2., replies with zsr2.)" ;;
	esac
}

# What the saved virtual LAN is, for the menu.  (empty: none)
saved_desc() {
	local n hname f
	case "$(role)" in
	host)
		n=0; for f in "$STATE_HOST"/peers/*; do [ -e "$f" ] && n=$((n + 1)); done
		echo "this PC hosts a virtual LAN as $NET.1, with $n guest(s)" ;;
	guest)
		[ -f "$STATE_GUEST/invite" ] || return 0
		read -r _ _ _ _ _ hname <<<"$(dec zsi "$(cat "$STATE_GUEST/invite")" 2>/dev/null)"
		echo "this PC joined the virtual LAN of \"$(clean_name "${hname:-the host}")\" as $NET.$(STATE=$STATE_GUEST my_slot)" ;;
	esac
}

# Remove the saved role before switching to the other one (or joining a different host).
leave() {
	if [ -d "$STATE_HOST" ]; then STATE=$STATE_HOST; teardown; fi
	if [ -d "$STATE_GUEST" ]; then STATE=$STATE_GUEST; teardown; fi
	echo
}

# Ask for an invite; only a valid-looking one replaces what's saved.  arg: the current role
ask_join() {
	local line
	read -r -p "paste the invite code from the host: " line || exit 1
	line=$(tr -d '[:space:]' <<<"$line")
	[[ $line == zsi[12].* ]] || die "that isn't an invite (invites start with zsi2.); nothing changed."
	dec zsi "$line" >/dev/null || fail 1
	[ "$1" = none ] || leave
	code "$line"
}

guided() {
	local pick r saved yn
	r=$(role)
	if ! [ -t 0 ] || [ "$MACHINE" = 1 ]; then   # no one to ask: carry on with what's saved
		case "$r" in
		host) host_up; host_loop ;;
		guest) guest_up; guest_show; guest_wait ;;
		*) status ;;
		esac
		return
	fi
	saved=$(saved_desc)
	echo "zs-vlan: a private virtual LAN for co-op over the internet."
	echo
	if [ -n "$saved" ]; then
		echo "$saved."
		echo
		if [ "$r" = host ]; then
			echo "  c  continue hosting: start it again, show the next invite   (Enter)"
			echo "  j  join a friend instead (removes your virtual LAN and its guests)"
		else
			echo "  c  continue: start the tunnel again, show your reply   (Enter)"
			echo "  j  join a different host or a new invite (removes the old join)"
			echo "  h  host a game for friends instead (removes the old join)"
		fi
		echo "  s  stop: remove everything zs-vlan made"
		echo
		read -r -p "choice: " pick || exit 1
	else
		echo "  h  host a game for friends"
		echo "  j  join a friend (paste their invite)"
		echo
		read -r -p "choice: " pick || exit 1
	fi
	case "${pick:-c}" in
	c*|C*)
		case "$r" in
		host) host_up; host_loop ;;
		guest) guest_up; guest_show; guest_wait ;;
		*) die "nothing done." ;;
		esac ;;
	h*|H*)
		[ "$r" = guest ] && leave
		host_up; host_loop ;;
	j*|J*)
		if [ "$r" = host ]; then
			read -r -p "this removes your virtual LAN; your guests would need a new invite. Sure? [y/N] " yn || exit 1
			[[ $yn == [yY]* ]] || die "nothing changed."
		fi
		ask_join "$r" ;;
	s*|S*) [ "$r" = none ] && die "nothing done."; stop ;;
	*) die "nothing done." ;;
	esac
}

case "${1:-}" in
"") guided ;;
host)
	case "${2:-}" in
	"") host_up; if [ "$MACHINE" = 1 ]; then host_show; else host_loop; fi ;;
	add) [ -n "${3:-}" ] || die "usage: $SELF host add <reply>"; host_add "$3" ;;
	remove) host_remove "${3:-}" ;;
	*) die "usage: $SELF host [add <reply> | remove <N>]" ;;
	esac ;;
join) [ -n "${2:-}" ] || die "usage: $SELF join <invite>"; guest_join "$2"; guest_show; guest_wait ;;
start) start ;;
newaddress) newaddress ;;
status) status ;;
name) name_cmd "${2:-}" ;;
stop) stop ;;
off) off ;;
watch) watch "${2:-}" ;;
zsi[12].*|zsr[12].*) code "$1" ;;
-h|--help|help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//' ;;
*) die "unknown command '$1' (try: $SELF help)" ;;
esac
