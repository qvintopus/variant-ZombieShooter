## Dedicated server: a headless host whose own player is hidden. Started with
##   Godot --headless --path . -- --server [--port N] [--max-players 2..8]
##                                [--save-dir PATH] [--name "Server"] [--vlan] [--idle-kick MIN]
##                                [--main first|local]
## (tools/server.sh, tools\server.cmd on Windows: a menu that runs it in the background).
## Commands typed into its window go to ServerConsole ("help"); with --control FILE they
## also come from the launcher menu. It skips the title, opens the session in its home base
## and from then on goes where the players go: their copies walk through its
## doors and exit gate like a host's teammates do. Its own player is
## server_player.tscn (Net swaps it in): the player scene with everything seen
## or used switched off, carried along and kept on the party leader
## (ServerAnchor).
##
## Victory and game over return it to the home base by themselves; so does the
## last player leaving mid-run (the run is checkpointed first).
##
## --vlan: the launcher has brought up the zs-vlan virtual LAN on this PC (this PC is
## 10.77.0.1); the server says so once it's hosting, and guests are added from its console.
## --idle-kick MIN (IDLE_KICK_MIN): guests idle that long are dropped, ghosts after 3x that
## (Net.idle_kick_min); 0 keeps everyone.
## --main first|local: who becomes the main player, who wears the host's plumber
## (Net.main_mode): the first player to join (default), or the first to join from this PC.
## The seat stays theirs while they're away; the console's "main" command changes it.
class_name DedicatedServer
extends Node

const HOME_SCENE:String = "res://game/scenes/room_H00.tscn"
const TITLE_SCENE:String = "res://game/scenes/title.tscn"
const VICTORY_SCENE:String = "res://game/scenes/victory.tscn"
const GAME_OVER_SCENE:String = "res://addons/top_down/scenes/ui/screens/game_over.tscn"
## Seconds on the victory screen before going home (sooner once nobody follows).
const VICTORY_WAIT:float = 20.0
const GAME_OVER_WAIT:float = 8.0
const MIN_PLAYERS:int = 2
const IDLE_KICK_MIN:float = 5.0

static var _options:Dictionary = {}
static var _parsed:bool

var port:int = 24565
var server_name:String = "Server"
var _scene:Node
var _scene_time:float
var _going_home:bool
## --status N: a status line every N seconds (tests, operators).
var _status_every:float
var _status_left:float
var console:ServerConsole

## The command line asks for a server.
static func enabled()->bool:
	return options().has("server")

## --server, --port, --max-players, --save-dir and --name from the user args.
static func options()->Dictionary:
	if _parsed:
		return _options
	_parsed = true
	var _args:PackedStringArray = OS.get_cmdline_user_args()
	var _i:int = 0
	while _i < _args.size():
		var _arg:String = _args[_i]
		if _arg in ["--server", "--vlan"]:
			_options[_arg.trim_prefix("--")] = true
		elif _arg in ["--port", "--max-players", "--save-dir", "--name", "--status", "--idle-kick", "--control", "--main"] && _i + 1 < _args.size():
			_options[_arg.trim_prefix("--")] = _args[_i + 1]
			_i += 1
		_i += 1
	return _options

## Before any save is read (RunSession._ready): the server's own save folder.
static func configure_early()->void:
	if !enabled():
		return
	var _dir:String = str(options().get("save-dir", ""))
	if _dir.is_empty():
		_dir = "user://server"
	DirAccess.make_dir_recursive_absolute(_dir)
	SaveableResource.save_dir = _dir

func _ready()->void:
	var _options_now:Dictionary = options()
	port = clampi(int(_options_now.get("port", str(Net.DEFAULT_PORT))), 1, 65535)
	server_name = Net._clean_name(str(_options_now.get("name", "Server")))
	Net.max_players = clampi(int(_options_now.get("max-players", str(Net.MAX_PLAYERS))), MIN_PLAYERS, Net.MAX_PLAYERS)
	_status_every = maxf(float(_options_now.get("status", "0")), 0.0)
	Net.idle_kick_min = maxf(float(_options_now.get("idle-kick", str(IDLE_KICK_MIN))), 0.0)
	var _main_mode:String = str(_options_now.get("main", "first")).to_lower()
	Net.main_mode = _main_mode if Net.MAIN_MODES.has(_main_mode) else "first"
	Transition.instant = true
	var _master:int = AudioServer.get_bus_index("Master")
	if _master >= 0:
		AudioServer.set_bus_mute(_master, true)
	var _local:PlayerState = RunSession.local_player()
	_local.hidden = true
	_local.display_name = server_name
	print("DedicatedServer [INFO]: port %d, up to %d players, saves in %s, %s, main player: %s" % [port, Net.max_players, SaveableResource.save_dir,
		("idle guests dropped after %s min (ghosts %s min)" % [Net.idle_kick_min, Net.idle_kick_min * Net.IDLE_GHOST_FACTOR]) if Net.idle_kick_min > 0.0 else "no idle kick",
		"first to join" if Net.main_mode == "first" else "first to join from this PC"])
	console = ServerConsole.new()
	console.name = "ServerConsole"
	console.server = self
	add_child(console)

