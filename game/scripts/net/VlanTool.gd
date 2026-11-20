## Runs tools/vlan/vlan_auto (.sh on Linux, .ps1 on Windows) in its --machine mode:
## no prompts, a last line "ZSVLAN key=value ..." and stable exit codes (tools/vlan/lib.sh).
## The dedicated server console (ServerConsole) and the Co-op dialog both use it.
##
## From the game (`for_game`):
## - Windows: every command except "status" needs admin. Each one goes through a UAC
##   prompt (Start-Process -Verb RunAs). Its output can't be piped back from an
##   elevated process, so vlan_auto writes it to a file too (--out), read after it exits.
##   A declined prompt is EXIT_DECLINED; any other failure to start it is EXIT_LAUNCH.
##   The game's exe is passed with --allow (firewall), its subst drive resolved.
##   The script runs from a copy on the local drive (stage_dir): an elevated process doesn't
##   see subst or mapped drives of the user's session, and the copy has no odd path.
##   open_window() is the fallback: vlan_auto in a visible PowerShell window that asks for
##   admin itself and shows everything it says; the dialog's status poll picks up the result.
## - Linux: ufw needs root; ZS_SUDO=pkexec gives a desktop password prompt (lib.sh).
##
## start() runs on a worker thread (vlan_auto can take a minute: installs, the tunnel,
## waiting for pings) and calls back on the main thread.
class_name VlanTool
extends RefCounted

## Exit codes (lib.sh): 0 ok, 1 usage/broken code, 2 missing, 3 wrong state, 4 timed out.
const EXIT_DECLINED:int = 5
## Windows: the admin PowerShell couldn't be started at all (not a declined prompt).
const EXIT_LAUNCH:int = 6
## Windows: the local folder the script runs from (under %LOCALAPPDATA%).
const STAGE_NAME:String = "zs-vlan-game"
## Commands that change nothing (no admin on Windows).
const READ_ONLY:PackedStringArray = ["status"]

## Called with (code:int, lines:PackedStringArray, result:Dictionary) on the main thread.
signal finished(code:int, lines:PackedStringArray, result:Dictionary)

var _thread:Thread
var _out_file:String = ""
## The last command ran elevated and left no output at all (the admin window never ran it).
var silent:bool = false

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
			return [powershell(), _ps]
		"Linux", "FreeBSD":
			var _sh:PackedStringArray = [_dir.path_join("vlan_auto.sh")]
			_sh.append_array(_argv)
			return ["bash", _sh]
	return []

