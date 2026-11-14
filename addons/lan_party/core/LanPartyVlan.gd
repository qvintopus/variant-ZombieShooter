## Runs tools/vlan/vlan_auto (.sh on Linux, .ps1 on Windows) in its --machine mode:
## no prompts, a last line "LANPARTY key=value ..." and stable exit codes (tools/vlan/lib.sh).
## The dedicated server console (LanPartyConsole) and the VLAN page (LanPartyVlanPage) use it.
##
## Where the scripts run from (scripts_dir):
## - the addon's own tools/vlan when it's a real folder (running from the editor or a source checkout),
##   except on Windows, see below;
## - else a copy in a local folder (stage_dir: <prefix>-vlan-game under the user's state/app-data dir),
##   written from res:// (an exported game keeps the scripts inside its .pck: export them with the
##   include filter "addons/lan_party/tools/*, lan_party.cfg") with the merged settings beside them;
## - else tools/vlan next to the executable.
##
## From the game (`start`):
## - Windows: every command except "status" needs admin. Each one goes through a UAC prompt
##   (Start-Process -Verb RunAs). Its output can't be piped back from an elevated process, so
##   vlan_auto writes it to a file too (--out), read after it exits. A declined prompt is
##   EXIT_DECLINED; any other failure to start it is EXIT_LAUNCH. The game's exe is passed with
##   --allow (firewall), its subst drive resolved. The script always runs from the local copy: an
##   elevated process doesn't see subst or mapped drives of the user's session.
##   open_window() is the fallback: vlan_auto in a visible PowerShell window that asks for admin
##   itself and shows everything it says; the page's status poll picks up the result.
## - Linux: ufw needs root; LANPARTY_SUDO=pkexec gives a desktop password prompt (lib.sh).
##
## start() runs on a worker thread (vlan_auto can take a minute: installs, the tunnel, waiting
## for pings) and calls back on the main thread.
class_name LanPartyVlan
extends RefCounted

## Exit codes (lib.sh): 0 ok, 1 usage/broken code, 2 missing, 3 wrong state, 4 timed out.
const EXIT_DECLINED:int = 5
## Windows: the admin PowerShell couldn't be started at all (not a declined prompt).
const EXIT_LAUNCH:int = 6
## The machine-readable line's tag.
const TAG:String = "LANPARTY"
const SOURCE_DIR:String = LanPartyConfig.ADDON_DIR + "/tools/vlan"
## What a copy needs (the merged lan_party.cfg is written beside them).
const SCRIPT_FILES:PackedStringArray = ["vlan_auto.sh", "lib.sh", "lp_config.sh", "vlan_auto.ps1", "vlan_auto.cmd", "lp_config.ps1"]
## Commands that change nothing (no admin on Windows).
const READ_ONLY:PackedStringArray = ["status"]

## Called with (code:int, lines:PackedStringArray, result:Dictionary) on the main thread.
signal finished(code:int, lines:PackedStringArray, result:Dictionary)

var _thread:Thread
var _out_file:String = ""
## The last command ran elevated and left no output at all (the admin window never ran it).
var silent:bool = false

static func script_name()->String:
	return "vlan_auto.ps1" if OS.get_name() == "Windows" else "vlan_auto.sh"

## The addon's tools/vlan as a real folder on disk ("" in an exported game).
static func source_dir()->String:
	var _dir:String = ProjectSettings.globalize_path(SOURCE_DIR)
	if !_dir.begins_with("res://") && FileAccess.file_exists(_dir.path_join(script_name())):
		return _dir
	return ""

## Where vlan_auto runs from (see the top); "" when the scripts aren't anywhere.
static func scripts_dir()->String:
	var _source:String = source_dir()
	if !_source.is_empty() && OS.get_name() != "Windows":
		return _source
	var _staged:String = staged_dir()
	if !_staged.is_empty():
		return _staged
	if !_source.is_empty():
		return _source
	var _beside:String = OS.get_executable_path().get_base_dir().path_join("tools/vlan")
	if FileAccess.file_exists(_beside.path_join(script_name())):
		return _beside
	return ""

static func supported()->bool:
	return OS.get_name() in ["Windows", "Linux", "FreeBSD"] && !scripts_dir().is_empty()

