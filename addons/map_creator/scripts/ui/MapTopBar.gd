## The admin topbar, built from the catalog.
## Row 1: Edit/Play toggle, category tabs (keys 1-9), the room's settings (floor look,
## Start / Home / Campaign flags, each with a tooltip), workspace, room name, recent rooms and Browse.
## Row 2: tools, brush, Clean, Undo/Redo, Save, the auto-clean and grid toggles, and messages.
## Row 3: the current category's items, each followed by its variants (Q/E step through them).
## In Play mode only row 1 shows.
class_name MapTopBar
extends PanelContainer


@export var creator:MapCreator

var _mode_button:Button
var _room_label:MenuButton
var _recent:MenuButton
var _workspace:MenuButton
var _stamps:MenuButton
var _problems:Button
var _layers:MenuButton
var _stamp_names:Array = []
var _workspace_ids:Array[String] = []
var _browse:Button
var _message:Label
var _dirty:Label
var _save:Button
var _undo:Button
var _redo:Button
var _rows:Array[Control] = []
var _category_buttons:Dictionary = {}
var _tool_buttons:Dictionary = {}
var _brush_buttons:Dictionary = {}
var _item_strip:HBoxContainer
var _item_buttons:Dictionary = {}
var _swatches:Dictionary = {}
var _message_time:float
## Room settings on row 1: look menu and flag toggles (field -> Button).
var _look:MenuButton
var _looks:PackedStringArray = []
var _flags:Dictionary = {}
var _room_box:HBoxContainer

## Room flags: [field, label, tooltip].
const ROOM_FLAGS:Array = [
	[&"start", "Start", "Campaign start: a new run begins in this room.\nResets the run (cleared rooms, loot, weapons) on entry; starting weapon spots work only here. No fight sections."],
	[&"home", "Home", "Home base: the hub between runs (adds the HomeBase node: shop, run summary)."],
	[&"writes_balance", "Campaign", "Campaign room: its waves, spawn caps and loot are written to game/balance/maps.json on save,\nand the campaign checks run (boss room needs a portal + victory exit).\nOff for test rooms outside a campaign."],
]

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# children are ready before the creator: wait for its layout
	if !creator.is_node_ready():
		await creator.ready
	var _preset:MapCreatorPreset = creator.preset
	var _style:StyleBoxFlat = StyleBoxFlat.new()
	_style.bg_color = _preset.bar_color
	_style.content_margin_left = 2
	_style.content_margin_right = 2
	_style.content_margin_top = 1
	_style.content_margin_bottom = 1
	add_theme_stylebox_override(&"panel", _style)
	# shared by every map creator panel under the UI root
	get_parent().theme = make_theme(_preset)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)

	var _box:VBoxContainer = VBoxContainer.new()
	_box.add_theme_constant_override(&"separation", 1)
	add_child(_box)
	_box.add_child(_build_top_row())
	_rows.append(_build_tool_row())
	_box.add_child(_rows[0])
	var _scroll:ScrollContainer = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.custom_minimum_size.y = _preset.swatch_size.y + 4
	_item_strip = HBoxContainer.new()
	_item_strip.add_theme_constant_override(&"separation", 1)
	_scroll.add_child(_item_strip)
	_rows.append(_scroll)
	_box.add_child(_scroll)

	creator.mode_changed.connect(func (_v:bool)->void: _refresh())
	creator.tool_changed.connect(_refresh)
	creator.item_changed.connect(_on_item_changed)
	creator.dirty_changed.connect(_refresh)
	creator.history_changed.connect(_refresh)
	creator.layout_changed.connect(_refresh)
	creator.message.connect(show_message)
	creator.workspace_changed.connect(_refresh)
	creator.problems_changed.connect(_refresh)
	if creator.settings != null:
		creator.settings.recent_changed.connect(_fill_recent)
	_fill_recent()
	_on_item_changed()

