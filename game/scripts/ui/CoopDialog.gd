## Modal co-op dialog, opened by the home base Comms Terminal and the title's Co-op button
## (open_layer). Offline it shows Host (pick a port, open to friends) and Join (type ip[:port]
## or pick a recent host). Once a session is open the Session tab replaces them, and it
## opens by itself: what to tell a friend (with Copy), everyone in the session (the host
## can kick) and Leave session. Always there: VLAN (the zs-vlan virtual LAN, CoopVlanTab)
## and Server (a dedicated server on this PC, CoopServerTab).
## Hosting or joining from the title goes on to the home base (a host on the title leaves its
## session; a guest lends the host a gun from its own home base).
## Built in code so it follows game_gui_theme; it consumes Escape before the
## pause menu sees it and does not freeze the room (the session keeps running).
class_name CoopDialog
extends Control

const LAYER_NAME:String = "CoopDialogLayer"
const HOME_SCENE:String = "res://game/scenes/room_H00.tscn"
const TITLE_SCENE:String = "res://game/scenes/title.tscn"

const THEME_PATH:String = "res://addons/top_down/resources/theme/game_gui_theme.theme"
const SETTINGS_PATH:String = "res://game/resources/net_settings.tres"
const FONT_SIZE:int = 8
enum Tab {HOST, JOIN, SESSION, VLAN, SERVER}

var _settings:NetSettings
var _status:Label
var _tabs:TabContainer
var _host_button:Button
var _port_edit:LineEdit
var _share:VBoxContainer
var _roster:VBoxContainer
var _players_title:Label
var _shown_state:int = -1
var _session_scroll:ScrollContainer
var _address_edit:LineEdit
var _name_edit:LineEdit
## "Use VLAN name: X": shown when this PC's zs-vlan name differs from a name the player picked.
var _vlan_name_button:Button
var _connect_button:Button
var _recent:VBoxContainer
var _leave_button:Button
var _vlan_tab:Node
var _server_tab:Node

## The dialog on its own layer at the root (above the HUD, below Transition), or the one
## already open. It frees the layer when it closes.
static func open_layer()->CoopDialog:
	var _tree:SceneTree = Engine.get_main_loop() as SceneTree
	var _old:Node = _tree.root.get_node_or_null(LAYER_NAME)
	if _old != null && !_old.is_queued_for_deletion() && _old.get_child_count() > 0:
		return _old.get_child(0) as CoopDialog
	var _layer:CanvasLayer = CanvasLayer.new()
	_layer.layer = 4
	_layer.name = LAYER_NAME
	var _dialog:CoopDialog = CoopDialog.new()
	_layer.add_child(_dialog)
	_tree.root.add_child(_layer)
	_dialog.tree_exited.connect(func ()->void:
		if is_instance_valid(_layer):
			_layer.queue_free(), CONNECT_ONE_SHOT)
	return _dialog

static func make_label(text:String)->Label:
	var _l:Label = Label.new()
	_l.text = text
	return _l

static func make_edit(text:String, placeholder:String)->LineEdit:
	var _edit:LineEdit = LineEdit.new()
	_edit.text = text
	_edit.placeholder_text = placeholder
	_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	return _edit

static func make_button(text:String, callback:Callable)->Button:
	var _b:Button = Button.new()
	_b.text = text
	_b.pressed.connect(callback)
	return _b

func _ready()->void:
	_settings = load(SETTINGS_PATH)
	_settings.load_resource()
	theme = _small_theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_build()
	Net.state_changed.connect(_refresh)
	Net.roster_changed.connect(_refresh)
	Net.connection_failed.connect(_on_failed)
	Net.session_ended.connect(_on_ended)
	Net.share_addresses_ready.connect(func (_list:Array)->void: _refresh())
	_refresh()
	_focus_first.call_deferred()

