## Modal co-op dialog, opened by the home base Comms Terminal and the title's Co-op button
## (open_layer). A card with a header (title, session chip, Close), a left rail of pages and
## a message bar:
## - Play (offline): your name, then two cards side by side: Host a game (port, Host game)
##   and Join a game (address, Join, recent hosts as chips).
## - Session (replaces Play while hosting or joined, and opens by itself): everyone in the
##   session (the host can kick), what to tell a friend (with Copy), Leave session.
## - Internet (VLAN): the zs-vlan virtual LAN, CoopVlanTab. Server: a dedicated server on
##   this PC, CoopServerTab. Both are there in every state.
## Hosting or joining from the title goes on to the home base (a host on the title leaves its
## session; a guest lends the host a gun from its own home base). A join from the title that
## fails opens the dialog again in the home base with the reason.
## Built in code with CoopStyle; it consumes Escape before the pause menu sees it and does
## not freeze the room (the session keeps running).
class_name CoopDialog
extends Control

const LAYER_NAME:String = "CoopDialogLayer"
const HOME_SCENE:String = "res://game/scenes/room_H00.tscn"
const TITLE_SCENE:String = "res://game/scenes/title.tscn"

const THEME_PATH:String = CoopStyle.THEME_PATH
const SETTINGS_PATH:String = "res://game/resources/net_settings.tres"
const FONT_SIZE:int = CoopStyle.BODY
const SIZE:Vector2 = Vector2(408, 240)
## Pages, in the order of the rail. The TabContainer underneath keeps them; its tab bar is hidden.
enum Tab {PLAY, SESSION, VLAN, SERVER}

var _settings:NetSettings
var _status:Label
var _tabs:TabContainer
var _nav:Dictionary = {}
var _nav_group:ButtonGroup = ButtonGroup.new()
var _chip_box:HBoxContainer
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
var _recent:HFlowContainer
var _leave_button:Button
var _close_button:Button
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

## Kept for other screens; CoopStyle has the whole set.
static func make_label(text:String)->Label:
	return CoopStyle.label(text)

static func make_edit(text:String, placeholder:String)->LineEdit:
	return CoopStyle.edit(text, placeholder)

static func make_button(text:String, callback:Callable)->Button:
	return CoopStyle.button(text, callback)