static func make_theme(preset:MapCreatorPreset)->Theme:
	var _theme:Theme = Theme.new()
	_theme.default_font_size = preset.font_size
	var _flat:StyleBoxFlat = StyleBoxFlat.new()
	_flat.bg_color = Color(1, 1, 1, 0.06)
	_flat.content_margin_left = 2
	_flat.content_margin_right = 2
	var _pressed:StyleBoxFlat = _flat.duplicate()
	_pressed.bg_color = Color(preset.active_color, 0.45)
	var _hover:StyleBoxFlat = _flat.duplicate()
	_hover.bg_color = Color(1, 1, 1, 0.16)
	for _type:String in ["Button", "MenuButton"]:
		_theme.set_stylebox(&"normal", _type, _flat)
		_theme.set_stylebox(&"hover", _type, _hover)
		_theme.set_stylebox(&"pressed", _type, _pressed)
		_theme.set_stylebox(&"hover_pressed", _type, _pressed)
		_theme.set_stylebox(&"focus", _type, StyleBoxEmpty.new())
		_theme.set_constant(&"h_separation", _type, 2)
	return _theme

func _build_top_row()->HBoxContainer:
	var _row:HBoxContainer = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", 1)
	_mode_button = _button(_row, "EDIT", "Edit / Play (%s)" % OS.get_keycode_string(creator.preset.key_toggle_edit), creator.toggle_editing)
	_row.add_child(VSeparator.new())
	var _index:int = 0
	for _category:MapCatalogCategory in creator.catalog.categories:
		_index += 1
		var _b:Button = _button(_row, _category.display_name, "%s (%d)" % [_category.display_name, _index], creator.select_category.bind(_category))
		_b.toggle_mode = true
		var _icon:Texture2D = creator.category_icon(_category)
		_b.icon = _icon if _icon != null else _swatch(_category.color)
		_b.add_theme_constant_override(&"icon_max_width", int(creator.preset.swatch_size.y))
		_category_buttons[_category] = _b
	var _spacer:Control = Control.new()
	_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(_spacer)
	_row.add_child(_build_room_settings())
	_workspace = MenuButton.new()
	_workspace.flat = false
	_workspace.tooltip_text = "Workspace: where Save writes (a mod in user://mods, or the game files)"
	_workspace.get_popup().id_pressed.connect(_on_workspace)
	_workspace.about_to_popup.connect(_fill_workspaces)
	_row.add_child(_workspace)
	_room_label = MenuButton.new()
	_room_label.text = "room_" + creator.key
	_room_label.tooltip_text = "This room: rename, copy, name"
	_room_label.about_to_popup.connect(_fill_room_menu)
	_room_label.get_popup().id_pressed.connect(_on_room_menu)
	_row.add_child(_room_label)
	_recent = MenuButton.new()
	_recent.text = "Recent"
	_recent.tooltip_text = "Last visited rooms"
	_recent.flat = false
	_recent.get_popup().id_pressed.connect(func (id:int)->void: creator.switch_room(creator.settings.recent_rooms[id]))
	_row.add_child(_recent)
	_problems = _button(_row, "OK", "Live problems of the room (%s)" % OS.get_keycode_string(creator.preset.key_problems), func ()->void: creator.problems_requested.emit())
	_button(_row, "Waves", "Sections and waves (%s)" % OS.get_keycode_string(creator.preset.key_waves), func ()->void: creator.waves_requested.emit())
	_button(_row, "Map", "Campaign graph: rooms and their links (%s)" % OS.get_keycode_string(creator.preset.key_graph), func ()->void: creator.graph_requested.emit())
	_browse = _button(_row, "Rooms", "Search / switch rooms (%s)" % OS.get_keycode_string(creator.preset.key_browse), func ()->void: creator.browse_requested.emit())
	_button(_row, "?", "Keys and mouse (%s)" % OS.get_keycode_string(creator.preset.key_help), func ()->void: creator.help_requested.emit())
	return _row