func current_path()->String:
	return _scene.scene_file_path if _scene != null else ""

func _process(delta:float)->void:
	var _now:Node = get_tree().current_scene
	if _now != _scene:
		_scene = _now
		_scene_time = 0.0
		_going_home = false
		_on_scene_changed()
	_scene_time += delta
	if _status_every > 0.0:
		_status_left -= delta
		if _status_left <= 0.0:
			_status_left = _status_every
			print_status()
	match current_path():
		VICTORY_SCENE:
			if _scene_time >= VICTORY_WAIT || (_scene_time >= 3.0 && _following_guests() == 0):
				go_home()
		GAME_OVER_SCENE:
			if _scene_time >= GAME_OVER_WAIT:
				go_home()
		HOME_SCENE, "":
			pass
		_:
			# everyone left mid-run: keep the run and wait at home
			if Net.is_host() && players() == 0 && _scene_time > 1.0:
				RunSession.checkpoint()
				go_home()

func _on_scene_changed()->void:
	print("DedicatedServer [INFO]: scene ", current_path())
	_status_left = 0.0
	match current_path():
		TITLE_SCENE:
			go_home()
		HOME_SCENE:
			if Net.state == Net.State.OFFLINE:
				var _err:Error = Net.host(port)
				print("DedicatedServer [INFO]: hosting on port %d - %s" % [port, error_string(_err)])
				if _err == OK:
					_print_join_info()

## Where players connect from (what they type into Join), and the console hint.
func _print_join_info()->void:
	var _vlan:String = ENetTransport.vlan_address()
	if !_vlan.is_empty():
		print("DedicatedServer [INFO]: join over the virtual LAN at  " + _join(_vlan))
	elif options().has("vlan"):
		print("DedicatedServer [WARN]: --vlan, but this PC has no 10.77.0.x address; is the virtual LAN up? (tools/vlan/vlan_auto status)")
	for _ip:String in ENetTransport.lan_addresses():
		print("DedicatedServer [INFO]: join on the same network at  " + _join(_ip))
	print("DedicatedServer [INFO]: join from this PC at  " + _join("127.0.0.1"))
	if !_vlan.is_empty():
		print("DedicatedServer [INFO]: paste a guest's reply code here to add them; 'invite' shows the next invite")
	print("DedicatedServer [INFO]: type help for the console commands")

func _join(ip:String)->String:
	return ip if port == Net.DEFAULT_PORT else "%s:%d" % [ip, port]

func go_home()->void:
	if _going_home:
		return
	_going_home = true
	Transition.change_scene(HOME_SCENE)

## Players connected (ghosts too: they'll be back), not counting our own.
func players()->int:
	var _count:int = 0
	for _state:PlayerState in RunSession.players.all():
		if !_state.is_local:
			_count += 1
	return _count

## Guests still in the session on the victory screen (not gone home).
func _following_guests()->int:
	var _count:int = 0
	for _state:PlayerState in RunSession.players.all():
		if !_state.is_local && !_state.ghost:
			_count += 1
	return _count

## One line: room, players, the hidden player's state and where it is.
func print_status()->void:
	print(status_line())

func status_line()->String:
	var _body:Node2D = Net.players.local_body()
	var _shown:bool = false
	var _layers:int = -1
	var _at:Vector2 = Vector2.ZERO
	if _body != null:
		_shown = (_body.get_node("Body") as Node2D).is_visible_in_tree()
		_layers = (_body as CollisionObject2D).collision_layer
		_at = _body.global_position
	var _leader:Node2D = ServerAnchor.leader()
	var _gap:float = _leader.global_position.distance_to(_at) if _leader != null && _body != null else -1.0
	var _hp:float = RunSession.local_player().health.hp
	return ("SERVERSTATUS room=%s players=%d active=%d scaling=%d anchor_visible=%s anchor_layers=%d anchor_gap=%.1f anchor_hp=%.1f" % [
		current_path(), players(), RunSession.players.count_active(), CoopScaling.players(), _shown, _layers, _gap, _hp])

## Everyone is down: the run ends here too (the hidden player dies for real).
func on_party_wiped()->void:
	var _body:Node2D = Net.players.local_body()
	var _anchor:ServerAnchor = _body.get_node_or_null("ServerAnchor") as ServerAnchor if _body != null else null
	if _anchor != null:
		_anchor.wipe()
