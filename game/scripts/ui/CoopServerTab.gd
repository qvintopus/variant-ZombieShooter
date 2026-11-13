## Co-op dialog, "Server" tab: a dedicated server on this PC, run by the game in the
## background (ServerProcess). It keeps running when the game closes (the quit prompt
## asks), and tools/server.sh / server.cmd see and control the same one.
## Start brings it up with the settings below and joins it: this PC's player is the main
## player (the plumber). Friends join this PC's address, or 10.77.0.1 over the virtual LAN.
extends ScrollContainer

const POLL:float = 3.0

var dialog:CoopDialog
var _state_label:Label
var _settings_box:VBoxContainer
var _name_edit:LineEdit
var _max_spin:SpinBox
var _idle_edit:LineEdit
var _vlan_box:CheckBox
var _start_button:Button
var _join_button:Button
var _stop_button:Button
var _note:Label
## The running server's info ({} when none answers).
var info:Dictionary = {}
var _running:bool
var _busy:String = ""
var _poll_left:float

func _ready()->void:
	name = "Server"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	custom_minimum_size = Vector2(0, 130)
	var _box:VBoxContainer = VBoxContainer.new()
	_box.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(_box)
	_state_label = CoopDialog.make_label("")
	_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_state_label)

	var _settings:Dictionary = ServerProcess.load_settings()
	_settings_box = VBoxContainer.new()
	_box.add_child(_settings_box)
	_name_edit = CoopDialog.make_edit(str(_settings.name), "Server")
	_name_edit.max_length = Net.MAX_NAME_LENGTH
	_settings_box.add_child(_labelled("Name", _name_edit))
	_max_spin = SpinBox.new()
	_max_spin.min_value = 2
	_max_spin.max_value = Net.MAX_PLAYERS
	_max_spin.value = int(_settings.max_players)
	_settings_box.add_child(_labelled("Players", _max_spin))
	_idle_edit = CoopDialog.make_edit(str(_settings.idle_kick), "5")
	_idle_edit.max_length = 4
	_idle_edit.tooltip_text = "Minutes before an idle guest is dropped (0 keeps everyone)"
	_settings_box.add_child(_labelled("Idle kick min", _idle_edit))
	_vlan_box = CheckBox.new()
	_vlan_box.text = "Over the virtual LAN"
	_vlan_box.tooltip_text = "Friends in your virtual LAN (VLAN tab, host one first) join at 10.77.0.1"
	_vlan_box.button_pressed = _settings.vlan == "yes"
	_settings_box.add_child(_vlan_box)

	var _buttons:HBoxContainer = HBoxContainer.new()
	_box.add_child(_buttons)
	_start_button = CoopDialog.make_button("Start and join", _on_start)
	_buttons.add_child(_start_button)
	_join_button = CoopDialog.make_button("Join it", _on_join)
	_buttons.add_child(_join_button)
	_stop_button = CoopDialog.make_button("Stop", _on_stop)
	_buttons.add_child(_stop_button)
	_buttons.add_child(CoopDialog.make_button("Log", func ()->void:
		if FileAccess.file_exists(ServerProcess.log_path()):
			OS.shell_open(ServerProcess.log_path())
		else:
			OS.shell_open(ServerProcess.state_dir())))
	_note = CoopDialog.make_label("")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_note)
	Net.state_changed.connect(_refresh)
	_refresh()

func _process(delta:float)->void:
	if !is_visible_in_tree() || !_busy.is_empty():
		return
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = POLL
		_poll()

func _poll()->void:
	_running = ServerProcess.alive()
	info = await ServerProcess.info() if _running else {}
	if is_inside_tree():
		_refresh()

## Running (by its process) and what it said last.
func running()->bool:
	return _running