func _build()->void:
	var _dim:ColorRect = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_dim)

	var _center:CenterContainer = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_center)
	var _panel:PanelContainer = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(220, 0)
	_center.add_child(_panel)
	var _margin:MarginContainer = MarginContainer.new()
	for _side:String in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + _side, 6)
	_panel.add_child(_margin)
	var _box:VBoxContainer = VBoxContainer.new()
	_margin.add_child(_box)

	var _title:Label = Label.new()
	_title.text = "CO-OP"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_title)

	var _name_row:HBoxContainer = HBoxContainer.new()
	_box.add_child(_name_row)
	_name_row.add_child(_label("Name"))
	# a name the player never picked follows this PC's zs-vlan name (it may be new)
	if RunSession.profile.refresh_default() && Net.state == Net.State.OFFLINE:
		RunSession.local_player().display_name = RunSession.profile.display_name
	_name_edit = _line_edit(RunSession.profile.display_name, PlayerProfile.default_name())
	_name_edit.max_length = Net.MAX_NAME_LENGTH
	_name_edit.text_changed.connect(_on_name_changed)
	_name_row.add_child(_name_edit)
	_vlan_name_button = _button("", func ()->void:
		_name_edit.text = ENetTransport.vlan_name()
		_on_name_changed(_name_edit.text))
	_vlan_name_button.name = "UseVlanName"
	_name_row.add_child(_vlan_name_button)
	_update_vlan_name_button()

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 90)
	_box.add_child(_tabs)

	# Host tab
	var _host:VBoxContainer = VBoxContainer.new()
	_host.name = "Host"
	_tabs.add_child(_host)
	var _port_row:HBoxContainer = HBoxContainer.new()
	_host.add_child(_port_row)
	_port_row.add_child(_label("Port"))
	_port_edit = _line_edit(str(_settings.host_port), str(Net.DEFAULT_PORT))
	_port_edit.max_length = 5
	_port_row.add_child(_port_edit)
	_host_button = _button("Open to friends", _on_host_pressed)
	_host.add_child(_host_button)

	# Join tab
	var _join:VBoxContainer = VBoxContainer.new()
	_join.name = "Join"
	_tabs.add_child(_join)
	_address_edit = _line_edit(_settings.recent_hosts[0] if !_settings.recent_hosts.is_empty() else "", "ip or ip:port")
	_address_edit.text_submitted.connect(func (_text:String)->void: _on_connect_pressed())
	_join.add_child(_address_edit)
	_connect_button = _button("Connect", _on_connect_pressed)
	_join.add_child(_connect_button)
	_recent = VBoxContainer.new()
	_join.add_child(_recent)

	# Session tab (while hosting or joined)
	var _scroll:ScrollContainer = ScrollContainer.new()
	_scroll.name = "Session"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 130)
	_tabs.add_child(_scroll)
	_session_scroll = _scroll
	var _session:VBoxContainer = VBoxContainer.new()
	_session.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.add_child(_session)
	_players_title = _label("")
	_session.add_child(_players_title)
	_roster = VBoxContainer.new()
	_session.add_child(_roster)
	_session.add_child(HSeparator.new())
	_share = VBoxContainer.new()
	_session.add_child(_share)
	_leave_button = _button("Leave session", _on_leave_pressed)
	_session.add_child(_leave_button)

	# the virtual LAN and the dedicated server: there in every state
	_vlan_tab = (load("res://game/scripts/ui/CoopVlanTab.gd") as GDScript).new()
	_vlan_tab.dialog = self
	_tabs.add_child(_vlan_tab)
	_server_tab = (load("res://game/scripts/ui/CoopServerTab.gd") as GDScript).new()
	_server_tab.dialog = self
	_tabs.add_child(_server_tab)

	# playtest log: a file a tester can send (PlaytestLog)
	var _log_row:HBoxContainer = HBoxContainer.new()
	_box.add_child(_log_row)
	var _log_box:CheckBox = CheckBox.new()
	_log_box.text = "Playtest log"
	_log_box.button_pressed = _settings.playtest_log || PlaytestLog.is_on()
	_log_box.tooltip_text = "Writes a log of the session (network, rooms, fights, errors) to share with the developer"
	_log_box.toggled.connect(_on_playtest_log_toggled)
	_log_row.add_child(_log_box)
	_log_row.add_child(_button("Log folder", _open_log_folder))

	_status = _label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_status)
	var _buttons:HBoxContainer = HBoxContainer.new()
	_buttons.add_theme_constant_override(&"separation", 12)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(_buttons)
	_buttons.add_child(_button("Close", close))

