## Dedicated server: a headless host whose own player is hidden. The generic part (options, the
## console and its control channel, the ready line, join info) is the LAN Party addon's
## LanPartyServer; this is the game's part. Started with
##   Godot --headless --path . -- --server [--port N] [--max-players 2..8]
##                                [--save-dir PATH] [--name "Server"] [--vlan] [--idle-kick MIN]
##                                [--main first|local]
## (tools/server.sh, tools\server.cmd on Windows: a menu that runs it in the background).
## It skips the title, opens the session in its home base and from then on goes where the players
## go: their copies walk through its doors and exit gate like a host's teammates do. Its own player
## is server_player.tscn (Net swaps it in): the player scene with everything seen or used switched
## off, carried along and kept on the party leader (ServerAnchor).
##
## Victory and game over return it to the home base by themselves; so does the
## last player leaving mid-run (the run is checkpointed first).
##
## --idle-kick MIN: guests idle that long are dropped, ghosts after 3x that (Net.idle_kick_min);
## 0 keeps everyone.
## --main first|local (lan_party.cfg extra_settings): who becomes the main player, who wears the
## host's plumber (Net.main_mode): the first player to join (default), or the first to join from
## this PC. The seat stays theirs while they're away; the console's "main" command changes it.
class_name DedicatedServer
extends LanPartyServer

const HOME_SCENE:String = "res://game/scenes/room_H00.tscn"
const TITLE_SCENE:String = "res://game/scenes/title.tscn"
const VICTORY_SCENE:String = "res://game/scenes/victory.tscn"
const GAME_OVER_SCENE:String = "res://addons/top_down/scenes/ui/screens/game_over.tscn"
## Seconds on the victory screen before going home (sooner once nobody follows).
const VICTORY_WAIT:float = 20.0
const GAME_OVER_WAIT:float = 8.0

var _scene:Node
var _scene_time:float
var _going_home:bool

## Before any save is read (RunSession._ready): the server's own save folder.
static func configure_early()->void:
	if !enabled():
		return
	var _dir:String = save_dir()
	DirAccess.make_dir_recursive_absolute(_dir)
	SaveableResource.save_dir = _dir

func _server_ready()->void:
	Net.max_players = max_players
	Net.idle_kick_min = idle_kick_min
	var _main_mode:String = option("main", "first").to_lower()
	Net.main_mode = _main_mode if Net.MAIN_MODES.has(_main_mode) else "first"
	Transition.instant = true
	var _local:PlayerState = RunSession.local_player()
	_local.hidden = true
	_local.display_name = server_name
	print("DedicatedServer [INFO]: port %d, up to %d players, saves in %s, %s, main player: %s" % [port, Net.max_players, SaveableResource.save_dir,
		("idle guests dropped after %s min (ghosts %s min)" % [Net.idle_kick_min, Net.idle_kick_min * Net.IDLE_GHOST_FACTOR]) if Net.idle_kick_min > 0.0 else "no idle kick",
		"first to join" if Net.main_mode == "first" else "first to join from this PC"])
	console.register_command("status", "status                 room, players, hidden player", _cmd_status)
	console.register_command("players", "players                everyone connected: slot, name, state, address (* = the main player)", _cmd_players)
	console.register_command("main", "main                   who is the main player (the plumber) and how it's chosen\n"
		+ "  main <slot>            make that player the main player\n"
		+ "  main free              nobody: the next player to join (that the mode allows) gets it\n"
		+ "  main mode first|local  main = the first player to join / the first from this PC (--main)", _cmd_main)
	console.register_command("kick", "kick <slot> [reason]   drop a player (slot from 'players')", _cmd_kick)
	console.register_command("home", "home                   save the run and go back to the home base", _cmd_home)

func current_path()->String:
	return _scene.scene_file_path if _scene != null else ""

func _process(delta:float)->void:
	super(delta)
	var _now:Node = get_tree().current_scene
	if _now != _scene:
		_scene = _now
		_scene_time = 0.0
		_going_home = false
		_on_scene_changed()
	_scene_time += delta
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
				report_hosting(Net.host(port))

func go_home()->void:
	if _going_home:
		return
	_going_home = true
	Transition.change_scene(HOME_SCENE)

# --- LanPartyServer ---------------------------------------------------------------

## Players connected (ghosts too: they'll be back), not counting our own.
func players()->int:
	var _count:int = 0
	for _state:PlayerState in RunSession.players.all():
		if !_state.is_local:
			_count += 1
	return _count

func is_hosting()->bool:
	return Net.is_host()

## "home_base", or the room's name without "room_" (N00), for the launchers' status.
func place()->String:
	var _path:String = current_path()
	if _path == HOME_SCENE:
		return "home_base"
	return _path.get_file().get_basename().trim_prefix("room_")

