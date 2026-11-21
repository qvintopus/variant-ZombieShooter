## Side panel of the map creator, shown only while an entity is inspected: that entity's
## catalog properties as editors (MapPropertySpec: number, toggle, text, choice, room,
## section). Room settings live in the topbar (MapTopBar). Every change is one undo step.
class_name MapInspector
extends PanelContainer

@export var creator:MapCreator
@export var width:float = 120.0

var _box:VBoxContainer

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
	creator.inspected_changed.connect(func (_e:LayoutEntity)->void:
		_sync_visible()
		rebuild())
	creator.mode_changed.connect(func (_v:bool)->void: _sync_visible())
	creator.history_changed.connect(_on_history)
	_sync_visible()
	rebuild()

func _sync_visible()->void:
	visible = creator.editing && creator.can_edit() && creator.inspected != null

func _on_history()->void:
	# undo/redo can drop the inspected entity
	_sync_visible()

func rebuild()->void:
	for _child:Node in _box.get_children():
		_child.queue_free()
	if creator.can_edit() && creator.inspected != null:
		_build_entity(creator.inspected)

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
	var _group:int = creator.inspected_group.size() if entity == creator.inspected else 0
	if _group > 1:
		_title("%d x %s (edited together)" % [_group, _item.display_name if _item != null else entity.item_id])
	else:
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
	_close.text = "Close"
	_close.tooltip_text = "Stop inspecting (Esc)"
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