## The game theme at a size that fits a form into the 480x270 viewport.
func _small_theme()->Theme:
	var _theme:Theme = (load(THEME_PATH) as Theme).duplicate()
	_theme.default_font_size = FONT_SIZE
	for _type:StringName in [&"Label", &"Button", &"LineEdit", &"TabContainer", &"TabBar"]:
		_theme.set_font_size(&"font_size", _type, FONT_SIZE)
	return _theme

func _label(text:String)->Label:
	return make_label(text)

func _line_edit(text:String, placeholder:String)->LineEdit:
	return make_edit(text, placeholder)

func _button(text:String, callback:Callable)->Button:
	return make_button(text, callback)

## The VLAN tab says this PC hosts a virtual LAN that is up.
func vlan_hosting()->bool:
	return _vlan_tab != null && _vlan_tab.hosting_up()

## The VLAN tab has news (the Server tab's "over the virtual LAN" follows it).
func vlan_changed()->void:
	if _server_tab != null:
		_server_tab._refresh()

## Join this address now (the VLAN and Server tabs' Join buttons).
func join_address(address:String)->void:
	_address_edit.text = address
	_tabs.current_tab = Tab.JOIN
	_on_connect_pressed()

## Go to the home base, then join `address` there. A coroutine; false if it didn't start.
static func join_from_home(address:String)->bool:
	var _tree:SceneTree = Engine.get_main_loop() as SceneTree
	Transition.change_scene(HOME_SCENE)
	var _left:float = 15.0
	while _left > 0.0:
		var _scene:Node = _tree.current_scene
		if _scene != null && _scene.scene_file_path == HOME_SCENE && Net.players.local_body() != null:
			break
		await _tree.process_frame
		_left -= _tree.root.get_process_delta_time()
	if Net.state != Net.State.OFFLINE:
		return false
	var _err:Error = Net.join(address)
	if _err != OK:
		Net.connection_failed.emit("couldn't start connecting to " + address)
	return _err == OK

func _on_title()->bool:
	var _scene:Node = get_tree().current_scene
	return _scene != null && _scene.scene_file_path == TITLE_SCENE

