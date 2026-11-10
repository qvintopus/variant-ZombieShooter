## Dedicated server console: commands typed into the server's window (or piped
## to its stdin), one per line. "help" lists them.
##
## The virtual LAN commands run tools/vlan/vlan_auto (.sh on Linux, .ps1 on
## Windows) in its --machine mode on a worker thread. Its human text is printed
## as is, and its last line ("ZSVLAN key=value ...") is kept in `vlan_result`.
## Later the game will drive vlan_auto the same way.
##
## Ctrl+C kills the process at once (Godot runs no shutdown code on SIGINT): the
## run keeps its last checkpoint. "stop" saves first and tells the players.
class_name ServerConsole
extends Node

const HELP:String = """commands:
  status                 room, players, hidden player
  players                everyone connected: slot, name, state, address
  kick <slot> [reason]   drop a player (slot from 'players')
  home                   save the run and go back to the home base
  stop                   save, tell the players, quit (also: quit, exit)
virtual LAN (zs-vlan, this PC hosts it - tools/server.sh --vlan):
  invite                 the invite code for the next guest
  add <reply>            add a guest from their reply code (pasting the bare zsr1. code works too)
  guests                 guests and whether they're online
  revoke <N>             remove guest 10.77.0.N"""

## Consecutive empty reads from a pipe or file before it counts as closed.
const EOF_READS:int = 20

var server:DedicatedServer
## The last vlan_auto result line as key -> value ({} before the first one).
var vlan_result:Dictionary = {}
var _reader:Thread
var _vlan_thread:Thread
var _stopping:bool

func _ready()->void:
	if OS.get_stdin_type() == OS.STD_HANDLE_INVALID:
		return
	_reader = Thread.new()
	_reader.start(_read_loop)

## Reader thread. A console blocks until Enter (an empty line reads as ""); a
## pipe gives what was written and "" over and over once it's closed.
func _read_loop()->void:
	var _console:bool = OS.get_stdin_type() == OS.STD_HANDLE_CONSOLE
	var _empty:int = 0
	while true:
		var _text:String = OS.read_string_from_stdin(1024)
		if _text.strip_edges().is_empty():
			if _console:
				continue
			_empty += 1
			if _empty >= EOF_READS:
				return
			OS.delay_msec(50)
			continue
		_empty = 0
		var _quit:bool = false
		for _line:String in _text.split("\n", false):
			_line = _line.strip_edges()
			if _line.is_empty():
				continue
			run.call_deferred(_line)
			_quit = _quit || _line.get_slice(" ", 0).to_lower() in ["stop", "quit", "exit"]
		# nothing to read after stop; ending here lets the thread be joined
		if _quit:
			return

## One command line.
func run(line:String)->void:
	var _words:PackedStringArray = line.strip_edges().split(" ", false)
	if _words.is_empty():
		return
	var _cmd:String = _words[0].to_lower()
	print("> ", line)
	if _words[0].begins_with("zsr1."):
		_vlan(["host", "add", _words[0]])
		return
	match _cmd:
		"help", "?":
			print(HELP)
		"status":
			_status()
		"players":
			_list_players()
		"kick":
			_kick(_words)
		"home":
			_home()
		"stop", "quit", "exit":
			stop()
		"invite":
			_vlan(["host"])
		"add":
			if _words.size() < 2:
				print("usage: add <reply code from the guest>")
			else:
				_vlan(["host", "add", _words[1]])
		"guests":
			_vlan(["status"])
		"revoke":
			if _words.size() < 2 || !_words[1].is_valid_int():
				print("usage: revoke <N>   (guest 10.77.0.N, see 'guests')")
			else:
				_vlan(["host", "remove", _words[1]])
		_:
			print("unknown command '%s' - type help" % _cmd)

func _status()->void:
	server.print_status()
	var _vlan_ip:String = ENetTransport.vlan_address()
	print("room %s, %d player(s), %d active, port %d%s" % [
		server.current_path().get_file().get_basename(), server.players(), RunSession.players.count_active(),
		Net.port, (", VLAN %s" % _vlan_ip) if !_vlan_ip.is_empty() else ""])

func _list_players()->void:
	var _any:bool = false
	for _state:PlayerState in RunSession.players.all():
		if _state.is_local:
			continue
		_any = true
		var _what:String = "ghost (at own home base)" if _state.ghost else ("down" if _state.downed else "active")
		var _idle:String = (" idle %dm" % int(_state.idle_time / 60.0)) if _state.idle_time >= 60.0 else ""
		print("  slot %d  %-24s %-26s %s%s" % [_state.slot, _state.display_name, _what, Net.peer_address(_state.peer_id), _idle])
	if !_any:
		print("  nobody connected")

