## LAN Party's own checks; needs nothing but the addon (it runs the same in any project):
## settings and their override, code prefixes, vlan_auto's result line and exit codes, the
## copy of the scripts for exported games, the server's options, and its console with the control
## channel, answered in this very process the way the launchers and LanPartyServerProcess ask.
## It never changes the network: the only script it runs is "vlan_auto status", when supported.
##   godot --headless --path . res://addons/lan_party/tests/lan_party_check.tscn
extends Node

## A server for the console to serve: one command of its own, fixed info.
class StubServer extends LanPartyServer:
	var said:Array = []
	func _server_ready()->void:
		console.register_command("hello", "hello <name>           says hello", func (words:PackedStringArray)->void:
			said.append(words)
			console.say("hello " + " ".join(words.slice(1))))
	func players()->int:
		return 2
	func is_hosting()->bool:
		return true
	func place()->String:
		return "test_room"
	func info_fields()->Dictionary:
		return {"mode": "stub"}

var failures:int = 0
var checks:int = 0
var _temp:String

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	_temp = ProjectSettings.globalize_path("user://lan_party_check_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_temp)
	_run.call_deferred()

func _run()->void:
	_config_checks()
	_vlan_checks()
	_stage_checks()
	await _vlan_status()
	_option_checks()
	await _console_checks()
	_finish()

func _config_checks()->void:
	var _file:String = _temp.path_join("override.cfg")
	_write(_file, "# a comment\nprefix = tst  # trailing\ngame_port=4321\nBad Key=1\ncode_prefix=tq\nextra_settings=main:first,local; speed:slow,fast\n")
	var _read:Dictionary = LanPartyConfig.read_file(_file)
	check(_read.get("prefix") == "tst" && _read.get("game_port") == "4321" && !_read.has("Bad Key"), "config: parsed, comments and bad keys skipped (%s)" % _read)
	var _before:String = LanPartyConfig.prefix()
	OS.set_environment("LANPARTY_CONFIG", _file)
	LanPartyConfig.reload()
	check(LanPartyConfig.prefix() == "tst" && LanPartyConfig.game_port() == 4321, "config: LANPARTY_CONFIG wins")
	check(LanPartyConfig.invite_prefix() == "tqi" && LanPartyConfig.is_invite_code("tqi2.QUJD") && LanPartyConfig.is_reply_code("tqr1.x") && !LanPartyConfig.is_reply_code("tqi2.x"), "config: code prefixes")
	var _extra:Array[Dictionary] = LanPartyConfig.extra_settings()
	check(_extra.size() == 2 && _extra[0].name == "main" && _extra[1].choices == PackedStringArray(["slow", "fast"]), "config: extra settings (%s)" % [_extra])
	check(LanPartyServerProcess.defaults().get("speed") == "slow" && LanPartyServerProcess.defaults().get("port") == "4321", "config: server defaults follow it")
	check(LanPartyConfig.as_text().contains("prefix=tst\n"), "config: merged text for a copy")
	OS.unset_environment("LANPARTY_CONFIG")
	LanPartyConfig.reload()
	check(LanPartyConfig.prefix() == _before, "config: back without the override")
	check(LanPartyConfig.clean_name("  Big \t  Bob\n ") == "Big Bob" && LanPartyConfig.clean_name("x".repeat(40)).length() == LanPartyConfig.MAX_NAME_LENGTH, "config: names cleaned like the scripts do")

func _vlan_checks()->void:
	var _result:Dictionary = LanPartyVlan.parse_result("text\nLANPARTY role=host state=up guests=3:online:Big%20Bob,4:no-reply:Ann name=A%25B\n")
	check(_result.get("role") == "host" && _result.get("name") == "A%B", "vlan: result line parsed (%s)" % _result)
	var _guests:Array[Dictionary] = LanPartyVlan.parse_guests(_result.guests)
	check(_guests.size() == 2 && _guests[0].name == "Big Bob" && _guests[0].online && !_guests[1].online, "vlan: guests (%s)" % [_guests])
	check(LanPartyVlan.parse_result("nothing here").is_empty(), "vlan: no result line, no result")
	check(LanPartyVlan.human_lines("one\r\nLANPARTY a=1\ntwo\n") == PackedStringArray(["one", "two"]), "vlan: human lines")
	check(LanPartyVlan.exit_text(LanPartyVlan.EXIT_DECLINED).contains("declined") && LanPartyVlan.exit_text(4).contains("timed out"), "vlan: exit texts")
	check(LanPartyVlan.unsubst("O:/Games/x.exe", "O:\\: => D:\\Disk\r\n") == "D:\\Disk\\Games\\x.exe", "vlan: subst drive resolved")
	check(!LanPartyVlan.needs_admin(["status"]), "vlan: status never needs admin")
	var _command:Array = LanPartyVlan.vlan_command(["status"])
	check(_command.is_empty() || PackedStringArray(_command[1])[-1] == "--machine", "vlan: --machine mode (%s)" % [_command])

## The copy an exported game runs: every script plus the merged settings, rewritten only when changed.
func _stage_checks()->void:
	LanPartyVlan.stage_override = _temp.path_join("stage")
	var _dir:String = LanPartyVlan.staged_dir()
	check(_dir == LanPartyVlan.stage_override, "stage: copied (%s)" % _dir)
	var _all:bool = true
	for _file:String in LanPartyVlan.SCRIPT_FILES:
		_all = _all && FileAccess.get_file_as_bytes(_dir.path_join(_file)) == FileAccess.get_file_as_bytes(LanPartyVlan.SOURCE_DIR.path_join(_file))
	check(_all, "stage: every script, byte for byte")
	check(FileAccess.get_file_as_string(_dir.path_join("lan_party.cfg")) == LanPartyConfig.as_text(), "stage: the merged settings beside them")
	var _stamp:int = FileAccess.get_modified_time(_dir.path_join("vlan_auto.sh"))
	_write(_dir.path_join("lib.sh"), "changed")
	LanPartyVlan.staged_dir()
	check(FileAccess.get_file_as_bytes(_dir.path_join("lib.sh")) == FileAccess.get_file_as_bytes(LanPartyVlan.SOURCE_DIR.path_join("lib.sh")) && FileAccess.get_modified_time(_dir.path_join("vlan_auto.sh")) == _stamp,
		"stage: a changed file is put back, the rest left alone")
	if OS.get_name() in ["Linux", "FreeBSD"]:
		# the copy reads its own settings: no project.godot above it
		# (a script file: OS.execute can hand its arguments through a shell that eats quotes)
		var _probe:String = _temp.path_join("probe.sh")
		_write(_probe, ". \"$1/lib.sh\"\necho \"$NAME $NET $GAME_PORT $CI\"\n")
		var _out:Array = []
		OS.execute("bash", [_probe, _dir], _out, true)
		var _expect:String = "%s %s %d %s" % [LanPartyConfig.get_value("vlan_name"), LanPartyConfig.get_value("vlan_net"), LanPartyConfig.game_port(), LanPartyConfig.invite_prefix()]
		check("".join(_out).strip_edges() == _expect, "stage: the copy's scripts use the game's names (%s, want %s)" % ["".join(_out).strip_edges(), _expect])
	LanPartyVlan.stage_override = ""

## status changes nothing: safe to run for real
func _vlan_status()->void:
	if !LanPartyVlan.supported() || OS.get_name() == "Windows":
		return
	var _tool:LanPartyVlan = LanPartyVlan.new()
	check(_tool.start(["status"]), "vlan: status started")
	var _done:Array = await _tool.finished
	check(int(_done[0]) == 0 && str(_done[2].get("role", "")) in ["none", "host", "guest"], "vlan: status answered (%s)" % [_done])

func _option_checks()->void:
	var _options:Dictionary = LanPartyServer.parse_args(["--server", "--port", "4000", "--vlan", "--name", "My Server", "--nope", "x", "--control"])
	check(_options.get("server") == true && _options.get("port") == "4000" && _options.get("vlan") == true && _options.get("name") == "My Server", "server: options parsed (%s)" % _options)
	check(!_options.has("nope") && !_options.has("control"), "server: unknown options and a missing value skipped")
	LanPartyServer.register_option("--speed", true)
	check(LanPartyServer.parse_args(["--speed", "fast"]).get("speed") == "fast", "server: a game option registered")
	check(!LanPartyServer.enabled(), "server: not a server without --server")

func _console_checks()->void:
	var _server:StubServer = StubServer.new()
	add_child(_server)
	await get_tree().process_frame
	var _console:LanPartyConsole = _server.console
	check(_console != null && _console.is_inside_tree(), "console: made by the server")
	check(_console.help_text().contains("hello <name>") && _console.help_text().contains("invite") && _console.help_text().contains("stop"), "console: help lists the game's and its own commands")
	_console.run("HELLO there")
	check(_server.said.size() == 1 && _server.said[0][1] == "there", "console: the game's command ran, any case")
	var _line:String = _console.info_line()
	check(_line.begins_with("INFO room=test_room players=2 ") && _line.contains(" mode=stub ") && _line.contains(" hosting=1 ") && _line.ends_with(" name=" + _server.server_name), "console: info line (%s)" % _line)
	# the control channel, asked the way LanPartyServerProcess asks
	OS.set_environment("LANPARTY_SERVER_DIR", _temp.path_join("server"))
	DirAccess.make_dir_recursive_absolute(LanPartyServerProcess.state_dir())
	_console.open_control(LanPartyServerProcess.control_path())
	var _control:Dictionary = LanPartyServerProcess.control()
	check(int(_control.get("pid", "0")) == OS.get_process_id() && str(_control.get("token", "")).length() == 32, "control: file written (%s)" % [_control.keys()])
	check(LanPartyServerProcess.alive(), "control: the server counts as running")
	var _info:Dictionary = LanPartyServerProcess.parse_info(await LanPartyServerProcess.request("info"))
	check(_info.get("room") == "test_room" && _info.get("players") == "2" && _info.get("hosting") == "1" && _info.get("name") == _server.server_name, "control: info answered (%s)" % _info)
	var _hello:String = await LanPartyServerProcess.request("hello control")
	check(_hello == "hello control", "control: a game command answered (%s)" % _hello)
	var _token:String = str(_control.token)
	_write(LanPartyServerProcess.control_path(), FileAccess.get_file_as_string(LanPartyServerProcess.control_path()).replace(_token, "0".repeat(32)))
	check((await LanPartyServerProcess.request("info")) == "bad token", "control: a wrong token is refused")
	_write(LanPartyServerProcess.control_path(), FileAccess.get_file_as_string(LanPartyServerProcess.control_path()).replace("0".repeat(32), _token))
	_server.queue_free()
	await get_tree().process_frame
	check(!FileAccess.file_exists(LanPartyServerProcess.control_path()), "control: file removed when the server goes")
	OS.unset_environment("LANPARTY_SERVER_DIR")

func _finish()->void:
	_remove_tree(_temp)
	print("lan_party_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

static func _write(path:String, text:String)->void:
	var _file:FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_file.store_string(text)
	_file.close()

static func _remove_tree(path:String)->void:
	if !DirAccess.dir_exists_absolute(path):
		return
	for _dir:String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(_dir))
	for _file:String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(_file))
	DirAccess.remove_absolute(path)
