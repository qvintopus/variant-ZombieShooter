## A dedicated server (a second headless game started with --server, its saves
## in a temp folder) and this process as a player joining it from its own home
## base. Checks that the server shows nobody of its own (no copy, no party panel
## row), counts only real players for scaling, and that the hidden player is
## invisible, untouchable, never hurt and kept on the player; that walking onto
## the exit gate takes the server (and so us) to the mission; and that the
## server's saves land in its own folder. Then drives its console (stdin):
## players, status, kick usage, an unknown command, and stop, which saves the run,
## tells us and quits. The same commands over the control channel (--control: the
## launcher menu's way in): the token, info, players. Also the console's vlan_auto
## plumbing (paths, result line).
##   Godot --headless --path . res://game/tests/dedicated_server_check.tscn
extends Node

const PORT:int = 24597
const TD:String = "res://addons/top_down/"
const HOME:String = "res://game/scenes/room_H00.tscn"
const N00:String = "res://game/scenes/room_N00.tscn"

var failures:int = 0
var checks:int = 0
var _server:Dictionary
var _saved_names:Dictionary = {}
var _save_dir:String

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	# our home base saves while we're in it: keep the user's file out of it
	for _path:String in ["res://game/resources/home_base_resource.tres", "res://game/resources/campaign_resource.tres"]:
		var _resource:SaveableResource = load(_path)
		_saved_names[_resource] = _resource.resource_name
		_resource.resource_name += "_test"
		_resource.delete_resource()
		_resource.reset_resource()
	# another computer as far as the server can tell
	GuestSandbox.install_override = "dedicated_check"
	RunSession.profile.profile_id = "dedicated_check_%d" % OS.get_process_id()
	RunSession.local_player().profile_id = RunSession.profile.profile_id
	Transition.instant = true
	get_tree().current_scene = null
	_run.call_deferred()

