## The background dedicated server, from the game: start it (this Godot, headless, its own
## process that outlives the game), ask it things over its control channel, stop it.
## It uses the same folder and files as tools/server.sh and tools\server.cmd, so each sees a
## server the other started:
##   Linux:   $XDG_STATE_HOME/zs-server (~/.local/state/zs-server)
##   Windows: %LOCALAPPDATA%\zs-server
##   control    written by the server: pid, control_port, token, port, started, name
##   server.log its output (the last one is server.log.1)
##   settings   port, name, max_players, idle_kick, vlan, main (key=value, the scripts' menu edits it too)
## ZS_SERVER_DIR overrides the folder (tests).
##
## Requests: "TOKEN <token>\n<command>\n", the answer, then the server closes the connection
## (ServerConsole). The server started here always uses --main local: this PC's player is the
## main player (the plumber) when it joins.
class_name ServerProcess
extends RefCounted

const DEFAULTS:Dictionary = {"port": "24565", "name": "Server", "max_players": "8", "idle_kick": "5", "vlan": "no", "main": "first"}
const CONNECT_TIMEOUT:float = 2.0
const ANSWER_TIMEOUT:float = 8.0
## Seconds to wait for a started server to host, or a stopped one to go.
const START_TIMEOUT:float = 45.0
const STOP_TIMEOUT:float = 15.0

static func state_dir()->String:
	if OS.has_environment("ZS_SERVER_DIR"):
		return OS.get_environment("ZS_SERVER_DIR")
	if OS.get_name() == "Windows":
		return OS.get_environment("LOCALAPPDATA").path_join("zs-server")
	var _state:String = OS.get_environment("XDG_STATE_HOME")
	if _state.is_empty():
		_state = OS.get_environment("HOME").path_join(".local/state")
	return _state.path_join("zs-server")

static func control_path()->String:
	return state_dir().path_join("control")

static func log_path()->String:
	return state_dir().path_join("server.log")

static func settings_path()->String:
	return state_dir().path_join("settings")

static func _key_values(path:String)->Dictionary:
	var _values:Dictionary = {}
	if !FileAccess.file_exists(path):
		return _values
	for _line:String in FileAccess.get_file_as_string(path).split("\n", false):
		var _at:int = _line.find("=")
		if _at > 0:
			_values[_line.substr(0, _at).strip_edges()] = _line.substr(_at + 1).strip_edges()
	return _values

## The control file's values ({} when no server wrote one).
static func control()->Dictionary:
	return _key_values(control_path())

## The saved settings, with the scripts' defaults for what's missing or broken.
static func load_settings()->Dictionary:
	var _settings:Dictionary = DEFAULTS.duplicate()
	var _saved:Dictionary = _key_values(settings_path())
	if str(_saved.get("port", "")).is_valid_int():
		_settings.port = str(clampi(int(_saved.port), 1024, 65535))
	if !str(_saved.get("name", "")).is_empty():
		_settings.name = _saved.name
	if str(_saved.get("max_players", "")).is_valid_int():
		_settings.max_players = str(clampi(int(_saved.max_players), 2, 8))
	if str(_saved.get("idle_kick", "")).is_valid_float():
		_settings.idle_kick = str(maxf(float(_saved.idle_kick), 0.0))
	if _saved.get("vlan", "") in ["yes", "no"]:
		_settings.vlan = _saved.vlan
	if _saved.get("main", "") in ["first", "local"]:
		_settings.main = _saved.main
	return _settings

static func save_settings(settings:Dictionary)->void:
	DirAccess.make_dir_recursive_absolute(state_dir())
	var _file:FileAccess = FileAccess.open(settings_path(), FileAccess.WRITE)
	if _file == null:
		return
	for _key:String in ["port", "name", "max_players", "idle_kick", "vlan", "main"]:
		_file.store_string("%s=%s\n" % [_key, settings.get(_key, DEFAULTS[_key])])
	_file.close()

## The pid this game started (OS.is_process_running only knows its own children).
static var _spawned:int = -1

