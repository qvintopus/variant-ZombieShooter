# LAN Party settings for the bash scripts (sourced, not run): sets LP_<KEY> for every key=value in
#   1. the defaults below,
#   2. the addon's lan_party.cfg (two folders up from this file),
#   3. lan_party.cfg in this folder (a copy the game made for an exported build: already merged),
#   4. lan_party.cfg next to the project's project.godot (the nearest folder above this one that has it),
#   5. $LANPARTY_CONFIG, when set (tests).
# Later ones win. The file is parsed, never run. Values are trimmed; '#' starts a comment.

LP_PREFIX=lanparty
LP_VLAN_NAME=lanparty
LP_VLAN_NET=10.88.0
LP_VLAN_PORT=51820
LP_GAME_PORT=7777
LP_CODE_PREFIX=lp
LP_GAME_TITLE="Godot game"
LP_SERVER_NAME=Server
LP_MAX_PLAYERS=8
LP_IDLE_KICK=5
LP_EXTRA_SETTINGS=

lp_cfg_read() {
	[ -f "$1" ] || return 0
	local line key value
	while IFS= read -r line || [ -n "$line" ]; do
		line=${line%%#*}
		line=${line%$'\r'}
		[[ $line == *=* ]] || continue
		key=${line%%=*}; key=${key//[[:space:]]/}
		value=${line#*=}
		value=${value#"${value%%[![:space:]]*}"}; value=${value%"${value##*[![:space:]]}"}
		[[ $key =~ ^[a-z_][a-z0-9_]*$ ]] || continue
		printf -v "LP_${key^^}" '%s' "$value"
	done <"$1"
}

# The folder above $1 (inclusive) that holds project.godot; "" if none.
lp_project_dir() {
	local d=$1
	while [ -n "$d" ] && [ "$d" != / ]; do
		[ -f "$d/project.godot" ] && { printf '%s' "$d"; return 0; }
		d=$(dirname "$d")
	done
	return 0
}

LP_TOOLS_VLAN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LP_PROJECT=$(lp_project_dir "$LP_TOOLS_VLAN")
lp_cfg_read "$LP_TOOLS_VLAN/../../lan_party.cfg"
lp_cfg_read "$LP_TOOLS_VLAN/lan_party.cfg"
[ -n "$LP_PROJECT" ] && lp_cfg_read "$LP_PROJECT/lan_party.cfg"
[ -n "${LANPARTY_CONFIG:-}" ] && lp_cfg_read "$LANPARTY_CONFIG"
# State folders live under the user's state dir.
LP_STATE_BASE=${XDG_STATE_HOME:-$HOME/.local/state}