func _run()->void:
	_save_dir = ProjectSettings.globalize_path("user://dedicated_check_%d" % OS.get_process_id())
	_server = _spawn_server()
	Transition.change_scene(HOME)
	check(await _wait(func ()->bool: return _body() != null, 10.0), "player: in our home base")
	check(await _wait(func ()->bool: return _read().contains("hosting on port %d - OK" % PORT), 60.0), "server: up and hosting from its home base")
	var _err:Error = Net.join("127.0.0.1:%d" % PORT)
	check(_err == OK, "player: connecting")
	check(await _wait(func ()->bool: return Net.is_guest() && _current() == HOME && _body() != null, 20.0), "player: joined, in the server's home base")
	check(Net.host_is_server, "player: knows it's a dedicated server")
	check(RunSession.players.local_slot == 1, "player: first seat after the server's (%d)" % RunSession.players.local_slot)
	check(RunSession.players.count() == 1 && RunSession.players.get_state(0) == null, "player: the server's own player isn't in our roster")
	await _frames(30)
	check(Net.players.puppets.is_empty(), "player: no copy of the server's player in the room")
	var _panel:PartyPanel = _find(get_tree().root, func (n:Node)->bool: return n is PartyPanel) as PartyPanel
	check(_panel == null || _panel.rows.is_empty(), "player: no party panel row for the server")
	check((_body().get_node("Body/Stretch/Sprite2D") as Sprite2D).texture == PlayerSkin.GUEST_TEXTURE, "player: wears the electrician (no visible host)")

	# the hidden player sits on us and is untouchable
	_body().global_position += Vector2(24, 8)
	check(await _wait(func ()->bool: return _status().contains("anchor_gap=") && float(_field("anchor_gap")) >= 0.0 && float(_field("anchor_gap")) < 4.0, 10.0), "server: hidden player follows us (%s)" % _field("anchor_gap"))
	check(_field("anchor_visible") == "false", "server: hidden player is invisible")
	check(_field("anchor_layers") == "0", "server: hidden player has no collision layer (doors, enemies, loot ignore it)")
	check(_field("players") == "1" && _field("active") == "1" && _field("scaling") == "1", "server: scales for one player (%s)" % _status())

	# onto the exit gate: the server departs and we follow
	var _gate:HomeExitGate = _find(get_tree().current_scene, func (n:Node)->bool: return n is HomeExitGate) as HomeExitGate
	check(_gate != null, "home base has its exit gate")
	if _gate != null:
		while _body().get_node("ResourceNode").get_resource("weapons").list.size() > 1:
			_body().get_node("ResourceNode").get_resource("weapons").list.pop_back()
		_body().global_position = _gate.global_position
	check(await _wait(func ()->bool: return _read().contains("scene " + N00), 20.0), "server: our walking onto the gate took it to the mission")
	check(await _wait(func ()->bool: return _current() == N00 && _body() != null, 20.0), "player: followed the server to the mission")
	check(await _wait(func ()->bool: return _field("room") == N00 && float(_field("anchor_gap")) >= 0.0 && float(_field("anchor_gap")) < 4.0, 10.0), "server: hidden player carried to the mission and on us")
	check(float(_field("anchor_hp")) > 0.0, "server: hidden player unhurt")

	check(FileAccess.file_exists(_save_dir.path_join("Profile.tres")), "server: saves in its own folder")
	check(!FileAccess.file_exists("user://Profile_server.tres"), "server: nothing extra in the user folder")

	# the console
	_say("players")
	check(await _wait(func ()->bool: return _read().contains("  slot %d  %s" % [RunSession.players.local_slot, RunSession.local_player().display_name]), 5.0), "console: players lists us")
	_say("status")
	check(await _wait(func ()->bool: return _read().contains("room room_N00, 1 player(s)"), 5.0), "console: status shows the room and players")
	_say("kick")
	check(await _wait(func ()->bool: return _read().contains("usage: kick <slot>"), 5.0), "console: kick without a slot shows its usage")
	_say("frobnicate")
	check(await _wait(func ()->bool: return _read().contains("unknown command 'frobnicate'"), 5.0), "console: unknown commands are named")
	# the control channel (the launcher menu)
	var _control:Dictionary = _read_control()
	check(int(_control.get("pid", "0")) > 0 && int(_control.get("control_port", "0")) > 0 && str(_control.get("token", "")).length() == 32, "control: file with pid, port and token (%s)" % _control.keys())
	var _reply:String = await _request(_control, "info")
	check(_reply.contains("INFO room=room_N00 players=1 ") && _reply.contains("port=%d" % PORT) && _reply.contains("name=Server"), "control: info answered (%s)" % _reply.strip_edges())
	_reply = await _request(_control, "players")
	check(_reply.contains("slot %d  %s" % [RunSession.players.local_slot, RunSession.local_player().display_name]), "control: players answered")
	_reply = await _request({"control_port": _control.get("control_port", "0"), "token": "nope"}, "stop")
	check(_reply.contains("bad token") && OS.is_process_running(_server.pid), "control: a wrong token is refused")
	var _ended:Array = []
	Net.session_ended.connect(func (reason:String)->void: _ended.append(reason), CONNECT_ONE_SHOT)
	_say("stop")
	check(await _wait(func ()->bool: return !OS.is_process_running(_server.pid), 15.0), "console: stop quits the server")
	check(_read().contains("ServerConsole [INFO]: stopping (run saved)"), "console: stop saved the run first")
	check(!FileAccess.file_exists(_save_dir + ".control"), "control: file removed on stop")
	check(FileAccess.file_exists(_save_dir.path_join(RunSave.file_name + ".tres")), "console: the run checkpoint is in the server's folder")
	check(_ended.size() == 1 && _ended[0] == "The server stopped", "player: told the server stopped (%s)" % [_ended])

	# vlan_auto plumbing (no tunnel is made)
	var _result:Dictionary = ServerConsole.parse_result("text\nZSVLAN role=host state=up code=zsi1.QUJD= guests=2:online\n")
	check(_result.get("role") == "host" && _result.get("code") == "zsi1.QUJD=" && _result.get("guests") == "2:online", "vlan: result line parsed (%s)" % _result)
	_result = ServerConsole.parse_result("ZSVLAN role=host state=added slot=3 name=Big%20Bob%2520 online=yes\n")
	check(_result.get("name") == "Big Bob%20" && _result.get("slot") == "3", "vlan: names in a result line unescaped (%s)" % _result)
	check(ServerConsole.parse_result("no result here").is_empty(), "vlan: no result line, no result")
	var _command:Array = ServerConsole.vlan_command(["host", "add", "zsr1.x"])
	check(_command.size() == 2 && _command[0] == "bash" && str(_command[1][0]).ends_with("tools/vlan/vlan_auto.sh") && _command[1][-1] == "--machine", "vlan: runs tools/vlan/vlan_auto.sh --machine (%s)" % [_command])
	_finish()