## The server's process is alive, by the control file's pid. A file left by a server that
## is surely gone is removed, as the scripts do.
static func alive()->bool:
	var _pid:int = int(control().get("pid", "0"))
	if _pid <= 0:
		return false
	if _pid != _spawned && OS.get_name() == "Windows":
		# started by tools\server.cmd: no cheap check here; it removes the file when it stops,
		# and a killed one just doesn't answer
		return true
	# ours (this also reaps it once it has ended), or any on Linux
	if _pid_running(_pid):
		return true
	DirAccess.remove_absolute(control_path())
	return false

## Godot and its arguments for a server with `settings` (see DedicatedServer).
static func command(settings:Dictionary)->Array:
	var _args:PackedStringArray = ["--headless"]
	if !OS.has_feature("template"):
		_args.append_array(["--path", ProjectSettings.globalize_path("res://").trim_suffix("/")])
	if OS.get_name() == "Windows":
		# no shell redirect on Windows (it locks the log for readers): Godot writes the log itself
		_args.append_array(["--log-file", log_path()])
	_args.append_array(["--", "--server", "--control", control_path(),
		"--port", str(settings.port), "--name", str(settings.name), "--max-players", str(settings.max_players),
		"--idle-kick", str(settings.idle_kick), "--main", "local"])
	if settings.get("vlan", "no") == "yes":
		_args.append("--vlan")
	# not a saved setting: tests keep the server's saves out of the user's
	if !str(settings.get("save_dir", "")).is_empty():
		_args.append_array(["--save-dir", str(settings.save_dir)])
	return [OS.get_executable_path(), _args]

## Start it in the background. Returns the pid (-1: failed). Then wait with ready().
static func start(settings:Dictionary)->int:
	DirAccess.make_dir_recursive_absolute(state_dir())
	if FileAccess.file_exists(log_path()):
		DirAccess.rename_absolute(log_path(), log_path() + ".1")
	DirAccess.remove_absolute(control_path())
	var _command:Array = command(settings)
	if OS.get_name() == "Windows":
		_spawned = OS.create_process(str(_command[0]), _command[1], false)
		return _spawned
	# output to the log. Godot starts it in its own session already (closing a terminal
	# the game came from doesn't end it), so no setsid: that would fork, and this pid would
	# be setsid's, gone at once
	var _sh:PackedStringArray = ["-c", 'log=$1; shift; exec "$@" >"$log" 2>&1 </dev/null', "sh", log_path(), str(_command[0])]
	_sh.append_array(_command[1])
	# sh execs in place: this pid is the server's
	_spawned = OS.create_process("/bin/sh", _sh)
	return _spawned

## One command to the running server; its answer without the echoed "> command" line,
## or "" when no server answers. A coroutine: await it.
static func request(command_line:String)->String:
	var _control:Dictionary = control()
	var _port:int = int(_control.get("control_port", "0"))
	if _port <= 0:
		return ""
	var _peer:StreamPeerTCP = StreamPeerTCP.new()
	if _peer.connect_to_host("127.0.0.1", _port) != OK:
		return ""
	var _tree:SceneTree = Engine.get_main_loop() as SceneTree
	var _waited:float = 0.0
	while true:
		_peer.poll()
		var _status:int = _peer.get_status()
		if _status == StreamPeerTCP.STATUS_CONNECTED:
			break
		if _status == StreamPeerTCP.STATUS_ERROR || _status == StreamPeerTCP.STATUS_NONE || _waited > CONNECT_TIMEOUT:
			_peer.disconnect_from_host()
			return ""
		await _tree.process_frame
		_waited += _tree.root.get_process_delta_time()
	_peer.put_data(("TOKEN %s\n%s\n" % [_control.get("token", ""), command_line]).to_utf8_buffer())
	var _text:String = ""
	_waited = 0.0
	while _waited <= ANSWER_TIMEOUT:
		_peer.poll()
		if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var _bytes:int = _peer.get_available_bytes()
		if _bytes > 0:
			_text += _peer.get_utf8_string(_bytes)
		await _tree.process_frame
		_waited += _tree.root.get_process_delta_time()
	_peer.disconnect_from_host()
	var _lines:PackedStringArray = []
	for _line:String in _text.split("\n"):
		if !_line.begins_with("> "):
			_lines.append(_line.trim_suffix("\r"))
	return "\n".join(_lines).strip_edges()

