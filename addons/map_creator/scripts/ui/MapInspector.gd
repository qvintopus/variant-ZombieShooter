## Side panel of the map creator. With an entity inspected it shows that entity's catalog
## properties as editors (MapPropertySpec: number, toggle, text, choice, room, section).
## Otherwise it shows the room: name, look, start/home, side room, boss section and the
## fight sections (waves) as JSON. Every change is one undo step.
class_name MapInspector
extends PanelContainer

@export var creator:MapCreator
@export var width:float = 120.0

var _box:VBoxContainer
var _sections_text:TextEdit

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# children are ready before the creator: wait for its layout
	if !creator.is_node_ready():
		await creator.ready
	var _style:StyleBoxFlat = StyleBoxFlat.new()
	_style.bg_color = creator.preset.bar_color
	_style.set_content_margin_all(2)
	add_theme_stylebox_override(&"panel", _style)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -width
	offset_top = 40
	var _scroll:ScrollContainer = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override(&"separation", 1)
	_scroll.add_child(_box)
	creator.inspected_changed.connect(func (_e:LayoutEntity)->void: rebuild())
	creator.mode_changed.connect(func (_v:bool)->void: _sync_visible())
	creator.history_changed.connect(_on_history)
	_sync_visible()
	rebuild()

func _sync_visible()->void:
	visible = creator.editing && creator.can_edit()

func _on_history()->void:
	# undo/redo swaps the layout object: show its values
	if creator.inspected == null && !_has_focus():
		rebuild()

func _has_focus()->bool:
	var _focus:Control = get_viewport().gui_get_focus_owner()
	return _focus != null && is_ancestor_of(_focus)

func rebuild()->void:
	for _child:Node in _box.get_children():
		_child.queue_free()
	_sections_text = null
	if !creator.can_edit():
		return
	if creator.inspected != null:
		_build_entity(creator.inspected)
	else:
		_build_room()

func _title(text:String)->void:
	var _label:Label = Label.new()
	_label.text = text
	_label.modulate = creator.preset.active_color.lightened(0.4)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_label)

func _row(label:String, editor:Control, hint:String = "")->void:
	var _label:Label = Label.new()
	_label.text = label
	_label.tooltip_text = hint
	_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_box.add_child(_label)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.tooltip_text = hint
	_box.add_child(editor)

# --- entity -----------------------------------------------------------------------------

func _build_entity(entity:LayoutEntity)->void:
	var _item:MapCatalogItem = creator.catalog.item(entity.item_id)
	_title("%s  (%d, %d)" % [_item.display_name if _item != null else entity.item_id, entity.cell.x, entity.cell.y])
	if _item == null:
		return
	if !_item.description.is_empty():
		var _desc:Label = Label.new()
		_desc.text = _item.description
		_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_desc.modulate.a = 0.7
		_box.add_child(_desc)
	for _spec:MapPropertySpec in _item.properties:
		_row(_spec.label if !_spec.label.is_empty() else String(_spec.key), _editor(entity, _spec, entity.props.get(_spec.key, _item.defaults.get(_spec.key, null))), _spec.hint)
	var _close:Button = Button.new()
	_close.text = "Room settings"
	_close.pressed.connect(creator.inspect.bind(null))
	_box.add_child(_close)

func _editor(entity:LayoutEntity, spec:MapPropertySpec, value:Variant)->Control:
	var _set:Callable = func (v:Variant)->void: creator.set_entity_prop(entity, spec.key, v)
	match spec.type:
		MapPropertySpec.Type.INT, MapPropertySpec.Type.FLOAT, MapPropertySpec.Type.SECTION:
			var _spin:SpinBox = SpinBox.new()
			_spin.min_value = spec.min_value - (1 if spec.optional else 0)
			_spin.max_value = spec.max_value
			if spec.type == MapPropertySpec.Type.SECTION:
				_spin.min_value = 1
				_spin.max_value = clampi(creator.layout.sections.size(), 1, int(spec.max_value))
			_spin.step = 0.1 if spec.type == MapPropertySpec.Type.FLOAT else 1.0
			_spin.value = value if value != null else _spin.min_value
			if spec.optional:
				_spin.tooltip_text = "%s = default" % _spin.min_value
			_spin.value_changed.connect(func (v:float)->void:
				if spec.optional && v < spec.min_value:
					_set.call(null)
				else:
					_set.call(v if spec.type == MapPropertySpec.Type.FLOAT else int(v)))
			return _spin
		MapPropertySpec.Type.BOOL:
			var _check:CheckButton = CheckButton.new()
			_check.button_pressed = bool(value) if value != null else false
			_check.toggled.connect(func (v:bool)->void: _set.call(v))
			return _check
		MapPropertySpec.Type.ENUM:
			var _option:OptionButton = OptionButton.new()
			for _choice:String in spec.options:
				_option.add_item(_choice)
			_option.selected = int(value) if value != null else 0
			_option.item_selected.connect(func (i:int)->void: _set.call(i))
			return _option
		MapPropertySpec.Type.ROOM:
			var _option:OptionButton = OptionButton.new()
			var _keys:Array = creator.baker.layouts.keys()
			_keys.sort()
			for _key:String in _keys:
				_option.add_item("room_%s  %s" % [_key, creator.baker.layouts[_key].display_name])
				_option.set_item_metadata(_option.item_count - 1, "room_" + _key)
				if value != null && String(value) == "room_" + _key:
					_option.selected = _option.item_count - 1
			_option.item_selected.connect(func (i:int)->void: _set.call(_option.get_item_metadata(i)))
			return _option
	var _line:LineEdit = LineEdit.new()
	_line.text = str(value) if value != null else ""
	_line.text_submitted.connect(func (t:String)->void:
		_set.call(t)
		_line.release_focus())
	_line.focus_exited.connect(func ()->void:
		if _line.text != str(entity.props.get(spec.key, "")):
			_set.call(_line.text))
	return _line