func _refresh()->void:
	if !is_inside_tree():
		return
	var _offline:bool = Net.state == Net.State.OFFLINE
	_settings_box.visible = !_running
	_start_button.visible = !_running
	_start_button.disabled = !_busy.is_empty() || !_offline
	_join_button.visible = _running
	_join_button.disabled = !_busy.is_empty() || !_offline || info.is_empty()
	_stop_button.visible = _running
	_stop_button.disabled = !_busy.is_empty()
	var _vlan_ok:bool = dialog != null && dialog.vlan_hosting()
	_vlan_box.disabled = !_vlan_ok && !_vlan_box.button_pressed
	if !_busy.is_empty():
		_state_label.text = _busy + "..."
	elif !_running:
		_state_label.text = "Dedicated server: not running. It runs in the background on this PC, hidden; you join it like a friend does." + ("" if _offline else "\n(leave this session to start one)")
	elif info.is_empty():
		_state_label.text = "Dedicated server: running, starting up or busy"
	else:
		_state_label.text = "Dedicated server \"%s\": running %s - %s, %s of %s players, port %s%s" % [
			info.get("name", ""), _duration(int(info.get("up", "0"))), _room_name(str(info.get("room", ""))),
			info.get("players", "?"), info.get("max", "?"), info.get("port", "?"),
			", VLAN " + str(info.vlan) if str(info.get("vlan", "-")) != "-" else ""]

func _on_start()->void:
	if !_busy.is_empty() || Net.state != Net.State.OFFLINE:
		return
	if ServerProcess.alive():
		_note.text = "A server is already running on this PC"
		_poll()
		return
	var _settings:Dictionary = ServerProcess.load_settings()
	var _name:String = Net._clean_name(_name_edit.text)
	_settings.name = _name if !_name.is_empty() else "Server"
	_settings.max_players = str(int(_max_spin.value))
	_settings.idle_kick = str(maxf(float(_idle_edit.text), 0.0)) if _idle_edit.text.is_valid_float() else "5"
	_settings.vlan = "yes" if _vlan_box.button_pressed else "no"
	if _settings.vlan == "yes" && (dialog == null || !dialog.vlan_hosting()):
		_note.text = "Host the virtual LAN first (VLAN tab), or untick it"
		return
	ServerProcess.save_settings(_settings)
	_busy = "Starting the server"
	_note.text = ""
	_refresh()
	var _pid:int = ServerProcess.start(_settings)
	var _problem:String = "couldn't start Godot" if _pid <= 0 else await ServerProcess.wait_ready(_pid)
	_busy = ""
	PlaytestLog.event("net", {"dedicated_server": "start", "result": _problem if !_problem.is_empty() else "up"})
	if !is_inside_tree():
		return
	if !_problem.is_empty():
		_note.text = "Not started: " + _problem
		_poll()
		return
	_note.text = "Server is up, joining it"
	await _poll()
	_on_join()

func _on_join()->void:
	if Net.state != Net.State.OFFLINE || dialog == null:
		return
	var _port:int = int(info.get("port", str(Net.DEFAULT_PORT)))
	dialog.join_address("127.0.0.1" if _port == Net.DEFAULT_PORT else "127.0.0.1:%d" % _port)

func _on_stop()->void:
	if !_busy.is_empty():
		return
	_busy = "Stopping the server (the run is saved)"
	_refresh()
	var _gone:bool = await ServerProcess.stop()
	_busy = ""
	if !is_inside_tree():
		return
	_note.text = "Server stopped" if _gone else "The server didn't stop; see its log"
	_poll()

func _labelled(text:String, control:Control)->HBoxContainer:
	var _row:HBoxContainer = HBoxContainer.new()
	var _label:Label = CoopDialog.make_label(text)
	_label.custom_minimum_size = Vector2(60, 0)
	_row.add_child(_label)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	_row.add_child(control)
	return _row

static func _duration(seconds:int)->String:
	if seconds >= 3600:
		return "%dh %dm" % [seconds / 3600, seconds % 3600 / 60]
	if seconds >= 60:
		return "%dm" % (seconds / 60)
	return "%ds" % seconds

static func _room_name(room:String)->String:
	match room:
		"room_H00": return "home base"
		"": return "starting"
	return room.trim_prefix("room_")
