## The game's own control of the virtual LAN and the dedicated server:
## - LanPartyVlan: guest list and exit codes, and a real (read-only) "vlan_auto status".
## - LanPartyLanPartyServerProcess: settings saved in the scripts' format; a server started in the
##   background (in a temp XDG_STATE_HOME, saves in a temp folder) comes up hosting, and
##   tools/server.sh sees the same one; we join it and are the main player (--main local);
##   stop saves and ends it, and the control file is gone.
## - The Co-op dialog from the title: all five tabs; Host from the title goes on to the home
##   base still hosting, and Join from the title (the server above) goes home first, then joins.
##   Godot --headless --path . res://game/tests/server_process_check.tscn
extends Node

const PORT:int = 24599
const HOME:String = "res://game/scenes/room_H00.tscn"
const TITLE:String = "res://game/scenes/title.tscn"

var failures:int = 0
var checks:int = 0
var _state_home:String
var _save_dir:String
var _saved_names:Dictionary = {}

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	for _path:String in ["res://game/resources/home_base_resource.tres", "res://game/resources/campaign_resource.tres"]:
		var _resource:SaveableResource = load(_path)
		_saved_names[_resource] = _resource.resource_name
		_resource.resource_name += "_test"
		_resource.delete_resource()
		_resource.reset_resource()
	# the boot screen registers the input actions; tests start without it
	(load("res://addons/top_down/resources/global_resources/action_resource.tres") as ActionResource).reset_resource()
	GuestSandbox.install_override = "server_process_check"
	Transition.instant = true
	get_tree().current_scene = null
	_state_home = ProjectSettings.globalize_path("user://server_process_check_%d" % OS.get_process_id())
	_save_dir = _state_home.path_join("saves")
	DirAccess.make_dir_recursive_absolute(_save_dir)
	OS.set_environment("XDG_STATE_HOME", _state_home)
	_run.call_deferred()

func _run()->void:
	_vlan_checks()
	await _vlan_status()
	await _server_checks()
	await _title_checks()
	_finish()

func _vlan_checks()->void:
	var _guests:Array[Dictionary] = LanPartyVlan.parse_guests("3:online:Big Bob,4:no-reply:Ann:x")
	check(_guests.size() == 2 && _guests[0].slot == 3 && _guests[0].online && _guests[0].name == "Big Bob"
		&& _guests[1].slot == 4 && !_guests[1].online && _guests[1].name == "Ann:x", "vlan: guest list parsed (%s)" % [_guests])
	check(LanPartyVlan.parse_guests("-").is_empty(), "vlan: no guests")
	var _result:Dictionary = LanPartyVlan.parse_result("LANPARTY role=host state=up guests=3:online:Big%20Bob\n")
	check(LanPartyVlan.parse_guests(_result.guests)[0].name == "Big Bob", "vlan: names in the guest list unescaped")
	check(LanPartyVlan.exit_text(LanPartyVlan.EXIT_DECLINED).contains("declined"), "vlan: declined admin has its own text")
	check(LanPartyVlan.exit_text(LanPartyVlan.EXIT_LAUNCH).contains("couldn't start"), "vlan: a launch failure isn't called declined")
	var _subst:String = "O:\\: => D:\\Games\\Disk\r\nP:\\: => C:\\Other\r\n"
	check(LanPartyVlan.unsubst("O:/Projects/Godot/godot.exe", _subst) == "D:\\Games\\Disk\\Projects\\Godot\\godot.exe", "vlan: a subst drive resolved (%s)" % LanPartyVlan.unsubst("O:/Projects/Godot/godot.exe", _subst))
	check(LanPartyVlan.unsubst("C:/Games/godot.exe", _subst) == "C:/Games/godot.exe", "vlan: a real drive left alone")
	check(LanPartyVlan.stage_dir().ends_with("zs-vlan-game") && (OS.get_name() != "Windows" || !LanPartyVlan.stage_dir().contains("/")), "vlan: the copy runs from a local folder (%s)" % LanPartyVlan.stage_dir())
	check(LanPartyVlan.scripts_dir().ends_with("addons/lan_party/tools/vlan") || OS.get_name() == "Windows", "vlan: run from the addon's own folder (%s)" % LanPartyVlan.scripts_dir())
	check(LanPartyVlan.human_lines("one\r\nLANPARTY a=1\ntwo\n") == PackedStringArray(["one", "two"]), "vlan: human lines without the result line")
	check(!LanPartyVlan.needs_admin(["status"]) && (LanPartyVlan.needs_admin(["host"]) == (OS.get_name() == "Windows")), "vlan: only Windows asks for admin, never for status")

