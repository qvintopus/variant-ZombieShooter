## Runs tools/vlan/vlan_auto (.sh on Linux, .ps1 on Windows) in its --machine mode:
## no prompts, a last line "ZSVLAN key=value ..." and stable exit codes (tools/vlan/lib.sh).
## The dedicated server console (ServerConsole) and the Co-op dialog both use it.
##
## From the game (`for_game`):
## - Windows: every command except "status" needs admin. Each one goes through a UAC
##   prompt (Start-Process -Verb RunAs). Its output can't be piped back from an
##   elevated process, so vlan_auto writes it to a file too (--out), read after it exits.
##   A declined prompt is EXIT_DECLINED. The game's exe is passed with --allow (firewall).
## - Linux: ufw needs root; ZS_SUDO=pkexec gives a desktop password prompt (lib.sh).
##
## start() runs on a worker thread (vlan_auto can take a minute: installs, the tunnel,
## waiting for pings) and calls back on the main thread.
class_name VlanTool
extends RefCounted

## Exit codes (lib.sh): 0 ok, 1 usage/broken code, 2 missing, 3 wrong state, 4 timed out.
const EXIT_DECLINED:int = 5
## Commands that change nothing (no admin on Windows).
const READ_ONLY:PackedStringArray = ["status"]

## Called with (code:int, lines:PackedStringArray, result:Dictionary) on the main thread.
signal finished(code:int, lines:PackedStringArray, result:Dictionary)

var _thread:Thread
var _out_file:String = ""

## Where vlan_auto is: the project's tools/vlan, or tools/vlan next to an exported game.
static func vlan_dir()->String:
	var _name:String = "vlan_auto.ps1" if OS.get_name() == "Windows" else "vlan_auto.sh"
	for _dir:String in [ProjectSettings.globalize_path("res://tools/vlan"), OS.get_executable_path().get_base_dir().path_join("tools/vlan")]:
		if !_dir.is_empty() && FileAccess.file_exists(_dir.path_join(_name)):
			return _dir
	return ""

static func supported()->bool:
	return OS.get_name() in ["Windows", "Linux", "FreeBSD"] && !vlan_dir().is_empty()

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