func _kick(words:PackedStringArray)->void:
	if words.size() < 2 || !words[1].is_valid_int():
		print("usage: kick <slot> [reason]   (slot from 'players')")
		return
	var _state:PlayerState = RunSession.players.get_state(int(words[1]))
	if _state == null || _state.is_local:
		print("no player in slot ", words[1])
		return
	var _reason:String = " ".join(words.slice(2)) if words.size() > 2 else "Kicked by the server"
	Net.kick(_state.slot, _reason)
	print("kicked %s (%s)" % [_state.display_name, _reason])

func _home()->void:
	if server.current_path() == DedicatedServer.HOME_SCENE:
		print("already at the home base")
		return
	RunSession.checkpoint()
	server.go_home()
	print("run saved, going home")

## Save, tell everyone, then quit (after the kick messages had time to arrive).
func stop()->void:
	if _stopping:
		return
	_stopping = true
	var _saved:bool = RunSession.checkpoint()
	print("ServerConsole [INFO]: stopping%s" % (" (run saved)" if _saved else ""))
	var _kicked:bool = false
	for _state:PlayerState in RunSession.players.all():
		if !_state.is_local:
			Net.kick(_state.slot, "The server stopped")
			_kicked = true
	if _kicked:
		await get_tree().create_timer(Net.REJECT_GRACE * 0.5).timeout
	Net.leave()
	print("ServerConsole [INFO]: stopped")
	get_tree().quit()

# --- virtual LAN ------------------------------------------------------------------

## Where vlan_auto is: the project's tools/vlan, or tools/vlan next to an exported game.
static func vlan_dir()->String:
	var _name:String = "vlan_auto.ps1" if OS.get_name() == "Windows" else "vlan_auto.sh"
	for _dir:String in [ProjectSettings.globalize_path("res://tools/vlan"), OS.get_executable_path().get_base_dir().path_join("tools/vlan")]:
		if !_dir.is_empty() && FileAccess.file_exists(_dir.path_join(_name)):
			return _dir
	return ""

## [program, arguments] to run vlan_auto with `args` in --machine mode; [] if unsupported here.
static func vlan_command(args:PackedStringArray)->Array:
	var _dir:String = vlan_dir()
	if _dir.is_empty():
		return []
	var _argv:PackedStringArray = args.duplicate()
	_argv.append("--machine")
	match OS.get_name():
		"Windows":
			var _ps:PackedStringArray = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", _dir.path_join("vlan_auto.ps1")]
			_ps.append_array(_argv)
			return ["powershell", _ps]
		"Linux", "FreeBSD":
			var _sh:PackedStringArray = [_dir.path_join("vlan_auto.sh")]
			_sh.append_array(_argv)
			return ["bash", _sh]
	return []

## "ZSVLAN a=1 b=2" -> {a: "1", b: "2"}; {} when the text has no such line.
static func parse_result(output:String)->Dictionary:
	var _result:Dictionary = {}
	for _line:String in output.split("\n"):
		_line = _line.strip_edges()
		if !_line.begins_with("ZSVLAN "):
			continue
		_result = {}
		for _pair:String in _line.trim_prefix("ZSVLAN ").split(" ", false):
			_result[_pair.get_slice("=", 0)] = _pair.substr(_pair.find("=") + 1)
	return _result

func _vlan(args:PackedStringArray)->void:
	var _command:Array = vlan_command(args)
	if _command.is_empty():
		print("virtual LAN: tools/vlan/vlan_auto isn't here, or this OS (%s) isn't supported" % OS.get_name())
		return
	if _vlan_thread != null:
		print("virtual LAN: still busy with the last command")
		return
	_vlan_thread = Thread.new()
	_vlan_thread.start(func ()->void:
		var _output:Array = []
		var _code:int = OS.execute(str(_command[0]), _command[1], _output, true)
		_vlan_done.call_deferred(_code, "".join(_output)))

func _vlan_done(code:int, output:String)->void:
	_vlan_thread.wait_to_finish()
	_vlan_thread = null
	for _line:String in output.strip_edges(false, true).split("\n"):
		if !_line.strip_edges().begins_with("ZSVLAN "):
			print(_line.trim_suffix("\r"))
	vlan_result = parse_result(output)
	if code != 0:
		print("virtual LAN: failed (exit %d)" % code)

func _exit_tree()->void:
	if _vlan_thread != null:
		_vlan_thread.wait_to_finish()
	# a reader still blocked on a console is left to the process exit
	if _reader != null && !_reader.is_alive():
		_reader.wait_to_finish()