func info_fields()->Dictionary:
	var _main:PlayerState = Net.main_player()
	var _who:String = str(_main.slot) if _main != null else ("away" if !Net.main_key.is_empty() else "-")
	return {"active": RunSession.players.count_active(), "main": "%s:%s" % [Net.main_mode, _who]}

## Save, tell everyone, leave (after the kick messages had time to arrive).
func shutdown()->void:
	var _saved:bool = RunSession.checkpoint()
	if _saved:
		print("DedicatedServer [INFO]: run saved")
	var _kicked:bool = false
	for _state:PlayerState in RunSession.players.all():
		if !_state.is_local:
			Net.kick(_state.slot, "The server stopped")
			_kicked = true
	if _kicked:
		await get_tree().create_timer(Net.REJECT_GRACE * 0.5).timeout
	Net.leave()

## One line: room, players, the hidden player's state and where it is.
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

## Guests still in the session on the victory screen (not gone home).
func _following_guests()->int:
	var _count:int = 0
	for _state:PlayerState in RunSession.players.all():
		if !_state.is_local && !_state.ghost:
			_count += 1
	return _count

## Everyone is down: the run ends here too (the hidden player dies for real).
func on_party_wiped()->void:
	var _body:Node2D = Net.players.local_body()
	var _anchor:ServerAnchor = _body.get_node_or_null("ServerAnchor") as ServerAnchor if _body != null else null
	if _anchor != null:
		_anchor.wipe()

# --- console commands -------------------------------------------------------------

func _cmd_status(_words:PackedStringArray)->void:
	console.say(status_line())
	var _vlan_ip:String = LanPartyAddresses.vlan_address()
	console.say("room %s, %d player(s), %d active, port %d%s" % [
		current_path().get_file().get_basename(), players(), RunSession.players.count_active(),
		Net.port, (", VLAN %s" % _vlan_ip) if !_vlan_ip.is_empty() else ""])

func _cmd_players(_words:PackedStringArray)->void:
	var _any:bool = false
	for _state:PlayerState in RunSession.players.all():
		if _state.is_local:
			continue
		_any = true
		var _what:String = "ghost (at own home base)" if _state.ghost else ("down" if _state.downed else "active")
		var _idle:String = (" idle %dm" % int(_state.idle_time / 60.0)) if _state.idle_time >= 60.0 else ""
		console.say("%s slot %d  %-24s %-26s %s%s" % [" *" if _state.main else "  ", _state.slot, _state.display_name, _what, Net.peer_address(_state.peer_id), _idle])
	if !_any:
		console.say("  nobody connected")
	elif Net.main_player() == null:
		console.say("  " + main_line())

## Who has the main seat, in words.
static func main_line()->String:
	var _how:String = "the first player to join" if Net.main_mode == "first" else "the first player to join from this PC"
	var _main:PlayerState = Net.main_player()
	if _main != null:
		return "main player (plumber): %s, slot %d   (mode %s: %s)" % [_main.display_name, _main.slot, Net.main_mode, _how]
	if !Net.main_key.is_empty():
		return "main player: away, their seat is kept for them until everyone has left   (mode %s; 'main free' gives it to the next to join)" % Net.main_mode
	return "main player: nobody yet, it goes to %s   (mode %s)" % [_how, Net.main_mode]

func _cmd_main(words:PackedStringArray)->void:
	if words.size() < 2:
		console.say(main_line())
		return
	var _arg:String = words[1].to_lower()
	if _arg == "mode":
		if words.size() < 3 || !Net.MAIN_MODES.has(words[2].to_lower()):
			console.say("usage: main mode first|local")
			return
		Net.main_mode = words[2].to_lower()
		if !Net.main_key.is_empty():
			console.say("mode %s: used once the seat is free ('main free'); the current main player keeps it" % Net.main_mode)
		console.say(main_line())
		return
	if _arg == "free":
		Net.set_main(-1)
		console.say(main_line())
		return
	if !_arg.is_valid_int() || !Net.set_main(int(_arg)):
		console.say("usage: main <slot> (a connected player, see 'players') | main free | main mode first|local")
		return
	console.say(main_line())

func _cmd_kick(words:PackedStringArray)->void:
	if words.size() < 2 || !words[1].is_valid_int():
		console.say("usage: kick <slot> [reason]   (slot from 'players')")
		return
	var _state:PlayerState = RunSession.players.get_state(int(words[1]))
	if _state == null || _state.is_local:
		console.say("no player in slot " + words[1])
		return
	var _reason:String = " ".join(words.slice(2)) if words.size() > 2 else "Kicked by the server"
	Net.kick(_state.slot, _reason)
	console.say("kicked %s (%s)" % [_state.display_name, _reason])

func _cmd_home(_words:PackedStringArray)->void:
	if current_path() == HOME_SCENE:
		console.say("already at the home base")
		return
	RunSession.checkpoint()
	go_home()
	console.say("run saved, going home")
