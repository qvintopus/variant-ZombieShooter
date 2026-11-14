## Dedicated server console: commands typed into the server's window (or piped to its stdin), one
## per line. "help" lists them. Built in: info, stop and the virtual LAN commands; the game adds its
## own with register_command().
##
## The virtual LAN commands run tools/vlan/vlan_auto (.sh on Linux, .ps1 on Windows) in its
## --machine mode on a worker thread. Its human text is printed as is, and its last line
## ("LANPARTY key=value ...") is kept in `vlan_result`.
##
## Ctrl+C kills the process at once (Godot runs no shutdown code on SIGINT): write checkpoints as the
## game goes. "stop" is the clean way: LanPartyServer.shutdown(), then quit.
##
## --control FILE: the same commands also come over a private control channel, for the launchers'
## menu (tools/server.sh, server.cmd) and the game (LanPartyServerProcess) while the server runs in the
## background. It listens on 127.0.0.1 only, on a free port; FILE gets "key=value" lines (pid,
## control_port, token, port, started, name) and is removed on a clean stop. A request is
## "TOKEN <token>\n<command>\n"; the reply is the command's output, then the connection closes.
class_name LanPartyConsole
extends Node

## Consecutive empty reads from a pipe or file before it counts as closed.
const EOF_READS:int = 20
const CONTROL_TIMEOUT:float = 5.0

var server:LanPartyServer
## The last vlan_auto result line as key -> value ({} before the first one).
var vlan_result:Dictionary = {}
## name -> {help, call, words}: the game's commands (see register_command).
var _commands:Dictionary = {}
## The game's help lines, in the order they were registered.
var _help:PackedStringArray = []
var _reader:Thread
var _vlan_thread:Thread
var _stopping:bool
# control channel (--control)
var _control:TCPServer
var _control_file:String = ""
var _token:String = ""
## Requests being read: {peer, text, age, out}.
var _clients:Array[Dictionary] = []
## The request whose output say() also collects (null: none). Its "out" is sent back.
var _capture:Variant = null
## The request waiting for a virtual LAN command to finish.
var _vlan_client:Variant = null

## A command of the game's: `callable` gets the words typed (the command first) and prints with
## say(). `help` is its line in "help" ("name <args>   what it does"). `aliases` run it too.
func register_command(name:String, help:String, callable:Callable, aliases:PackedStringArray = [])->void:
	for _name:String in [name] + Array(aliases):
		_commands[_name.to_lower()] = callable
	if !help.is_empty():
		_help.append(help)

func help_text()->String:
	var _lines:PackedStringArray = ["commands:"]
	for _line:String in _help:
		_lines.append("  " + _line)
	_lines.append("  info                   one line for programs: INFO room=... players=... (the launcher menu)")
	_lines.append("  stop                   save, tell the players, quit (also: quit, exit)")
	_lines.append("virtual LAN (%s, this PC hosts it - server.sh --vlan):" % LanPartyConfig.vlan_brand())
	_lines.append("  invite                 the invite code (the same one for every guest)")
	_lines.append("  add <reply>            add a guest from their reply code (pasting the bare %s2. code works too)" % LanPartyConfig.reply_prefix())
	_lines.append("  guests                 guests and whether they're online")
	_lines.append("  revoke <N>             remove guest %sN" % LanPartyConfig.vlan_prefix())
	return "\n".join(_lines)

func _ready()->void:
	var _file:String = LanPartyServer.option("control")
	if !_file.is_empty():
		open_control(_file)
	# stdin only in a real server process (a test's or a game's own instance has its own stdin)
	if OS.get_stdin_type() == OS.STD_HANDLE_INVALID || !LanPartyServer.enabled():
		return
	_reader = Thread.new()
	_reader.start(_read_loop)

## Prints, and collects the text for a control request being answered.
func say(text:String)->void:
	print(text)
	if _capture != null:
		(_capture as Dictionary).out.append(text)

## Reader thread. A console blocks until Enter (an empty line reads as ""); a pipe gives what was
## written and "" over and over once it's closed.
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
	say("> " + line)
	if LanPartyConfig.is_reply_code(_words[0]):
		_vlan(["host", "add", _words[0]])
		return
	if _commands.has(_cmd):
		(_commands[_cmd] as Callable).call(_words)
		return
	match _cmd:
		"help", "?":
			say(help_text())
		"info":
			_info()
		"stop", "quit", "exit":
			stop()
		"invite":
			_vlan(["host"])
		"add":
			if _words.size() < 2:
				say("usage: add <reply code from the guest>")
			else:
				_vlan(["host", "add", _words[1]])
		"guests":
			_vlan(["status"])
		"revoke":
			if _words.size() < 2 || !_words[1].is_valid_int():
				say("usage: revoke <N>   (guest %sN, see 'guests')" % LanPartyConfig.vlan_prefix())
			else:
				_vlan(["host", "remove", _words[1]])
		_:
			say("unknown command '%s' - type help" % _cmd)