func _refresh()->void:
	if !is_inside_tree():
		return
	var _online:bool = Net.is_online()
	var _connecting:bool = Net.state == Net.State.CONNECTING
	_host_button.disabled = Net.state != Net.State.OFFLINE
	_port_edit.editable = Net.state == Net.State.OFFLINE
	_connect_button.disabled = Net.state != Net.State.OFFLINE
	_address_edit.editable = Net.state == Net.State.OFFLINE
	_name_edit.editable = Net.state == Net.State.OFFLINE
	var _visible:Dictionary = {
		Tab.HOST: !_online && !_connecting,
		Tab.JOIN: !_online,
		Tab.SESSION: _online,
		Tab.VLAN: true,
		Tab.SERVER: true,
	}
	# Unhide first and pick the tab, then hide the rest: hiding the current tab
	# makes TabContainer jump to a neighbour on its own.
	for _tab:int in _visible:
		if _visible[_tab]:
			_tabs.set_tab_hidden(_tab, false)
	if _shown_state != Net.state:
		_shown_state = Net.state
		if _online:
			_tabs.current_tab = Tab.SESSION
			_session_scroll.set_deferred(&"scroll_vertical", 0)
		elif _connecting:
			_tabs.current_tab = Tab.JOIN
		elif _tabs.current_tab == Tab.SESSION:
			_tabs.current_tab = Tab.HOST
	if _server_tab != null:
		_server_tab._refresh()
	for _tab:int in _visible:
		if !_visible[_tab]:
			_tabs.set_tab_hidden(_tab, true)
	_refresh_share()
	_refresh_roster()

	for _child:Node in _recent.get_children():
		_child.queue_free()
	if Net.state == Net.State.OFFLINE:
		# in someone's zs-vlan virtual LAN: its host is always the same address
		var _vlan:String = ENetTransport.vlan_address()
		if !_vlan.is_empty() && _vlan != ENetTransport.VLAN_HOST && !_settings.recent_hosts.has(ENetTransport.VLAN_HOST):
			_recent.add_child(_button("Virtual LAN host  " + ENetTransport.VLAN_HOST, func ()->void: _address_edit.text = ENetTransport.VLAN_HOST))
		for _address:String in _settings.recent_hosts:
			var _pick:String = _address
			_recent.add_child(_button(_address, func ()->void: _address_edit.text = _pick))

	match Net.state:
		Net.State.OFFLINE:
			pass
		Net.State.CONNECTING:
			_status.text = "Connecting..."
		Net.State.HOSTING:
			_status.text = "Hosting on port %d - %d/%d players" % [Net.port, RunSession.players.count(), Net.MAX_PLAYERS]
		Net.State.JOINED:
			_status.text = "Joined - %d players" % RunSession.players.count()
			if !Net.players.end_screen_wait().is_empty():
				_status.text += " - the host is finishing its run"

## Host: what a friend types into Join, one row per address with Copy.
func _refresh_share()->void:
	for _child:Node in _share.get_children():
		_child.queue_free()
	if !Net.is_host():
		return
	var _intro:Label = _label("Invite: friend uses their Comms Terminal > Join and types")
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_share.add_child(_intro)
	if Net.share_addresses.is_empty():
		_share.add_child(_label("Looking up your address..."))
		return
	for _entry:Dictionary in Net.share_addresses:
		var _row:HBoxContainer = HBoxContainer.new()
		var _text:Label = _label("%s:  %s" % [_entry.label, _entry.address])
		_text.size_flags_horizontal = SIZE_EXPAND_FILL
		_row.add_child(_text)
		var _address:String = _entry.address
		var _copy:Button = _button("Copy", func ()->void:
			DisplayServer.clipboard_set(_address)
			_status.text = "Copied " + _address)
		_row.add_child(_copy)
		_share.add_child(_row)
	if !_has_internet_address():
		var _hint:Label = _label("Over the internet: forward UDP port %d on your router to this computer, then share your public IP." % Net.port)
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_share.add_child(_hint)

func _has_internet_address()->bool:
	for _entry:Dictionary in Net.share_addresses:
		if _entry.label == "Over the internet":
			return true
	return false

## Everyone in the session; the host gets Kick on each guest.
func _refresh_roster()->void:
	for _child:Node in _roster.get_children():
		_child.queue_free()
	if !Net.is_online():
		return
	_players_title.text = "Players %d/%d" % [RunSession.players.count(), Net.MAX_PLAYERS]
	for _state:PlayerState in RunSession.players.all():
		var _row:HBoxContainer = HBoxContainer.new()
		var _tags:PackedStringArray = []
		if _state.slot == 0 && !_state.hidden:
			_tags.append("host")
		if _state.main:
			_tags.append("main")
		if _state.is_local:
			_tags.append("you")
		var _suffix:String = " (%s)" % ", ".join(_tags) if !_tags.is_empty() else ""
		var _name:Label = _label("%d. %s%s" % [_state.slot + 1, _state.display_name, _suffix])
		_name.size_flags_horizontal = SIZE_EXPAND_FILL
		_row.add_child(_name)
		if Net.is_host() && !_state.is_local:
			var _slot:int = _state.slot
			var _kick:Button = _button("Kick", func ()->void: Net.kick(_slot))
			_kick.name = "Kick%d" % _slot
			_row.add_child(_kick)
		_roster.add_child(_row)

