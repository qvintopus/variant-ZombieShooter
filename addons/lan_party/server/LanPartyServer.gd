## Dedicated server base: the game itself, run headless with user arguments after "--":
##   godot --headless --path . -- --server [--port N] [--max-players N] [--name "Server"]
##        [--save-dir PATH] [--status SECONDS] [--control FILE] [--vlan] [--idle-kick MIN]
##        [and the game's extra_settings from lan_party.cfg, e.g. --main first|local]
## (tools/server.sh, tools/server.cmd: a menu that runs it in the background; LanPartyServerProcess
## starts it from the game).
##
## Extend it in the game, add the node when enabled() (an autoload's _ready is a good place) and:
## - host the session once the game is ready for players, then call report_hosting(error): it prints
##   the line "hosting on port N - OK" the launchers and LanPartyServerProcess wait for;
## - override players(), is_hosting(), place(), info_fields() and shutdown() (save, tell the players,
##   leave; the base then quits);
## - add console commands with console.register_command() in _server_ready().
## Commands typed into its window go to LanPartyConsole ("help"); with --control FILE they also come
## from the launchers and the game over a private channel.
##
## --vlan: the launcher has brought up the virtual LAN on this PC (this PC is <vlan_net>.1); the
## server says so once it's hosting, and guests are added from its console.
class_name LanPartyServer
extends Node

const MIN_PLAYERS:int = 2
## Built-in user options that take a value.
const VALUE_OPTIONS:PackedStringArray = ["port", "max-players", "save-dir", "name", "status", "idle-kick", "control"]
const FLAG_OPTIONS:PackedStringArray = ["server", "vlan"]

static var _options:Dictionary = {}
static var _parsed:bool
static var _extra_values:PackedStringArray = []
static var _extra_flags:PackedStringArray = []

var port:int
var server_name:String = "Server"
var max_players:int = 8
## Minutes a player may idle before the game drops them (0 = never). The game applies it.
var idle_kick_min:float
## When the server started (unix time).
var started:int
var console:LanPartyConsole
## --status N: a status line every N seconds (tests, operators).
var _status_every:float
var _status_left:float

## An option of the game's own; call before options() is first read (e.g. in a static
## initializer or before adding the server). lan_party.cfg's extra_settings are registered already.
static func register_option(option:String, takes_value:bool)->void:
	var _name:String = option.trim_prefix("--")
	if takes_value:
		_extra_values.append(_name)
	else:
		_extra_flags.append(_name)
	_parsed = false

## The command line asks for a server.
static func enabled()->bool:
	return options().has("server")

## The user args (after "--") as {option without "--": value, or true for flags}.
static func options()->Dictionary:
	if _parsed:
		return _options
	_parsed = true
	_options = parse_args(OS.get_cmdline_user_args())
	return _options

static func parse_args(args:PackedStringArray)->Dictionary:
	var _values:PackedStringArray = VALUE_OPTIONS.duplicate()
	_values.append_array(_extra_values)
	for _extra:Dictionary in LanPartyConfig.extra_settings():
		_values.append(_extra.name)
	var _flags:PackedStringArray = FLAG_OPTIONS.duplicate()
	_flags.append_array(_extra_flags)
	var _result:Dictionary = {}
	var _i:int = 0
	while _i < args.size():
		var _arg:String = args[_i].trim_prefix("--")
		if args[_i].begins_with("--") && _flags.has(_arg):
			_result[_arg] = true
		elif args[_i].begins_with("--") && _values.has(_arg) && _i + 1 < args.size():
			_result[_arg] = args[_i + 1]
			_i += 1
		_i += 1
	return _result

## An option's value ("" when not given).
static func option(name:String, default:String = "")->String:
	return str(options().get(name, default))

## The folder --save-dir names (user://server when not given): point the game's saves there
## before any is read, so the server never touches a player's own saves.
static func save_dir()->String:
	var _dir:String = option("save-dir")
	return _dir if !_dir.is_empty() else "user://server"

func _ready()->void:
	started = int(Time.get_unix_time_from_system())
	port = clampi(int(option("port", str(LanPartyConfig.game_port()))), 1, 65535)
	var _name:String = LanPartyConfig.clean_name(option("name", LanPartyConfig.get_value("server_name")))
	server_name = _name if !_name.is_empty() else "Server"
	max_players = clampi(int(option("max-players", str(LanPartyConfig.max_players()))), MIN_PLAYERS, LanPartyConfig.max_players())
	idle_kick_min = maxf(float(option("idle-kick", LanPartyConfig.get_value("idle_kick"))), 0.0)
	_status_every = maxf(float(option("status", "0")), 0.0)
	var _master:int = AudioServer.get_bus_index("Master")
	if _master >= 0:
		AudioServer.set_bus_mute(_master, true)
	console = LanPartyConsole.new()
	console.name = "Console"
	console.server = self
	_server_ready()
	add_child(console)

func _process(delta:float)->void:
	if _status_every > 0.0:
		_status_left -= delta
		if _status_left <= 0.0:
			_status_left = _status_every
			print(status_line())

# --- for the game to override -------------------------------------------------------

## Set up before the console starts: register commands, apply options.
func _server_ready()->void:
	pass

## Players connected, not counting the server itself.
func players()->int:
	return 0

## The session is open for players.
func is_hosting()->bool:
	return false

## Where the server is, one word (underscores for spaces), for the launchers' status. "" = starting.
func place()->String:
	return ""

## More key=value pairs for the "info" line (no spaces in keys or values).
func info_fields()->Dictionary:
	return {}

## One line for "status" and --status.
func status_line()->String:
	return "SERVERSTATUS place=%s players=%d hosting=%d" % [place(), players(), int(is_hosting())]

## "stop": save, tell the players, close the session. May await. The server quits afterwards.
func shutdown()->void:
	pass

# --- for the game to call ------------------------------------------------------------

## After trying to host: the ready line the launchers wait for, then where to join.
func report_hosting(error:Error)->void:
	print("LanPartyServer [INFO]: hosting on port %d - %s" % [port, error_string(error)])
	if error == OK:
		print_join_info()

## Where players connect from (what they type into Join), and the console hint.
func print_join_info()->void:
	var _vlan:String = LanPartyAddresses.vlan_address()
	if !_vlan.is_empty():
		print("LanPartyServer [INFO]: join over the virtual LAN at  " + join_text(_vlan))
	elif options().has("vlan"):
		print("LanPartyServer [WARN]: --vlan, but this PC has no %sx address; is the virtual LAN up? (vlan_auto status)" % LanPartyConfig.vlan_prefix())
	for _ip:String in LanPartyAddresses.lan_addresses():
		print("LanPartyServer [INFO]: join on the same network at  " + join_text(_ip))
	print("LanPartyServer [INFO]: join from this PC at  " + join_text("127.0.0.1"))
	if !_vlan.is_empty():
		print("LanPartyServer [INFO]: paste a guest's reply code here to add them; 'invite' shows the invite (the same for every guest)")
	print("LanPartyServer [INFO]: type help for the console commands")

func join_text(ip:String)->String:
	return LanPartyAddresses.join_text(ip, port)

## The "info" line's fields, in order (name is added last by the console).
func info()->Dictionary:
	var _vlan:String = LanPartyAddresses.vlan_address()
	var _info:Dictionary = {"room": place(), "players": players(), "up": int(Time.get_unix_time_from_system()) - started,
		"port": port, "max": max_players, "idle_kick": idle_kick_min, "vlan": _vlan if !_vlan.is_empty() else "-"}
	_info.merge(info_fields(), true)
	_info.hosting = int(is_hosting())
	return _info