## status changes nothing: safe to run for real
func _vlan_status()->void:
	if !LanPartyVlan.supported():
		return
	var _tool:LanPartyVlan = LanPartyVlan.new()
	check(_tool.start(["status"]), "vlan: status started")
	check(!_tool.start(["status"]), "vlan: one command at a time")
	var _done:Array = await _tool.finished
	check(int(_done[0]) == 0 && str(_done[2].get("role", "")) in ["none", "host", "guest"], "vlan: status answered (%s)" % [_done])

func _server_checks()->void:
	check(LanPartyServerProcess.state_dir() == _state_home.path_join("zs-server"), "server: the scripts' folder (%s)" % LanPartyServerProcess.state_dir())
	var _settings:Dictionary = LanPartyServerProcess.load_settings()
	check(_settings.port == "24565" && _settings.name == "Server", "server: default settings")
	_settings.port = str(PORT)
	_settings.name = "Proc Check"
	_settings.max_players = "4"
	LanPartyServerProcess.save_settings(_settings)
	var _text:String = FileAccess.get_file_as_string(LanPartyServerProcess.settings_path())
	check(_text.contains("port=%d\n" % PORT) && _text.contains("name=Proc Check\n") && _text.contains("max_players=4\n") && _text.contains("vlan=no\n"), "server: settings in the scripts' format")
	_settings = LanPartyServerProcess.load_settings()
	check(_settings.port == str(PORT) && _settings.name == "Proc Check" && _settings.max_players == "4", "server: settings read back")
	check(!LanPartyServerProcess.alive() && (await LanPartyServerProcess.info()).is_empty(), "server: none running yet")

	_settings.save_dir = _save_dir
	var _pid:int = LanPartyServerProcess.start(_settings)
	check(_pid > 0, "server: started (pid %d)" % _pid)
	var _problem:String = await LanPartyServerProcess.wait_ready(_pid)
	check(_problem.is_empty(), "server: up and hosting (%s)" % _problem)
	var _info:Dictionary = await LanPartyServerProcess.info()
	check(_info.get("hosting") == "1" && _info.get("port") == str(PORT) && _info.get("name") == "Proc Check" && _info.get("max") == "4"
		&& str(_info.get("main", "")).begins_with("local:"), "server: info (%s)" % [_info])
	check(int(LanPartyServerProcess.control().get("pid", "0")) == _pid, "server: the control file's pid is the one we started")
	if OS.get_name() == "Linux":
		var _sid:Array = []
		OS.execute("ps", ["-o", "sid=", "-p", str(_pid)], _sid)
		check(int("".join(_sid).strip_edges()) == _pid, "server: in its own session (sid %s)" % "".join(_sid).strip_edges())
	if OS.get_name() == "Linux":
		var _out:Array = []
		OS.execute("bash", [ProjectSettings.globalize_path("res://tools/server.sh"), "status"], _out, true)
		var _out2:Array = []
		OS.execute("bash", [ProjectSettings.globalize_path("res://addons/lan_party/tools/server.sh"), "status"], _out2, true)
		check("".join(_out2).contains("RUNNING") && "".join(_out2).contains("Proc Check") && "".join(_out2).contains("main     : local:"), "server: the addon's server.sh sees it, with the game's fields (%s)" % "".join(_out2).strip_edges())
		check("".join(_out).contains("RUNNING") && "".join(_out).contains("Proc Check"), "server: tools/server.sh sees it (%s)" % "".join(_out).strip_edges())
	# from the title, the way a player would: it goes home first, then joins
	Transition.change_scene(TITLE)
	check(await _wait(func ()->bool: return _current() == TITLE, 10.0), "join: on the title")
	var _dialog:CoopDialog = CoopDialog.open_layer()
	await _frames(2)
	_dialog.join_address("127.0.0.1:%d" % PORT)
	check(await _wait(func ()->bool: return Net.is_guest() && _current() == HOME && Net.players.local_body() != null, 30.0), "join from the title: in the server's home base")
	check(await _wait(func ()->bool: return RunSession.local_player().main, 5.0), "join: we're the main player (this PC)")
	Net.players.leaving_by_choice = true
	Net.leave()
	await _frames(10)
	check(await LanPartyServerProcess.stop(), "server: stopped")
	check(!FileAccess.file_exists(LanPartyServerProcess.control_path()), "server: control file removed")
	check(!OS.is_process_running(_pid), "server: process ended")
	check(FileAccess.file_exists(LanPartyServerProcess.log_path()) && FileAccess.get_file_as_string(LanPartyServerProcess.log_path()).contains("hosting on port %d - OK" % PORT), "server: its log")