func _on_name_changed(text:String)->void:
	var _clean:String = text.strip_edges()
	if _clean.is_empty():
		# cleared: back to the default (the zs-vlan name, else "Player")
		RunSession.profile.name_set = false
		RunSession.profile.refresh_default()
		_clean = RunSession.profile.display_name
	else:
		RunSession.profile.name_set = true
		RunSession.profile.display_name = _clean
	RunSession.profile.save_resource()
	RunSession.local_player().display_name = _clean
	_update_vlan_name_button()

## Suggest this PC's zs-vlan name when the player picked another one (never applied by itself).
func _update_vlan_name_button()->void:
	var _vlan:String = ENetTransport.vlan_name()
	_vlan_name_button.visible = !_vlan.is_empty() && RunSession.profile.name_set && _vlan != RunSession.profile.display_name
	_vlan_name_button.text = "Use VLAN name: " + _vlan

func _on_host_pressed()->void:
	var _port:int = int(_port_edit.text) if _port_edit.text.is_valid_int() else Net.DEFAULT_PORT
	if _port < 1024 || _port > 65535:
		_status.text = "Port must be 1024-65535"
		return
	var _title:bool = _on_title()
	var _err:Error = Net.host(_port)
	if _err == OK && _title:
		Net.players.mark_scene_seen()
	if _err != OK:
		_status.text = "Couldn't open port %d (in use?)" % _port
		return
	_settings.host_port = _port
	_settings.save_resource()
	if _title:
		# a host arriving at the title leaves (NetPlayers): go on to the home base
		close()
		Transition.change_scene(HOME_SCENE)

func _on_connect_pressed()->void:
	if Net.state != Net.State.OFFLINE:
		return
	var _text:String = _address_edit.text.strip_edges()
	if Net.parse_address(_text).is_empty():
		_status.text = "Type an address like 192.168.1.20 or 192.168.1.20:%d" % Net.DEFAULT_PORT
		return
	if _on_title():
		# from our own home base, like at its terminal: it lends the host a gun for a
		# mission (HomeBase.lend_to_host)
		_settings.remember_host(_text)
		close()
		join_from_home(_text)
		return
	if Net.join(_text) != OK:
		_status.text = "Couldn't start connecting"
		return
	_settings.remember_host(_text)

func _on_leave_pressed()->void:
	Net.leave()

func _on_failed(reason:String)->void:
	if is_inside_tree():
		_status.text = "Failed: " + reason

func _on_ended(reason:String)->void:
	if is_inside_tree():
		_status.text = "Session ended: " + reason

func _focus_first()->void:
	if Net.is_online():
		_leave_button.grab_focus()
	elif Net.state == Net.State.OFFLINE && !_address_edit.text.is_empty():
		_tabs.current_tab = Tab.JOIN
		_connect_button.grab_focus()
	else:
		_host_button.grab_focus()

func close()->void:
	queue_free()

## Escape / pause closes the dialog instead of opening the pause menu.
func _input(event:InputEvent)->void:
	if event.is_action("ui_cancel") || event.is_action(&"pause"):
		get_viewport().set_input_as_handled()
		if event.is_released():
			close()

func _on_playtest_log_toggled(on:bool)->void:
	_settings.playtest_log = on
	_settings.save_resource()
	if PlaytestLog.current() != null:
		PlaytestLog.current().set_enabled(on)

func _open_log_folder()->void:
	DirAccess.make_dir_recursive_absolute(PlaytestLog.DIR)
	OS.shell_open(ProjectSettings.globalize_path(PlaytestLog.DIR))