## A line into the server's console.
func _say(line:String)->void:
	var _pipe:FileAccess = _server.get("stdio")
	_pipe.store_string(line + "\n")
	_pipe.flush()

func _finish()->void:
	Net.players.leaving_by_choice = true
	Net.leave()
	if OS.is_process_running(_server.get("pid", -1)):
		OS.kill(_server.pid)
	if failures > 0:
		printerr(_read().right(4000))
	DirAccess.remove_absolute(_server.get("log", ""))
	_remove_dir(_save_dir)
	var _scene:Node = get_tree().current_scene
	if _scene != null:
		_scene.queue_free()
	await _frames(4)
	for _resource:SaveableResource in _saved_names:
		_resource.delete_resource()
		_resource.resource_name = _saved_names[_resource]
	print("dedicated_server_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

static func _remove_dir(path:String)->void:
	if !DirAccess.dir_exists_absolute(path):
		return
	for _file:String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(_file))
	DirAccess.remove_absolute(path)

func _spawn_server()->Dictionary:
	var _log:String = ProjectSettings.globalize_path("user://dedicated_server_%d.log" % Time.get_ticks_msec())
	var _cmd:String = "exec '%s' --headless --path '%s' -- --server --port %d --save-dir '%s' --status 0.5 --control '%s' > '%s' 2>&1" % [
		OS.get_executable_path(), ProjectSettings.globalize_path("res://"), PORT, _save_dir, _save_dir + ".control", _log]
	var _process:Dictionary = OS.execute_with_pipe("/bin/sh", ["-c", _cmd], false)
	return {"pid": _process.get("pid", -1), "stdio": _process.get("stdio"), "log": _log}

## The control file's key=value lines.
func _read_control()->Dictionary:
	var _out:Dictionary = {}
	for _line:String in FileAccess.get_file_as_string(_save_dir + ".control").split("\n", false):
		_out[_line.get_slice("=", 0)] = _line.substr(_line.find("=") + 1)
	return _out

## One control request, the way tools/server.sh sends it; "" on no answer.
func _request(control:Dictionary, command:String)->String:
	var _peer:StreamPeerTCP = StreamPeerTCP.new()
	if _peer.connect_to_host("127.0.0.1", int(control.get("control_port", "0"))) != OK:
		return ""
	var _text:String = ""
	var _sent:bool = false
	var _left:float = 5.0
	while _left > 0.0:
		_peer.poll()
		var _status:int = _peer.get_status()
		if _status == StreamPeerTCP.STATUS_CONNECTED:
			if !_sent:
				_peer.put_data(("TOKEN %s\n%s\n" % [control.get("token", ""), command]).to_utf8_buffer())
				_sent = true
			if _peer.get_available_bytes() > 0:
				_text += _peer.get_utf8_string(_peer.get_available_bytes())
		elif _status != StreamPeerTCP.STATUS_CONNECTING:
			break
		await get_tree().process_frame
		_left -= get_process_delta_time()
	return _text

func _read()->String:
	return FileAccess.get_file_as_string(_server.log) if FileAccess.file_exists(_server.get("log", "")) else ""

## The server's latest status line.
func _status()->String:
	var _lines:PackedStringArray = _read().split("\n")
	for _i:int in range(_lines.size() - 1, -1, -1):
		if _lines[_i].begins_with("SERVERSTATUS "):
			return _lines[_i]
	return ""

func _field(key:String)->String:
	for _part:String in _status().split(" "):
		if _part.begins_with(key + "="):
			return _part.substr(key.length() + 1)
	return ""

func _body()->Node2D:
	return Net.players.local_body()

func _current()->String:
	var _scene:Node = get_tree().current_scene
	return _scene.scene_file_path if _scene != null else ""

static func _find(node:Node, test:Callable)->Node:
	if node == null:
		return null
	if test.call(node):
		return node
	for _child:Node in node.get_children():
		var _found:Node = _find(_child, test)
		if _found != null:
			return _found
	return null

func _wait(condition:Callable, seconds:float)->bool:
	var _end:int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < _end:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()

func _frames(count:int)->void:
	for _i:int in count:
		await get_tree().physics_frame