## Windows, elevated: a small PowerShell that starts vlan_auto as admin (UAC), waits for it
## (not for the idle watchdog it leaves running) and returns its exit code; EXIT_DECLINED
## when the prompt was declined (error 1223, also inside the wrapping exception), else
## EXIT_LAUNCH with the reason on a "ZS_LAUNCH" line. vlan_auto's own arguments come in
## ZS_VLAN_ARGS (set by start), which keeps them out of the quoting of -Command.
static func elevated_command()->Array:
	var _script:String = ("try { $p = Start-Process powershell -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList $env:ZS_VLAN_ARGS; "
		+ "$null = $p.Handle; $p.WaitForExit(); exit $p.ExitCode } "
		+ "catch { $e = $_.Exception; $m = $e.Message; while ($e) { if ($e.NativeErrorCode -eq 1223) { exit %d }; $e = $e.InnerException }; "
		+ "Write-Output ('ZS_LAUNCH ' + $m); exit %d }") % [EXIT_DECLINED, EXIT_LAUNCH]
	return [powershell(), PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", _script])]

## Windows PowerShell by its full path (PATH can lack it), else just "powershell".
static func powershell()->String:
	var _root:String = OS.get_environment("SystemRoot")
	var _exe:String = _root.path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	return _exe if !_root.is_empty() && FileAccess.file_exists(_exe) else "powershell"

## The local folder vlan_auto runs from on Windows: %LOCALAPPDATA%\zs-vlan-game.
static func stage_dir()->String:
	var _base:String = OS.get_environment("LOCALAPPDATA")
	if _base.is_empty():
		_base = OS.get_user_data_dir()
	return windows_path(_base.path_join(STAGE_NAME))

## Copy vlan_auto.ps1 / .cmd to stage_dir() (only when changed) and return that folder;
## vlan_dir() itself when copying fails.
static func staged_dir()->String:
	var _source:String = vlan_dir()
	if _source.is_empty():
		return ""
	var _target:String = stage_dir()
	if DirAccess.make_dir_recursive_absolute(_target) != OK && !DirAccess.dir_exists_absolute(_target):
		return _source
	for _file:String in ["vlan_auto.ps1", "vlan_auto.cmd"]:
		var _from:String = _source.path_join(_file)
		var _to:String = _target.path_join(_file)
		if !FileAccess.file_exists(_from):
			continue
		if FileAccess.file_exists(_to) && FileAccess.get_md5(_to) == FileAccess.get_md5(_from):
			continue
		if DirAccess.copy_absolute(_from, _to) != OK:
			return _source
	return _target

static func windows_path(path:String)->String:
	return path.replace("/", "\\")

## `path` with a subst drive replaced by the folder behind it, from the output of
## Windows' "subst" ("O:\: => D:\Games"); unchanged when its drive isn't one.
static func unsubst(path:String, subst_output:String)->String:
	for _line:String in subst_output.split("\n"):
		var _parts:PackedStringArray = _line.strip_edges().split(": => ")
		if _parts.size() != 2:
			continue
		var _drive:String = _parts[0].trim_suffix("\\").to_upper()
		if _drive.length() == 2 && path.to_upper().begins_with(_drive):
			return windows_path(_parts[1].trim_suffix("\\") + path.substr(2))
	return path

## The game's exe as the firewall sees it (a subst drive resolved).
static func real_exe_path()->String:
	var _exe:String = OS.get_executable_path()
	if OS.get_name() != "Windows":
		return _exe
	var _out:Array = []
	OS.execute("subst", [], _out)
	return windows_path(unsubst(_exe, "".join(_out)))

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
		EXIT_LAUNCH: return "Windows couldn't start the admin PowerShell"
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
	silent = false
	if OS.get_name() == "Windows":
		_argv.append_array(["--allow", real_exe_path()])
		if needs_admin(args):
			var _dir:String = staged_dir()
			_out_file = windows_path(stage_dir().path_join("vlan_out_%d.txt" % (randi() % 1000000)))
			var _inner:PackedStringArray = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", _quote(windows_path(_dir.path_join("vlan_auto.ps1")))]
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
		var _said:String = ""
		if FileAccess.file_exists(_out_file):
			_said = FileAccess.get_file_as_string(_out_file)
			DirAccess.remove_absolute(_out_file)
		output += "\n" + _said
		silent = code != 0 && _said.strip_edges().is_empty()
		_out_file = ""
	var _lines:PackedStringArray = []
	for _line:String in human_lines(output):
		_lines.append(_line.trim_prefix("ZS_LAUNCH "))
	if silent && code != EXIT_DECLINED && code != EXIT_LAUNCH:
		_lines.append("The admin PowerShell ended without a word (exit %d): it couldn't run the script." % code)
	finished.emit(code, _lines, parse_result(output))

## Windows: run vlan_auto with `args` in a PowerShell window of its own. It asks for admin
## itself (UAC) and keeps its admin window open, so the player sees every message. Nothing
## comes back here: the caller polls "status". False when it couldn't start.
static func open_window(args:PackedStringArray, name:String = "")->bool:
	if OS.get_name() != "Windows":
		return false
	var _dir:String = staged_dir()
	if _dir.is_empty():
		return false
	var _argv:PackedStringArray = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", windows_path(_dir.path_join("vlan_auto.ps1"))]
	_argv.append_array(args)
	if !name.is_empty():
		_argv.append_array(["--name", name])
	_argv.append_array(["--allow", real_exe_path()])
	return OS.create_process(powershell(), _argv, true) > 0

## Wait for a running command (on quit).
func wait()->void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