func _ready()->void:
	_settings = load(SETTINGS_PATH)
	_settings.load_resource()
	theme = CoopStyle.theme()
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
	_dim.color = Color(0.02, 0.02, 0.03, 0.72)
	_dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_dim)

	var _center:CenterContainer = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_center)
	var _panel:PanelContainer = PanelContainer.new()
	_panel.theme_type_variation = &"DialogPanel"
	_panel.custom_minimum_size = SIZE
	_center.add_child(_panel)
	var _box:VBoxContainer = VBoxContainer.new()
	_box.add_theme_constant_override(&"separation", 5)
	_panel.add_child(_box)

	# header: title, the session chip, Close
	var _title:Label = CoopStyle.label("CO-OP", &"TitleLabel")
	_chip_box = HBoxContainer.new()
	_close_button = CoopStyle.button("Close  Esc", close, CoopStyle.GHOST)
	_close_button.name = "Close"
	_box.add_child(CoopStyle.row([_title, _chip_box, CoopStyle.spacer(), _close_button], 8))

	var _body:HBoxContainer = HBoxContainer.new()
	_body.size_flags_vertical = SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", 8)
	_box.add_child(_body)

	# the rail
	var _rail:VBoxContainer = VBoxContainer.new()
	_rail.custom_minimum_size = Vector2(84, 0)
	_rail.add_theme_constant_override(&"separation", 2)
	_body.add_child(_rail)
	for _tab:int in [Tab.PLAY, Tab.SESSION, Tab.VLAN, Tab.SERVER]:
		var _page:int = _tab
		var _b:Button = CoopStyle.button(_page_name(_page), func ()->void: show_page(_page), CoopStyle.NAV)
		_b.toggle_mode = true
		_b.button_group = _nav_group
		_b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_b.name = "Nav%d" % _page
		_rail.add_child(_b)
		_nav[_page] = _b
	_rail.add_child(_vspacer())
	# indented like the rail buttons' text
	var _hint:MarginContainer = MarginContainer.new()
	_hint.add_theme_constant_override(&"margin_left", int(CoopStyle.NAV_PAD))
	_hint.add_child(CoopStyle.label(_rail_hint(), &"SmallLabel", true))
	_rail.add_child(_hint)

	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	_tabs.size_flags_horizontal = SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = SIZE_EXPAND_FILL
	_body.add_child(_tabs)
	_build_play()
	_build_session()
	# the virtual LAN and the dedicated server: there in every state
	_vlan_tab = (load("res://game/scripts/ui/CoopVlanTab.gd") as GDScript).new()
	_vlan_tab.dialog = self
	_tabs.add_child(_vlan_tab)
	_server_tab = (load("res://game/scripts/ui/CoopServerTab.gd") as GDScript).new()
	_server_tab.dialog = self
	_tabs.add_child(_server_tab)

	# message bar, playtest log
	var _bar:PanelContainer = PanelContainer.new()
	_bar.theme_type_variation = &"BarPanel"
	_box.add_child(_bar)
	_status = CoopStyle.label("", &"", true)
	var _log_box:CheckBox = CheckBox.new()
	_log_box.text = "Playtest log"
	_log_box.add_theme_font_size_override(&"font_size", CoopStyle.SMALL)
	_log_box.button_pressed = _settings.playtest_log || PlaytestLog.is_on()
	_log_box.tooltip_text = "Writes a log of the session (network, rooms, fights, errors) to share with the developer"
	_log_box.toggled.connect(_on_playtest_log_toggled)
	var _folder:Button = CoopStyle.button("Log folder", _open_log_folder, CoopStyle.GHOST)
	_bar.add_child(CoopStyle.row([_status, _log_box, _folder], 6))

static func _vspacer()->Control:
	var _c:Control = Control.new()
	_c.size_flags_vertical = SIZE_EXPAND_FILL
	return _c

static func _page_name(tab:int)->String:
	match tab:
		Tab.PLAY: return "Play"
		Tab.SESSION: return "Session"
		Tab.VLAN: return "Internet (VLAN)"
		Tab.SERVER: return "Server"
	return ""

func _rail_hint()->String:
	return "Same network: Play.\nDifferent places: Internet (VLAN) first."

func _page_scroll(page_name:String)->Array:
	var _scroll:ScrollContainer = ScrollContainer.new()
	_scroll.name = page_name
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(_scroll)
	var _page:VBoxContainer = VBoxContainer.new()
	_page.size_flags_horizontal = SIZE_EXPAND_FILL
	_page.add_theme_constant_override(&"separation", 6)
	_scroll.add_child(_page)
	return [_scroll, _page]

