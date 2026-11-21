## The admin topbar, built from the catalog.
## Row 1: Edit/Play toggle, category tabs (keys 1-9), the room name, recent rooms and Browse.
## Row 2: tools, brush, Clean, Undo/Redo, Save, the auto-clean and grid toggles, and messages.
## Row 3: the current category's items, each followed by its variants (Q/E step through them).
## In Play mode only row 1 shows.
class_name MapTopBar
extends PanelContainer

signal browse_requested
signal recent_selected(key:String)

@export var creator:MapCreator

var _mode_button:Button
var _room_label:Label
var _recent:MenuButton
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
		_b.icon = _category.icon if _category.icon != null else _swatch(_category.color)
		_category_buttons[_category] = _b
	var _spacer:Control = Control.new()
	_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(_spacer)
	_room_label = Label.new()
	_room_label.text = "room_" + creator.key
	_row.add_child(_room_label)
	_recent = MenuButton.new()
	_recent.text = "Recent"
	_recent.tooltip_text = "Last visited rooms"
	_recent.flat = false
	_recent.get_popup().id_pressed.connect(func (id:int)->void: recent_selected.emit(creator.settings.recent_rooms[id]))
	_row.add_child(_recent)
	_browse = _button(_row, "Rooms", "Search / switch rooms (%s)" % OS.get_keycode_string(creator.preset.key_browse), func ()->void: browse_requested.emit())
	return _row

func _build_tool_row()->HBoxContainer:
	var _row:HBoxContainer = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", 1)
	var _p:MapCreatorPreset = creator.preset
	for _entry:Array in [[MapCreator.Tool.PAINT, "Paint", _p.key_paint], [MapCreator.Tool.ERASE, "Erase", _p.key_erase],
			[MapCreator.Tool.SELECT, "Select", _p.key_select], [MapCreator.Tool.MOVE, "Move", _p.key_move]]:
		var _b:Button = _button(_row, _entry[1], "%s (%s)" % [_entry[1], OS.get_keycode_string(_entry[2])], creator.set_tool.bind(_entry[0]))
		_b.toggle_mode = true
		_tool_buttons[_entry[0]] = _b
	_row.add_child(VSeparator.new())
	for _entry:Array in [[MapCreator.Brush.ONE, "1", "Single cell"], [MapCreator.Brush.THREE, "3x3", "3x3 brush"], [MapCreator.Brush.RECT, "Rect", "Drag a rectangle"]]:
		var _b:Button = _button(_row, _entry[1], _entry[2], creator.set_brush.bind(_entry[0]))
		_b.toggle_mode = true
		_brush_buttons[_entry[0]] = _b
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
	_b.icon = item.icon if item.icon != null else _swatch(item.color)
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
	_room_label.text = "room_%s%s" % [creator.key, "" if creator.can_edit() else " (no layout)"]
	if creator.layout != null && !creator.layout.display_name.is_empty():
		_room_label.text += "  " + creator.layout.display_name