## Windows, elevated: a small PowerShell that starts vlan_auto as admin (UAC), waits for it
## (not for the idle watchdog it leaves running) and returns its exit code; EXIT_DECLINED
## when the prompt was declined. vlan_auto's own arguments come in ZS_VLAN_ARGS (set by
## start), which keeps them out of the quoting of -Command.
static func elevated_command()->Array:
	var _script:String = ("try { $p = Start-Process powershell -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList $env:ZS_VLAN_ARGS; "
		+ "$null = $p.Handle; $p.WaitForExit(); exit $p.ExitCode } catch { exit %d }" % EXIT_DECLINED)
	return ["powershell", PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", _script])]

## One Windows command-line argument, quoted for Start-Process -ArgumentList.
static func _quote(text:String)->String:
	return "\"%s\"" % text.replace("\"", "")

## "ZSVLAN a=1 b=2" -> {a: "1", b: "2"}; {} when the text has no such line.
static func parse_result(output:String)->Dictionary:
	var _result:Dictionary = {}
	for _line:String in output.split("\n"):
		_line = _line.strip_edges()
		if !_line.begins_with("ZSVLAN "):
			continue
		_result = {}
		for _pair:String in _line.trim_prefix("ZSVLAN ").split(" ", false):
			var _key:String = _pair.get_slice("=", 0)
			var _value:String = _pair.substr(_pair.find("=") + 1)
			# names are the only values with escapes (space, %)
			if _key.ends_with("name") || _key == "guests":
				_value = _value.replace("%20", " ").replace("%25", "%")
			_result[_key] = _value
	return _result

## Host's "guests=3:online:Bob,4:no-reply:Ann" -> [{slot, online, name}].
static func parse_guests(text:String)->Array[Dictionary]:
	var _list:Array[Dictionary] = []
	if text.is_empty() || text == "-":
		return _list
	for _entry:String in text.split(",", false):
		var _parts:PackedStringArray = _entry.split(":")
		if _parts.size() < 2 || !_parts[0].is_valid_int():
			continue
		_list.append({"slot": int(_parts[0]), "online": _parts[1] == "online",
			"name": ":".join(_parts.slice(2)) if _parts.size() > 2 else "guest " + _parts[0]})
	return _list

## The human lines of vlan_auto's output (no ZSVLAN line, no blanks at the ends).
static func human_lines(output:String)->PackedStringArray:
	var _lines:PackedStringArray = []
	for _line:String in output.strip_edges().split("\n"):
		_line = _line.trim_suffix("\r")
		if !_line.strip_edges().begins_with("ZSVLAN "):
			_lines.append(_line)
	return _lines

## What an exit code means, for a status line.
static func exit_text(code:int)->String:
	match code:
		0: return "done"
		1: return "that code or command isn't right"
		2: return "something this PC needs is missing"
		3: return "not possible in the virtual LAN's current state"
		4: return "timed out waiting for the other PC"
		EXIT_DECLINED: return "Windows asked for admin rights and it was declined"
	return "failed (exit %d)" % code

## Windows asks for admin rights for this command (from the game).
static func needs_admin(args:PackedStringArray)->bool:
	return OS.get_name() == "Windows" && (args.is_empty() || !READ_ONLY.has(args[0]))

func busy()->bool:
	return _thread != null

## Run vlan_auto with `args` from the game: --name (the player's name) when `name` is set,
## admin/root handled as above. Ends with `finished`. False when busy or unsupported.
func start(args:PackedStringArray, name:String = "")->bool:
	if busy():
		return false
	var _argv:PackedStringArray = args.duplicate()
	if !name.is_empty():
		_argv.append_array(["--name", name])
	var _command:Array = vlan_command(_argv)
	if _command.is_empty():
		return false
	if OS.get_name() == "Windows":
		var _exe:String = OS.get_executable_path()
		_argv.append_array(["--allow", _exe])
		if needs_admin(args):
			_out_file = OS.get_user_data_dir().path_join("vlan_out_%d.txt" % (randi() % 1000000))
			var _inner:PackedStringArray = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", _quote(vlan_dir().path_join("vlan_auto.ps1"))]
			for _arg:String in _argv:
				_inner.append(_quote(_arg))
			_inner.append_array(["--machine", "--out", _quote(_out_file)])
			OS.set_environment("ZS_VLAN_ARGS", " ".join(_inner))
			_command = elevated_command()
		else:
			_command = vlan_command(_argv)
	elif OS.get_name() in ["Linux", "FreeBSD"]:
		# ufw: a desktop password prompt (polkit) instead of a sudo that can't ask
		var _desktop:bool = OS.has_environment("WAYLAND_DISPLAY") || OS.has_environment("DISPLAY")
		var _pkexec:bool = FileAccess.file_exists("/usr/bin/pkexec") || FileAccess.file_exists("/bin/pkexec")
		if _desktop && _pkexec && !OS.has_environment("ZS_SUDO"):
			OS.set_environment("ZS_SUDO", "pkexec")
	_thread = Thread.new()
	_thread.start(func ()->void:
		var _output:Array = []
		var _code:int = OS.execute(str(_command[0]), _command[1], _output, true)
		_done.call_deferred(_code, "".join(_output)))
	return true

func _done(code:int, output:String)->void:
	_thread.wait_to_finish()
	_thread = null
	if !_out_file.is_empty():
		if FileAccess.file_exists(_out_file):
			output += "\n" + FileAccess.get_file_as_string(_out_file)
			DirAccess.remove_absolute(_out_file)
		_out_file = ""
	finished.emit(code, human_lines(output), parse_result(output))

## Wait for a running command (on quit).
func wait()->void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