# --- room -------------------------------------------------------------------------------

func _build_room()->void:
	var _layout:RoomLayoutResource = creator.layout
	_title("room_%s" % _layout.key)
	var _name:LineEdit = LineEdit.new()
	_name.text = _layout.display_name
	_name.text_submitted.connect(func (t:String)->void:
		creator.set_layout_field(&"display_name", t)
		_name.release_focus())
	_row("Name", _name)
	var _look:OptionButton = OptionButton.new()
	var _looks:PackedStringArray = []
	for _item:MapCatalogItem in creator.catalog.all_items():
		if _item.kind == MapCatalogItem.Kind.FLOOR && String(_item.id).count("_") == 1:
			_looks.append(String(_item.id).trim_prefix("floor_"))
	for _l:String in _looks:
		_look.add_item(_l)
		if _l == _layout.look:
			_look.selected = _look.item_count - 1
	_look.item_selected.connect(func (i:int)->void: creator.set_layout_field(&"look", _looks[i]))
	_row("Look (default floor)", _look)
	for _flag:Array in [[&"start", "Campaign start"], [&"home", "Home base"], [&"writes_balance", "Writes balance.json"]]:
		var _check:CheckButton = CheckButton.new()
		_check.text = _flag[1]
		_check.button_pressed = _layout.get(_flag[0])
		_check.toggled.connect(func (v:bool)->void: creator.set_layout_field(_flag[0], v))
		_box.add_child(_check)
	for _field:Array in [[&"side_room", "Side room section (0 none)"], [&"boss_section", "Boss section (0 none)"]]:
		var _spin:SpinBox = SpinBox.new()
		_spin.max_value = 3
		_spin.value = _layout.get(_field[0])
		_spin.value_changed.connect(func (v:float)->void: creator.set_layout_field(_field[0], int(v)))
		_row(_field[1], _spin)
	_sections_text = TextEdit.new()
	_sections_text.custom_minimum_size.y = 90
	_sections_text.text = JSON.stringify(_layout.sections, " ")
	_row("Sections (waves)", _sections_text, "[{waves: [{count, enemies: [ids], is_boss?, display_name?, max_alive?}], spawn_density?, max_simultaneous?}]")
	var _apply:Button = Button.new()
	_apply.text = "Apply sections"
	_apply.pressed.connect(_apply_sections)
	_box.add_child(_apply)

func _apply_sections()->void:
	var _parsed:Variant = JSON.parse_string(_sections_text.text)
	if !(_parsed is Array):
		creator.message.emit("Sections must be a JSON array")
		return
	var _list:Array[Dictionary] = []
	for _section:Variant in _parsed:
		if !(_section is Dictionary) || !(_section.get("waves") is Array):
			creator.message.emit("Each section needs a waves array")
			return
		_list.append(_whole_ints(_section))
	creator.set_layout_field(&"sections", _list)
	creator.message.emit("Sections applied (%d)" % _list.size())

## JSON numbers come back as floats: whole ones become ints again (counts, densities).
func _whole_ints(value:Variant)->Variant:
	if value is float && is_equal_approx(value, roundf(value)):
		return int(value)
	if value is Array:
		return value.map(_whole_ints)
	if value is Dictionary:
		var _out:Dictionary = {}
		for _k:Variant in value:
			_out[_k] = _whole_ints(value[_k])
		return _out
	return value