func _build_play()->void:
	var _page:VBoxContainer = _page_scroll("Play")[1]
	# a name the player never picked follows this PC's zs-vlan name (it may be new)
	if RunSession.profile.refresh_default() && Net.state == Net.State.OFFLINE:
		RunSession.local_player().display_name = RunSession.profile.display_name
	_name_edit = CoopStyle.edit(RunSession.profile.display_name, PlayerProfile.default_name())
	_name_edit.max_length = Net.MAX_NAME_LENGTH
	_name_edit.text_changed.connect(_on_name_changed)
	_vlan_name_button = CoopStyle.button("", func ()->void:
		_name_edit.text = ENetTransport.vlan_name()
		_on_name_changed(_name_edit.text), CoopStyle.GHOST)
	_vlan_name_button.name = "UseVlanName"
	var _name_row:HBoxContainer = CoopStyle.field("Your name", _name_edit)
	_name_row.add_child(_vlan_name_button)
	_page.add_child(_name_row)
	_update_vlan_name_button()

	var _cards:HBoxContainer = HBoxContainer.new()
	_cards.add_theme_constant_override(&"separation", 6)
	_page.add_child(_cards)
	var _host:VBoxContainer = CoopStyle.card(_cards, "Host a game", "Friends join you. Your world, your run.")
	_port_edit = CoopStyle.edit(str(_settings.host_port), str(Net.DEFAULT_PORT))
	_port_edit.max_length = 5
	_host.add_child(CoopStyle.field("Port", _port_edit, 24))
	_host.add_child(_vspacer())
	_host_button = CoopStyle.button("Host game", _on_host_pressed, CoopStyle.PRIMARY)
	_host.add_child(_host_button)

	var _join:VBoxContainer = CoopStyle.card(_cards, "Join a game", "Type the address the host sent.")
	_address_edit = CoopStyle.edit(_settings.recent_hosts[0] if !_settings.recent_hosts.is_empty() else "", "ip or ip:port")
	_address_edit.text_submitted.connect(func (_text:String)->void: _on_connect_pressed())
	_join.add_child(_address_edit)
	_recent = HFlowContainer.new()
	_recent.add_theme_constant_override(&"h_separation", 3)
	_recent.add_theme_constant_override(&"v_separation", 3)
	_join.add_child(_recent)
	_connect_button = CoopStyle.button("Join", _on_connect_pressed, CoopStyle.PRIMARY)
	_join.add_child(_connect_button)

	var _hint:HBoxContainer = CoopStyle.row([
		CoopStyle.label("Not on the same network, no router setup?", &"MutedLabel"),
		CoopStyle.button("Use Internet (VLAN)", func ()->void: show_page(Tab.VLAN), CoopStyle.GHOST)])
	_page.add_child(_hint)

func _build_session()->void:
	var _parts:Array = _page_scroll("Session")
	_session_scroll = _parts[0]
	var _session:VBoxContainer = _parts[1]
	var _people:VBoxContainer = CoopStyle.card(_session)
	_players_title = CoopStyle.label("", &"HeadingLabel")
	_people.add_child(_players_title)
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override(&"separation", 2)
	_people.add_child(_roster)
	_share = VBoxContainer.new()
	_session.add_child(_share)
	_leave_button = CoopStyle.button("Leave session", _on_leave_pressed, CoopStyle.DANGER)
	_leave_button.size_flags_horizontal = SIZE_SHRINK_END
	_session.add_child(_leave_button)

## Open a page (the rail does this; so do the pages' own links).
func show_page(tab:int)->void:
	if _tabs.is_tab_hidden(tab):
		return
	_tabs.current_tab = tab
	_mark_nav()

func _mark_nav()->void:
	for _tab:int in _nav:
		var _b:Button = _nav[_tab]
		_b.set_pressed_no_signal(_tab == _tabs.current_tab)

## A message in the bar: info, ok, warn or error (CoopStyle.Tone). It stays until the next one.
func say(text:String, tone:int = CoopStyle.Tone.INFO)->void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override(&"font_color", CoopStyle.tone_color(tone))

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
	show_page(Tab.PLAY)
	_on_connect_pressed()

## Go to the home base, then join `address` there. A coroutine; false if it didn't start.
## When it fails, the dialog opens again there with the reason.
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
	var _reason:Array = []
	var _note:Callable = func (reason:String)->void: _reason.append(reason)
	Net.connection_failed.connect(_note)
	var _err:Error = Net.join(address)
	if _err != OK:
		_reason.append("couldn't start connecting")
	while _err == OK && Net.state == Net.State.CONNECTING:
		await _tree.process_frame
	Net.connection_failed.disconnect(_note)
	if Net.state == Net.State.OFFLINE && !_reason.is_empty():
		open_layer().say("Couldn't join %s: %s" % [address, _reason[-1]], CoopStyle.Tone.ERROR)
	return _err == OK