## [program, arguments] to run vlan_auto with `args` in --machine mode; [] if unsupported here.
static func vlan_command(args:PackedStringArray)->Array:
	var _dir:String = scripts_dir()
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
## EXIT_LAUNCH with the reason on a "LANPARTY_LAUNCH" line. vlan_auto's own arguments come in
## LANPARTY_VLAN_ARGS (set by start), which keeps them out of the quoting of -Command.
static func elevated_command()->Array:
	var _script:String = ("try { $p = Start-Process powershell -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList $env:LANPARTY_VLAN_ARGS; "
		+ "$null = $p.Handle; $p.WaitForExit(); exit $p.ExitCode } "
		+ "catch { $e = $_.Exception; $m = $e.Message; while ($e) { if ($e.NativeErrorCode -eq 1223) { exit %d }; $e = $e.InnerException }; "
		+ "Write-Output ('LANPARTY_LAUNCH ' + $m); exit %d }") % [EXIT_DECLINED, EXIT_LAUNCH]
	return [powershell(), PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", _script])]

## Windows PowerShell by its full path (PATH can lack it), else just "powershell".
static func powershell()->String:
	var _root:String = OS.get_environment("SystemRoot")
	var _exe:String = _root.path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	return _exe if !_root.is_empty() && FileAccess.file_exists(_exe) else "powershell"

## Tests point this somewhere of their own ("" = the usual place).
static var stage_override:String = ""

## The local folder the copy runs from: %LOCALAPPDATA%\<prefix>-vlan-game on Windows,
## <state>/<prefix>-vlan-game elsewhere.
static func stage_dir()->String:
	if !stage_override.is_empty():
		return stage_override
	var _name:String = LanPartyConfig.vlan_brand() + "-game"
	if OS.get_name() == "Windows":
		var _base:String = OS.get_environment("LOCALAPPDATA")
		if _base.is_empty():
			_base = OS.get_user_data_dir()
		return windows_path(_base.path_join(_name))
	return LanPartyConfig.state_home().path_join(_name)

## Copy the scripts from res:// and the merged settings to stage_dir() (only what changed) and
## return that folder; "" when the scripts aren't in res:// or copying fails.
static func staged_dir()->String:
	if !FileAccess.file_exists(SOURCE_DIR.path_join(script_name())):
		return ""
	var _target:String = stage_dir()
	if DirAccess.make_dir_recursive_absolute(_target) != OK && !DirAccess.dir_exists_absolute(_target):
		return ""
	for _file:String in SCRIPT_FILES:
		var _from:String = SOURCE_DIR.path_join(_file)
		if FileAccess.file_exists(_from) && !_write_if_changed(_target.path_join(_file), FileAccess.get_file_as_bytes(_from)):
			return ""
	if !_write_if_changed(_target.path_join("lan_party.cfg"), LanPartyConfig.as_text().to_utf8_buffer()):
		return ""
	return _target

static func _write_if_changed(path:String, bytes:PackedByteArray)->bool:
	if FileAccess.file_exists(path) && FileAccess.get_file_as_bytes(path) == bytes:
		return true
	var _file:FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		return false
	_file.store_buffer(bytes)
	_file.close()
	return true

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

## "LANPARTY a=1 b=2" -> {a: "1", b: "2"}; {} when the text has no such line.
static func parse_result(output:String)->Dictionary:
	var _result:Dictionary = {}
	for _line:String in output.split("\n"):
		_line = _line.strip_edges()
		if !_line.begins_with(TAG + " "):
			continue
		_result = {}
		for _pair:String in _line.trim_prefix(TAG + " ").split(" ", false):
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

## The human lines of vlan_auto's output (no result line, no blanks at the ends).
static func human_lines(output:String)->PackedStringArray:
	var _lines:PackedStringArray = []
	for _line:String in output.strip_edges().split("\n"):
		_line = _line.trim_suffix("\r")
		if !_line.strip_edges().begins_with(TAG + " "):
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
			var _dir:String = scripts_dir()
			_out_file = windows_path(stage_dir().path_join("vlan_out_%d.txt" % (randi() % 1000000)))
			var _inner:PackedStringArray = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", _quote(windows_path(_dir.path_join("vlan_auto.ps1")))]
			for _arg:String in _argv:
				_inner.append(_quote(_arg))
			_inner.append_array(["--machine", "--out", _quote(_out_file)])
			OS.set_environment("LANPARTY_VLAN_ARGS", " ".join(_inner))
			_command = elevated_command()
		else:
			_command = vlan_command(_argv)
	elif OS.get_name() in ["Linux", "FreeBSD"]:
		# ufw: a desktop password prompt (polkit) instead of a sudo that can't ask
		var _desktop:bool = OS.has_environment("WAYLAND_DISPLAY") || OS.has_environment("DISPLAY")
		var _pkexec:bool = FileAccess.file_exists("/usr/bin/pkexec") || FileAccess.file_exists("/bin/pkexec")
		if _desktop && _pkexec && !OS.has_environment("LANPARTY_SUDO"):
			OS.set_environment("LANPARTY_SUDO", "pkexec")
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
		_lines.append(_line.trim_prefix(TAG + "_LAUNCH "))
	if silent && code != EXIT_DECLINED && code != EXIT_LAUNCH:
		_lines.append("The admin PowerShell ended without a word (exit %d): it couldn't run the script." % code)
	finished.emit(code, _lines, parse_result(output))

## Windows: run vlan_auto with `args` in a PowerShell window of its own. It asks for admin
## itself (UAC) and keeps its admin window open, so the player sees every message. Nothing
## comes back here: the caller polls "status". False when it couldn't start.
static func open_window(args:PackedStringArray, name:String = "")->bool:
	if OS.get_name() != "Windows":
		return false
	var _dir:String = scripts_dir()
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