func _build_tool_row()->HBoxContainer:
	var _row:HBoxContainer = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", 1)
	var _p:MapCreatorPreset = creator.preset
	for _entry:Array in [[MapCreator.Tool.PAINT, "Paint", _p.key_paint], [MapCreator.Tool.ERASE, "Erase", _p.key_erase],
			[MapCreator.Tool.FILL, "Fill", _p.key_fill], [MapCreator.Tool.PICK, "Pick", _p.key_pick],
			[MapCreator.Tool.SELECT, "Select", _p.key_select], [MapCreator.Tool.MOVE, "Move", _p.key_move]]:
		var _b:Button = _button(_row, _entry[1], "%s (%s)" % [_entry[1], OS.get_keycode_string(_entry[2])], creator.set_tool.bind(_entry[0]))
		_b.toggle_mode = true
		_tool_buttons[_entry[0]] = _b
	_row.add_child(VSeparator.new())
	for _entry:Array in [[MapCreator.Brush.ONE, "1", "Single cell"], [MapCreator.Brush.THREE, "3x3", "3x3 brush"], [MapCreator.Brush.RECT, "Rect", "Drag a rectangle"],
			[MapCreator.Brush.LINE, "Line", "Drag a line (%s)" % OS.get_keycode_string(_p.key_line)]]:
		var _b:Button = _button(_row, _entry[1], _entry[2], creator.set_brush.bind(_entry[0]))
		_b.toggle_mode = true
		_brush_buttons[_entry[0]] = _b
	for _entry:Array in [["MirX", "Mirror the brush across the room's middle (x)", "mirror_x"],
			["MirY", "Mirror the brush across the room's middle (y)", "mirror_y"],
			["Mix", "Scatter: paint a random variant of the item", "scatter"]]:
		var _b:Button = _button(_row, _entry[0], _entry[1], func ()->void: pass)
		_b.toggle_mode = true
		var _field:String = _entry[2]
		_b.toggled.connect(func (on:bool)->void: creator.tools.set(_field, on))
	_layers = MenuButton.new()
	_layers.text = "Layers"
	_layers.flat = false
	_layers.tooltip_text = "Show / hide floor, walls, holes, entity markers"
	var _layer_popup:PopupMenu = _layers.get_popup()
	_layer_popup.hide_on_checkable_item_selection = false
	for _i:int in LAYER_NAMES.size():
		_layer_popup.add_check_item(LAYER_NAMES[_i], _i)
		_layer_popup.set_item_checked(_i, true)
	_layer_popup.id_pressed.connect(_on_layer)
	_row.add_child(_layers)
	_stamps = MenuButton.new()
	_stamps.text = "Stamps"
	_stamps.flat = false
	_stamps.tooltip_text = "Place a saved stamp, or save the selection as one (Ctrl+C / Ctrl+V copy and paste)"
	_stamps.about_to_popup.connect(_fill_stamps)
	_stamps.get_popup().id_pressed.connect(_on_stamp)
	_row.add_child(_stamps)
	_row.add_child(VSeparator.new())
	_button(_row, "Clean", "Clean visual tiles, colliders, navigation (%s)" % OS.get_keycode_string(_p.key_clean), creator.clean)
	_undo = _button(_row, "Undo", "Ctrl+%s" % OS.get_keycode_string(_p.key_undo), creator.undo)
	_redo = _button(_row, "Redo", "Ctrl+%s" % OS.get_keycode_string(_p.key_redo), creator.redo)
	_save = _button(_row, "Save", "Save layout + bake the room scene (Ctrl+%s)" % OS.get_keycode_string(_p.key_save), creator.save)
	_dirty = Label.new()
	_dirty.text = "*"
	_dirty.tooltip_text = "Unsaved changes"
	_row.add_child(_dirty)
	_row.add_child(VSeparator.new())
	if creator.settings != null:
		var _auto:Button = _button(_row, "Auto", "Clean after every stroke", func ()->void: pass)
		_auto.toggle_mode = true
		_auto.button_pressed = creator.settings.auto_clean
		_auto.toggled.connect(creator.settings.set_auto_clean)
		var _grid:Button = _button(_row, "Grid", "Show the cell grid", func ()->void: pass)
		_grid.toggle_mode = true
		_grid.button_pressed = creator.settings.show_grid
		_grid.toggled.connect(creator.settings.set_show_grid)
	_message = Label.new()
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_message.clip_text = true
	_row.add_child(_message)
	return _row

func _build_room_settings()->HBoxContainer:
	_room_box = HBoxContainer.new()
	_room_box.add_theme_constant_override(&"separation", 1)
	_look = MenuButton.new()
	_look.flat = false
	_look.tooltip_text = "Room look: the default floor style (new floor, holes and walls take it). Click to change"
	_look.about_to_popup.connect(_fill_looks)
	_look.get_popup().id_pressed.connect(func (id:int)->void:
		if id < _looks.size():
			creator.set_layout_field(&"look", _looks[id]))
	_room_box.add_child(_look)
	for _flag:Array in ROOM_FLAGS:
		var _field:StringName = _flag[0]
		var _b:Button = _button(_room_box, _flag[1], _flag[2], func ()->void: pass)
		_b.toggle_mode = true
		_b.toggled.connect(func (on:bool)->void:
			if creator.layout != null && bool(creator.layout.get(_field)) != on:
				creator.set_layout_field(_field, on))
		_flags[_field] = _b
	return _room_box