## "INFO room=... players=... ... name=Some Name" -> {room, players, ..., name}; {} if none.
static func parse_info(answer:String)->Dictionary:
	for _line:String in answer.split("\n"):
		if !_line.begins_with("INFO "):
			continue
		var _info:Dictionary = {}
		var _at:int = _line.find(" name=")
		_info.name = _line.substr(_at + 6) if _at >= 0 else ""
		for _pair:String in (_line.substr(5, _at - 5) if _at >= 0 else _line.substr(5)).split(" ", false):
			var _eq:int = _pair.find("=")
			if _eq > 0:
				_info[_pair.substr(0, _eq)] = _pair.substr(_eq + 1)
		return _info
	return {}

## The running server's info, {} when none answers. A coroutine.
static func info()->Dictionary:
	if !alive():
		return {}
	return parse_info(await request("info"))

## After start: wait until it hosts. "" = up, else what went wrong. A coroutine.
static func wait_ready(pid:int)->String:
	var _tree:SceneTree = Engine.get_main_loop() as SceneTree
	var _left:float = START_TIMEOUT
	while _left > 0.0:
		await _tree.create_timer(0.5).timeout
		_left -= 0.5
		if !FileAccess.file_exists(control_path()):
			if _left < START_TIMEOUT - 6.0 && pid > 0 && !OS.is_process_running(pid):
				return "the server quit while starting:\n" + log_tail(8)
			continue
		var _info:Dictionary = await info()
		if _info.get("hosting", "0") == "1":
			return ""
		var _hosting:String = _log_line("hosting on port")
		if !_hosting.is_empty() && !_hosting.ends_with("- OK"):
			stop_now()
			return "the server couldn't open its port: " + _hosting.get_slice("]: ", 1)
	return "the server is slow to start; see its log"

## Save, tell the players, quit; then wait for it to go. True when it went. A coroutine.
static func stop()->bool:
	if !alive():
		return true
	# the server removes the control file before it's done: wait for the process too
	var _pid:int = int(control().get("pid", "0"))
	await request("stop")
	var _tree:SceneTree = Engine.get_main_loop() as SceneTree
	var _left:float = STOP_TIMEOUT
	while _left > 0.0 && (alive() || _pid_running(_pid)):
		await _tree.create_timer(0.25).timeout
		_left -= 0.25
	return !alive() && !_pid_running(_pid)

## This pid still runs, where that can be known (ours, or any on Linux); else false.
static func _pid_running(pid:int)->bool:
	if pid <= 0:
		return false
	if pid == _spawned:
		return OS.is_process_running(pid)
	if OS.get_name() in ["Linux", "FreeBSD"]:
		return DirAccess.dir_exists_absolute("/proc/%d" % pid)
	return false

## Kill it without saving (it didn't come up).
static func stop_now()->void:
	var _pid:int = int(control().get("pid", "0"))
	if _pid > 0:
		OS.kill(_pid)
	DirAccess.remove_absolute(control_path())

## The log's last `count` lines (opened shared: the server is still writing it).
static func log_tail(count:int)->String:
	if !FileAccess.file_exists(log_path()):
		return ""
	var _lines:PackedStringArray = FileAccess.get_file_as_string(log_path()).strip_edges().split("\n")
	return "\n".join(_lines.slice(maxi(_lines.size() - count, 0)))

## The last log line containing `text` ("" if none).
static func _log_line(text:String)->String:
	if !FileAccess.file_exists(log_path()):
		return ""
	var _found:String = ""
	for _line:String in FileAccess.get_file_as_string(log_path()).split("\n"):
		if _line.contains(text):
			_found = _line.strip_edges()
	return _found