## Save, tell everyone (the server's shutdown), then quit.
func stop()->void:
	if _stopping:
		return
	_stopping = true
	say("LanPartyConsole [INFO]: stopping")
	_close_control()
	if server != null:
		await server.shutdown()
	print("LanPartyConsole [INFO]: stopped")
	get_tree().quit()

## One line for the launcher menu: "INFO key=value ... name=<name>". The name is last and may hold spaces.
func info_line()->String:
	var _pairs:PackedStringArray = []
	var _info:Dictionary = server.info() if server != null else {}
	for _key:String in _info:
		_pairs.append("%s=%s" % [_key, str(_info[_key]).replace(" ", "_")])
	return "INFO %s name=%s" % [" ".join(_pairs), server.server_name if server != null else ""]

func _info()->void:
	say(info_line())

# --- virtual LAN ------------------------------------------------------------------

func _vlan(args:PackedStringArray)->void:
	var _command:Array = LanPartyVlan.vlan_command(args)
	if _command.is_empty():
		say("virtual LAN: tools/vlan/vlan_auto isn't here, or this OS (%s) isn't supported" % OS.get_name())
		return
	if _vlan_thread != null:
		say("virtual LAN: still busy with the last command")
		return
	# a control request gets its answer once vlan_auto is done
	_vlan_client = _capture
	_vlan_thread = Thread.new()
	_vlan_thread.start(func ()->void:
		var _output:Array = []
		var _code:int = OS.execute(str(_command[0]), _command[1], _output, true)
		_vlan_done.call_deferred(_code, "".join(_output)))

func _vlan_done(code:int, output:String)->void:
	_vlan_thread.wait_to_finish()
	_vlan_thread = null
	_capture = _vlan_client
	for _line:String in LanPartyVlan.human_lines(output):
		say(_line)
	vlan_result = LanPartyVlan.parse_result(output)
	if code != 0:
		say("virtual LAN: failed (exit %d)" % code)
	_capture = null
	if _vlan_client != null:
		_answer(_vlan_client)
		_vlan_client = null

# --- control channel (--control FILE) ---------------------------------------------

## Listen on 127.0.0.1 and write the control file (--control does this; tests call it directly).
func open_control(file:String)->void:
	_control = TCPServer.new()
	var _err:Error = _control.listen(0, "127.0.0.1")
	if _err != OK:
		print("LanPartyConsole [WARN]: control channel failed (%s); the launcher menu can't reach this server" % error_string(_err))
		_control = null
		return
	_token = Crypto.new().generate_random_bytes(16).hex_encode()
	var _out:FileAccess = FileAccess.open(file, FileAccess.WRITE)
	if _out == null:
		print("LanPartyConsole [WARN]: can't write the control file %s (%s)" % [file, error_string(FileAccess.get_open_error())])
		_control.stop()
		_control = null
		return
	_out.store_string("pid=%d\ncontrol_port=%d\ntoken=%s\nport=%d\nstarted=%d\nname=%s\n" % [
		OS.get_process_id(), _control.get_local_port(), _token, server.port, server.started, server.server_name])
	_out.close()
	_control_file = file
	print("LanPartyConsole [INFO]: control channel on 127.0.0.1:%d (%s)" % [_control.get_local_port(), file])

func _close_control()->void:
	if _control == null:
		return
	_control.stop()
	_control = null
	if !_control_file.is_empty():
		DirAccess.remove_absolute(_control_file)
		_control_file = ""

func _process(delta:float)->void:
	if _control == null:
		return
	while _control.is_connection_available():
		_clients.append({"peer": _control.take_connection(), "text": "", "age": 0.0, "out": PackedStringArray()})
	for _client:Dictionary in _clients.duplicate():
		var _peer:StreamPeerTCP = _client.peer
		_peer.poll()
		_client.age += delta
		if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED || _client.age > CONTROL_TIMEOUT:
			_peer.disconnect_from_host()
			_clients.erase(_client)
			continue
		var _bytes:int = _peer.get_available_bytes()
		if _bytes > 0:
			_client.text += _peer.get_utf8_string(_bytes)
		# the token line and the command line, both ended
		if str(_client.text).count("\n") < 2:
			continue
		var _lines:PackedStringArray = str(_client.text).split("\n")
		_clients.erase(_client)
		if _lines[0].strip_edges() != "TOKEN " + _token:
			_client.out.append("bad token")
			_answer(_client)
			continue
		_capture = _client
		run(_lines[1].strip_edges())
		_capture = null
		if _vlan_client != _client:
			_answer(_client)

## Send what the request's command printed, then hang up.
func _answer(client:Dictionary)->void:
	var _peer:StreamPeerTCP = client.peer
	_peer.put_data(("\n".join(client.out) + "\n").to_utf8_buffer())
	_peer.disconnect_from_host()

func _exit_tree()->void:
	_close_control()
	if _vlan_thread != null:
		_vlan_thread.wait_to_finish()
	# a reader still blocked on a console is left to the process exit
	if _reader != null && !_reader.is_alive():
		_reader.wait_to_finish()