func _fill_looks()->void:
	var _popup:PopupMenu = _look.get_popup()
	_popup.clear()
	_looks.clear()
	for _item:MapCatalogItem in creator.catalog.all_items():
		if _item.kind == MapCatalogItem.Kind.FLOOR && String(_item.id).count("_") == 1:
			_looks.append(String(_item.id).trim_prefix("floor_"))
	for _i:int in _looks.size():
		_popup.add_radio_check_item(_looks[_i], _i)
		_popup.set_item_checked(_i, creator.layout != null && _looks[_i] == creator.layout.look)

func _fill_room_menu()->void:
	var _popup:PopupMenu = _room_label.get_popup()
	_popup.clear()
	var _locked:bool = creator.mod_state != null && creator.mod_state.is_active() && creator.rooms.is_builtin(creator.key)
	_popup.add_item("Rename room_%s..." % creator.key, 0)
	_popup.set_item_disabled(0, !creator.can_edit() || _locked || !creator.writable())
	if _locked:
		_popup.set_item_tooltip(0, "Built-in rooms keep their key: copy it instead")
	_popup.add_item("Copy as new room...", 1)
	_popup.set_item_disabled(1, !creator.can_edit() || !creator.writable())
	_popup.add_item("Display name...", 2)
	_popup.set_item_disabled(2, !creator.can_edit())
	_popup.add_separator()
	_popup.add_item("All rooms (%s)" % OS.get_keycode_string(creator.preset.key_browse), 3)

func _on_room_menu(id:int)->void:
	match id:
		0: creator.ask_rename(creator.key)
		1: creator.ask_duplicate(creator.key, true)
		2: creator.ask_display_name()
		3: creator.browse_requested.emit()

func _button(parent:Control, text:String, tooltip:String, action:Callable)->Button:
	var _b:Button = Button.new()
	_b.text = text
	_b.tooltip_text = tooltip
	_b.focus_mode = Control.FOCUS_NONE
	_b.pressed.connect(func ()->void: action.call())
	parent.add_child(_b)
	return _b

## Solid color icon (an item without its own icon).
func _swatch(color:Color)->Texture2D:
	if _swatches.has(color):
		return _swatches[color]
	var _size:Vector2i = Vector2i(creator.preset.swatch_size)
	var _image:Image = Image.create(_size.x, _size.y, false, Image.FORMAT_RGBA8)
	_image.fill(color)
	for _i:int in _size.x:
		_image.set_pixel(_i, 0, color.lightened(0.3))
		_image.set_pixel(_i, _size.y - 1, color.darkened(0.4))
	var _texture:ImageTexture = ImageTexture.create_from_image(_image)
	_swatches[color] = _texture
	return _texture

func _on_item_changed()->void:
	for _child:Node in _item_strip.get_children():
		_child.queue_free()
	_item_buttons.clear()
	if creator.category != null:
		for _item:MapCatalogItem in creator.category.items:
			_add_item_button(_item, false)
			for _variant:MapCatalogItem in _item.variants:
				_add_item_button(_variant, true)
	_refresh()

func _add_item_button(item:MapCatalogItem, variant:bool)->void:
	var _b:Button = _button(_item_strip, "" if variant else item.display_name, "%s%s" % [item.display_name, "\n" + item.description if !item.description.is_empty() else ""], creator.select_item.bind(item))
	_b.toggle_mode = true
	var _icon:Texture2D = creator.icon_of(item)
	_b.icon = _icon if _icon != null else _swatch(item.color)
	_b.add_theme_constant_override(&"icon_max_width", int(creator.preset.swatch_size.y))
	_item_buttons[item] = _b

func _fill_recent()->void:
	var _popup:PopupMenu = _recent.get_popup()
	_popup.clear()
	if creator.settings == null:
		return
	for _i:int in creator.settings.recent_rooms.size():
		var _key:String = creator.settings.recent_rooms[_i]
		var _layout:RoomLayoutResource = creator.baker.layouts.get(_key, null) if creator.baker != null else null
		_popup.add_item("room_%s%s" % [_key, "  " + _layout.display_name if _layout != null else ""], _i)

const LAYER_NAMES:PackedStringArray = ["Floor", "Walls", "Holes", "Entity markers"]

func _on_layer(id:int)->void:
	var _popup:PopupMenu = _layers.get_popup()
	var _on:bool = !_popup.is_item_checked(id)
	_popup.set_item_checked(id, _on)
	creator.set_layer_visible(id, _on)