func _on_title()->bool:
	var _scene:Node = get_tree().current_scene
	return _scene != null && _scene.scene_file_path == TITLE_SCENE

func _refresh()->void:
	if !is_inside_tree():
		return
	var _online:bool = Net.is_online()
	var _connecting:bool = Net.state == Net.State.CONNECTING
	var _offline:bool = Net.state == Net.State.OFFLINE
	_host_button.disabled = !_offline
	_port_edit.editable = _offline
	_connect_button.disabled = !_offline
	_connect_button.text = "Connecting..." if _connecting else "Join"
	_address_edit.editable = _offline
	_name_edit.editable = _offline
	var _visible:Dictionary = {
		Tab.PLAY: !_online,
		Tab.SESSION: _online,
		Tab.VLAN: true,
		Tab.SERVER: true,
	}
	# Unhide first and pick the page, then hide the rest: hiding the current tab
	# makes TabContainer jump to a neighbour on its own.
	for _tab:int in _visible:
		if _visible[_tab]:
			_tabs.set_tab_hidden(_tab, false)
		_nav[_tab].visible = _visible[_tab]
	if _shown_state != Net.state:
		_shown_state = Net.state
		if _online:
			_tabs.current_tab = Tab.SESSION
			_session_scroll.set_deferred(&"scroll_vertical", 0)
		elif _connecting:
			_tabs.current_tab = Tab.PLAY
		elif _tabs.current_tab == Tab.SESSION:
			_tabs.current_tab = Tab.PLAY
	if _server_tab != null:
		_server_tab._refresh()
	for _tab:int in _visible:
		if !_visible[_tab]:
			_tabs.set_tab_hidden(_tab, true)
	_mark_nav()
	_refresh_chip()
	_refresh_share()
	_refresh_roster()

	CoopStyle.clear(_recent)
	if _offline:
		# in someone's zs-vlan virtual LAN: its host is always the same address
		var _vlan:String = ENetTransport.vlan_address()
		if !_vlan.is_empty() && _vlan != ENetTransport.VLAN_HOST && !_settings.recent_hosts.has(ENetTransport.VLAN_HOST):
			_recent.add_child(_recent_button("VLAN host " + ENetTransport.VLAN_HOST, ENetTransport.VLAN_HOST))
		for _address:String in _settings.recent_hosts:
			_recent.add_child(_recent_button(_address, _address))

	match Net.state:
		Net.State.CONNECTING:
			say("Connecting...", CoopStyle.Tone.INFO)
		Net.State.HOSTING:
			say("Hosting on port %d - %d/%d players" % [Net.port, RunSession.players.count(), Net.MAX_PLAYERS], CoopStyle.Tone.OK)
		Net.State.JOINED:
			var _text:String = "Joined - %d players" % RunSession.players.count()
			if !Net.players.end_screen_wait().is_empty():
				_text += " - the host is finishing its run"
			say(_text, CoopStyle.Tone.OK)

func _recent_button(text:String, address:String)->Button:
	var _b:Button = CoopStyle.button(text, func ()->void:
		_address_edit.text = address
		_connect_button.grab_focus(), CoopStyle.CHIP)
	_b.tooltip_text = "Put %s in the address" % address
	return _b

func _refresh_chip()->void:
	CoopStyle.clear(_chip_box)
	match Net.state:
		Net.State.OFFLINE: _chip_box.add_child(CoopStyle.chip("OFFLINE", CoopStyle.Tone.MUTED))
		Net.State.CONNECTING: _chip_box.add_child(CoopStyle.chip("CONNECTING", CoopStyle.Tone.WARN))
		Net.State.HOSTING: _chip_box.add_child(CoopStyle.chip("HOSTING %d/%d" % [RunSession.players.count(), Net.MAX_PLAYERS], CoopStyle.Tone.OK))
		Net.State.JOINED: _chip_box.add_child(CoopStyle.chip("JOINED %d" % RunSession.players.count(), CoopStyle.Tone.OK))

