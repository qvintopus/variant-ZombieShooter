## LAN Party settings: addons/lan_party/lan_party.cfg (defaults), then res://lan_party.cfg (the game's
## own, next to project.godot), then $LANPARTY_CONFIG (tests). The scripts in tools/ read the same
## files (tools/vlan/lp_config.sh / .ps1), so the game and the scripts always agree on names.
## Plain "key=value" lines, '#' starts a comment.
class_name LanPartyConfig
extends RefCounted

const ADDON_DIR:String = "res://addons/lan_party"
const DEFAULTS_PATH:String = ADDON_DIR + "/lan_party.cfg"
const PROJECT_PATH:String = "res://lan_party.cfg"
## Names (players, servers) are cut to this many characters, here and in the scripts.
const MAX_NAME_LENGTH:int = 24

## Used when no file has the key at all.
const FALLBACK:Dictionary = {
	"prefix": "lanparty", "vlan_name": "lanparty", "vlan_net": "10.88.0", "vlan_port": "51820",
	"game_port": "7777", "code_prefix": "lp", "game_title": "Godot game", "server_name": "Server",
	"max_players": "8", "idle_kick": "5", "extra_settings": "",
}

static var _values:Dictionary = {}
static var _loaded:bool

## All settings, merged.
static func values()->Dictionary:
	if !_loaded:
		_loaded = true
		_values = FALLBACK.duplicate()
		_values.merge(read_file(DEFAULTS_PATH), true)
		_values.merge(read_file(PROJECT_PATH), true)
		if OS.has_environment("LANPARTY_CONFIG"):
			_values.merge(read_file(OS.get_environment("LANPARTY_CONFIG")), true)
	return _values

## Forget the cached values (tests change the files).
static func reload()->void:
	_loaded = false

static func get_value(key:String)->String:
	return str(values().get(key, ""))

static func get_int(key:String)->int:
	return int(get_value(key))

## "key=value" lines -> {key: value}; {} when the file isn't there.
static func read_file(path:String)->Dictionary:
	var _result:Dictionary = {}
	if path.is_empty() || !FileAccess.file_exists(path):
		return _result
	for _line:String in FileAccess.get_file_as_string(path).split("\n"):
		_line = _line.get_slice("#", 0)
		var _at:int = _line.find("=")
		if _at < 1:
			continue
		var _key:String = _line.substr(0, _at).strip_edges()
		if _key.is_valid_identifier() && _key == _key.to_lower():
			_result[_key] = _line.substr(_at + 1).strip_edges()
	return _result

## The merged settings as file text (written next to staged scripts, see LanPartyVlan).
static func as_text()->String:
	var _keys:Array = values().keys()
	_keys.sort()
	var _text:String = "# written by the game: LAN Party settings, merged\n"
	for _key:String in _keys:
		_text += "%s=%s\n" % [_key, values()[_key]]
	return _text

# --- the names everything shares ---------------------------------------------------

static func prefix()->String:
	return get_value("prefix")

static func game_port()->int:
	return clampi(get_int("game_port"), 1, 65535)

static func max_players()->int:
	return maxi(get_int("max_players"), 2)

static func vlan_prefix()->String:
	return get_value("vlan_net") + "."

static func vlan_host()->String:
	return get_value("vlan_net") + ".1"

## The virtual LAN as people see it called ("zs-vlan").
static func vlan_brand()->String:
	return prefix() + "-vlan"

static func invite_prefix()->String:
	return get_value("code_prefix") + "i"

static func reply_prefix()->String:
	return get_value("code_prefix") + "r"

## A pasted reply code (any version).
static func is_reply_code(text:String)->bool:
	var _p:String = reply_prefix()
	return text.begins_with(_p + "1.") || text.begins_with(_p + "2.")

static func is_invite_code(text:String)->bool:
	var _p:String = invite_prefix()
	return text.begins_with(_p + "1.") || text.begins_with(_p + "2.")

## extra_settings "main:first,local;x:a,b" -> [{name, choices}]
static func extra_settings()->Array[Dictionary]:
	var _list:Array[Dictionary] = []
	for _entry:String in get_value("extra_settings").split(";", false):
		_entry = _entry.strip_edges().replace(" ", "")
		var _at:int = _entry.find(":")
		if _at < 1:
			continue
		var _choices:PackedStringArray = _entry.substr(_at + 1).split(",", false)
		if !_choices.is_empty():
			_list.append({"name": _entry.substr(0, _at), "choices": _choices})
	return _list

## The user's state folder the scripts use on Linux ($XDG_STATE_HOME or ~/.local/state).
static func state_home()->String:
	var _state:String = OS.get_environment("XDG_STATE_HOME")
	if _state.is_empty():
		_state = OS.get_environment("HOME").path_join(".local/state")
	return _state

## Names cleaned the way the scripts do: printable, single spaces, at most MAX_NAME_LENGTH.
static func clean_name(text:String)->String:
	var _out:String = ""
	for _i:int in text.length():
		var _c:int = text.unicode_at(_i)
		if _c >= 32 && _c != 127:
			_out += char(_c)
	while _out.contains("  "):
		_out = _out.replace("  ", " ")
	return _out.strip_edges().left(MAX_NAME_LENGTH).strip_edges()