const SAVE_STAMP_ID:int = 1002

func _fill_stamps()->void:
	var _popup:PopupMenu = _stamps.get_popup()
	_popup.clear()
	_popup.add_item("Save selection as stamp...", SAVE_STAMP_ID)
	_popup.set_item_disabled(0, creator.selection.is_empty())
	_popup.add_separator()
	_stamp_names = MapTools.stamps().keys()
	_stamp_names.sort()
	for _i:int in _stamp_names.size():
		_popup.add_item(_stamp_names[_i], _i)

func _on_stamp(id:int)->void:
	if id == SAVE_STAMP_ID:
		creator.prompt_requested.emit("Stamp name", "stamp", creator.tools.save_stamp)
	elif id < _stamp_names.size():
		creator.tools.place_stamp(_stamp_names[id])

const NEW_MOD_ID:int = 1000
const OPEN_FOLDER_ID:int = 1001

func _fill_workspaces()->void:
	var _popup:PopupMenu = _workspace.get_popup()
	_popup.clear()
	_workspace_ids.clear()
	if creator.mod_state == null:
		return
	if OS.has_feature("editor"):
		_workspace_ids.append("")
		_popup.add_radio_check_item("Game (project files)", 0)
	var _mods:Dictionary = creator.mod_state.scan()
	var _ids:Array = _mods.keys()
	_ids.sort()
	for _id:String in _ids:
		_popup.add_radio_check_item("Mod: %s" % _mods[_id].name, _workspace_ids.size())
		_workspace_ids.append(_id)
	for _i:int in _workspace_ids.size():
		_popup.set_item_checked(_i, _workspace_ids[_i] == creator.mod_state.active)
	_popup.add_separator()
	_popup.add_item("New mod...", NEW_MOD_ID)
	_popup.add_item("Open mods folder", OPEN_FOLDER_ID)

func _on_workspace(id:int)->void:
	match id:
		NEW_MOD_ID:
			creator.prompt_requested.emit("New mod name", "my_rooms", creator.create_mod)
		OPEN_FOLDER_ID:
			creator.open_mods_folder()
		_:
			if id < _workspace_ids.size():
				creator.set_workspace(_workspace_ids[id])

func show_message(text:String)->void:
	_message.text = text
	_message_time = 4.0

func _process(delta:float)->void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_message.text = ""

func _refresh()->void:
	var _editing:bool = creator.editing
	_mode_button.text = "EDIT" if _editing else "PLAY"
	_mode_button.modulate = creator.preset.active_color.lightened(0.4) if _editing else Color.WHITE
	for _row:Control in _rows:
		_row.visible = _editing
	for _category:MapCatalogCategory in _category_buttons:
		var _active:bool = _category == creator.category
		_category_buttons[_category].set_pressed_no_signal(_active)
		_category_buttons[_category].text = _category.display_name if _active else ""
		_category_buttons[_category].visible = _editing
	for _tool:int in _tool_buttons:
		_tool_buttons[_tool].set_pressed_no_signal(_tool == creator.tool)
	for _brush:int in _brush_buttons:
		_brush_buttons[_brush].set_pressed_no_signal(_brush == creator.brush)
	for _item:MapCatalogItem in _item_buttons:
		_item_buttons[_item].set_pressed_no_signal(_item == creator.item)
	_dirty.visible = creator.dirty
	_undo.disabled = !creator.can_undo()
	_redo.disabled = !creator.can_redo()
	_save.disabled = !creator.can_edit()
	_workspace.text = creator.workspace_name()
	_problems.text = "OK" if creator.problems.is_empty() else "! %d" % creator.problems.size()
	_problems.modulate = Color.WHITE if creator.problems.is_empty() else Color(1, 0.6, 0.3)
	_problems.visible = _editing && creator.can_edit()
	_workspace.visible = _editing && creator.mod_state != null
	_room_box.visible = _editing && creator.can_edit()
	if creator.layout != null:
		_look.text = creator.layout.look
		for _field:StringName in _flags:
			_flags[_field].set_pressed_no_signal(bool(creator.layout.get(_field)))
	_room_label.text = "room_%s%s" % [creator.key, "" if creator.can_edit() else " (no layout)"]
	if creator.layout != null && !creator.layout.display_name.is_empty():
		_room_label.text += "  " + creator.layout.display_name