## Host: what a friend types into Join, one row per address with Copy.
func _refresh_share()->void:
	CoopStyle.clear(_share)
	if !Net.is_host():
		return
	var _card:VBoxContainer = CoopStyle.card(_share, "Invite friends", "A friend opens Co-op > Play > Join and types one of these:")
	if Net.share_addresses.is_empty():
		_card.add_child(CoopStyle.label("Looking up your address...", &"MutedLabel"))
		return
	for _entry:Dictionary in Net.share_addresses:
		_card.add_child(CoopStyle.label(_entry.label, &"SmallLabel"))
		_card.add_child(CoopStyle.copy_row(_entry.address, func (text:String)->void: say("Copied " + text, CoopStyle.Tone.OK)))
	if !_has_internet_address():
		_card.add_child(CoopStyle.banner("Over the internet: use Internet (VLAN), or forward UDP port %d on your router to this computer and share your public IP." % Net.port, CoopStyle.Tone.WARN))

func _has_internet_address()->bool:
	for _entry:Dictionary in Net.share_addresses:
		if _entry.label == "Over the internet":
			return true
	return false

## Everyone in the session with role chips; the host gets Kick on each guest.
func _refresh_roster()->void:
	CoopStyle.clear(_roster)
	if !Net.is_online():
		return
	_players_title.text = "Players %d/%d" % [RunSession.players.count(), Net.MAX_PLAYERS]
	for _state:PlayerState in RunSession.players.all():
		var _row:HBoxContainer = HBoxContainer.new()
		_row.add_child(CoopStyle.label("%d" % (_state.slot + 1), &"MutedLabel"))
		_row.add_child(CoopStyle.label(_state.display_name))
		if _state.slot == 0 && !_state.hidden:
			_row.add_child(CoopStyle.chip("HOST", CoopStyle.Tone.WARN))
		if _state.main:
			_row.add_child(CoopStyle.chip("MAIN", CoopStyle.Tone.INFO))
		if _state.is_local:
			_row.add_child(CoopStyle.chip("YOU", CoopStyle.Tone.OK))
		_row.add_child(CoopStyle.spacer())
		if Net.is_host() && !_state.is_local:
			var _slot:int = _state.slot
			var _kick:Button = CoopStyle.button("Kick", func ()->void: Net.kick(_slot), CoopStyle.DANGER)
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
		say("The port must be 1024-65535", CoopStyle.Tone.ERROR)
		_port_edit.grab_focus()
		return
	var _title:bool = _on_title()
	var _err:Error = Net.host(_port)
	if _err == OK && _title:
		Net.players.mark_scene_seen()
	if _err != OK:
		say("Couldn't open port %d - is another game using it?" % _port, CoopStyle.Tone.ERROR)
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
		say("Type an address like 192.168.1.20 or 192.168.1.20:%d" % Net.DEFAULT_PORT, CoopStyle.Tone.ERROR)
		_address_edit.grab_focus()
		return
	if _on_title():
		# from our own home base, like at its terminal: it lends the host a gun for a
		# mission (HomeBase.lend_to_host)
		_settings.remember_host(_text)
		close()
		join_from_home(_text)
		return
	if Net.join(_text) != OK:
		say("Couldn't start connecting", CoopStyle.Tone.ERROR)
		return
	_settings.remember_host(_text)

func _on_leave_pressed()->void:
	Net.leave()

func _on_failed(reason:String)->void:
	if is_inside_tree():
		say("Couldn't connect: " + reason, CoopStyle.Tone.ERROR)

func _on_ended(reason:String)->void:
	if is_inside_tree():
		say("Session ended: " + reason, CoopStyle.Tone.WARN)

func _focus_first()->void:
	if Net.is_online():
		_leave_button.grab_focus()
	elif Net.state == Net.State.OFFLINE && !_address_edit.text.is_empty():
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