func _title_checks()->void:
	Transition.change_scene(TITLE)
	check(await _wait(func ()->bool: return _current() == TITLE, 10.0), "title: shown")
	await _frames(4)
	var _button:Button = get_tree().current_scene.get_node_or_null("MarginContainer/Control/Body/TitleMenu/Coop/Button") as Button
	check(_button != null, "title: has a Co-op button")
	if _button == null:
		return
	_button.pressed.emit()
	await _frames(2)
	var _layer:Node = get_tree().root.get_node_or_null(CoopDialog.LAYER_NAME)
	check(_layer != null && _layer.get_child(0) is CoopDialog, "title: Co-op opens the dialog")
	if _layer == null:
		return
	var _dialog:CoopDialog = _layer.get_child(0)
	var _tabs:TabContainer = _dialog.find_children("*", "TabContainer", true, false)[0]
	check(_tabs.get_tab_count() == 4 && _tabs.get_tab_title(CoopDialog.Tab.VLAN) == "VLAN" && _tabs.get_tab_title(CoopDialog.Tab.SERVER) == "Server", "dialog: Play, Session, VLAN, Server")
	# every button has a box you can see (the game theme's own buttons are transparent)
	var _invisible:Array = []
	for _node:Node in _dialog.find_children("*", "Button", true, false):
		var _b:Button = _node as Button
		if _b is CheckBox:
			continue
		var _box:StyleBoxFlat = _b.get_theme_stylebox(&"normal") as StyleBoxFlat
		var _ghost:bool = _b.theme_type_variation in [LanPartyStyle.GHOST, LanPartyStyle.NAV]
		if !_ghost && (_box == null || (_box.bg_color.a < 0.05 && _box.border_width_bottom == 0)):
			_invisible.append(_b.text)
	check(_invisible.is_empty(), "dialog: every button is drawn as a button (%s)" % [_invisible])
	_dialog._nav[CoopDialog.Tab.SERVER].pressed.emit()
	check(_tabs.current_tab == CoopDialog.Tab.SERVER, "dialog: the rail opens the Server page")
	_dialog._nav[CoopDialog.Tab.PLAY].pressed.emit()
	check(_tabs.current_tab == CoopDialog.Tab.PLAY && _dialog._nav[CoopDialog.Tab.PLAY].button_pressed, "dialog: back to Play, marked in the rail")
	check(_button.focus_mode == Control.FOCUS_NONE, "title: the menu can't take the focus while it's open")
	_button.pressed.emit()
	await _frames(2)
	check(get_tree().root.get_children().filter(func (n:Node)->bool: return n.name.begins_with(CoopDialog.LAYER_NAME)).size() == 1, "title: pressing again opens no second one")
	_dialog._port_edit.text = str(PORT)
	_dialog._on_host_pressed()
	check(await _wait(func ()->bool: return _current() == HOME, 10.0), "host from the title: goes to the home base")
	await _frames(10)
	check(Net.is_host(), "host from the title: still hosting")
	check(get_tree().root.get_node_or_null(CoopDialog.LAYER_NAME) == null, "host from the title: the dialog closed")
	Net.leave()

func _finish()->void:
	if Net.is_online():
		Net.leave()
	if LanPartyServerProcess.alive():
		LanPartyServerProcess.stop_now()
	if failures > 0 && FileAccess.file_exists(LanPartyServerProcess.log_path()):
		printerr(FileAccess.get_file_as_string(LanPartyServerProcess.log_path()).right(3000))
	_remove_tree(_state_home)
	var _scene:Node = get_tree().current_scene
	if _scene != null:
		_scene.queue_free()
	await _frames(4)
	for _resource:SaveableResource in _saved_names:
		_resource.delete_resource()
		_resource.resource_name = _saved_names[_resource]
	print("server_process_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

static func _remove_tree(path:String)->void:
	if !DirAccess.dir_exists_absolute(path):
		return
	for _dir:String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(_dir))
	for _file:String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(_file))
	DirAccess.remove_absolute(path)

func _current()->String:
	var _scene:Node = get_tree().current_scene
	return _scene.scene_file_path if _scene != null else ""

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
