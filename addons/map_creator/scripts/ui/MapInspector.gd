## Side panel of the map creator, shown only while an entity is inspected: that entity's
## catalog properties as editors (MapPropertySpec: number, toggle, text, choice, room,
## section). Room settings live in the topbar (MapTopBar). Every change is one undo step.
## Tag props list the rooms using the tag (expandable); room rows and room pickers have an
## open button. A section trigger shows its section's waves and selects its spawners; a
## spawner selects its section's triggers (their section details).
class_name MapInspector
extends PanelContainer

@export var creator:MapCreator
@export var width:float = 120.0

var _box:VBoxContainer
## Prop key -> tag users list expanded.
var _expanded:Dictionary = {}
var _rebuild_queued:bool

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
	if visible && !_rebuild_queued:
		_rebuild_queued = true
		_rebuild_unfocused.call_deferred()

## Edits elsewhere (waves, tags) refresh the lists; not while a field here is typed in.
func _rebuild_unfocused()->void:
	_rebuild_queued = false
	var _focus:Control = get_viewport().gui_get_focus_owner()
	if _focus != null && is_ancestor_of(_focus) && (_focus is LineEdit || _focus is SpinBox):
		return
	rebuild()

func rebuild()->void:
	for _child:Node in _box.get_children():
		_box.remove_child(_child)
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
		var _value:Variant = entity.props.get(_spec.key, _item.defaults.get(_spec.key, null))
		_row(_spec.label if !_spec.label.is_empty() else String(_spec.key), _editor(entity, _spec, _value), _spec.hint)
		if _spec.lists_tag_users && _value != null && !String(_value).is_empty():
			_tag_users(_spec.key, String(_value))
	match _item.bake:
		MapCatalogItem.Bake.TRIGGER:
			_section_details(creator.section_of(entity))
		MapCatalogItem.Bake.SPAWN:
			var _number:int = creator.section_of(entity)
			_button(_box, "Section %d details" % _number, "Select this section's triggers (their inspector shows its waves)",
				creator.select_section_entities.bind(_number, MapCatalogItem.Bake.TRIGGER))
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
			var _row:HBoxContainer = HBoxContainer.new()
			_row.add_theme_constant_override(&"separation", 1)
			var _option:OptionButton = OptionButton.new()
			_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_option.fit_to_longest_item = false
			_row.add_child(_option)
			var _keys:Array = creator.baker.layouts.keys()
			_keys.sort()
			for _key:String in _keys:
				_option.add_item("room_%s  %s" % [_key, creator.baker.layouts[_key].display_name])
				_option.set_item_metadata(_option.item_count - 1, "room_" + _key)
				if value != null && String(value) == "room_" + _key:
					_option.selected = _option.item_count - 1
			_option.item_selected.connect(func (i:int)->void: _set.call(_option.get_item_metadata(i)))
			if value != null && !String(value).is_empty():
				_open_button(_row, String(value).trim_prefix("room_"))
			return _row
	var _line:LineEdit = LineEdit.new()
	_line.text = str(value) if value != null else ""
	_line.text_submitted.connect(func (t:String)->void:
		_line.release_focus()
		if t != str(entity.props.get(spec.key, "")):
			_set.call(t))
	_line.focus_exited.connect(func ()->void:
		if _line.text != str(entity.props.get(spec.key, "")):
			_set.call(_line.text))
	return _line

# --- tag users, sections ------------------------------------------------------------------

## Expandable list of the rooms using `tag`, each with an open button.
func _tag_users(key:StringName, tag:String)->void:
	var _users:Array = creator.tag_users(tag)
	var _open:bool = _expanded.get(key, false)
	var _toggle:Button = _button(_box, "%s Rooms using \"%s\" (%d)" % ["-" if _open else "+", tag, _users.size()],
		"Rooms with stairs / portals tagged or arriving at this tag", func ()->void:
			_expanded[key] = !_open
			rebuild())
	_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if !_open:
		return
	for _user:Dictionary in _users:
		var _row:HBoxContainer = HBoxContainer.new()
		_row.add_theme_constant_override(&"separation", 1)
		_box.add_child(_row)
		var _label:Label = Label.new()
		_label.text = " room_%s%s" % [_user.key, "  (here)" if _user.key == creator.key else ""]
		_label.tooltip_text = "%s\n%s" % [_user.name, ", ".join(_user.uses)]
		_label.mouse_filter = Control.MOUSE_FILTER_PASS
		_label.clip_text = true
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_row.add_child(_label)
		if _user.key != creator.key:
			_open_button(_row, _user.key)

## Waves of section `number` (enemies each) and a button selecting its spawners.
func _section_details(number:int)->void:
	var _spec:Dictionary = creator.layout.section_spec(number - 1)
	if _spec.is_empty():
		_note("Section %d has no waves (Waves panel)" % number)
		return
	var _waves:Array = _spec.get("waves", [])
	var _total:int = 0
	for _wave:Dictionary in _waves:
		_total += int(_wave.get("count", 0))
	_title("Section %d: %d waves, %d enemies" % [number, _waves.size(), _total])
	for _i:int in _waves.size():
		var _wave:Dictionary = _waves[_i]
		var _text:String = "W%d: %d  %s" % [_i + 1, int(_wave.get("count", 0)), ", ".join(_wave.get("enemies", []))]
		if _wave.has("max_alive"):
			_text += "  (max %d)" % int(_wave.max_alive)
		if _wave.get("is_boss", false):
			_text += "  boss " + String(_wave.get("display_name", ""))
		_note(_text)
	var _spawners:int = creator.section_entities(number, MapCatalogItem.Bake.SPAWN).size()
	_button(_box, "Select spawners (%d)" % _spawners, "Select every enemy spawner of section %d" % number,
		creator.select_section_entities.bind(number, MapCatalogItem.Bake.SPAWN))

func _note(text:String)->void:
	var _label:Label = Label.new()
	_label.text = text
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.modulate.a = 0.8
	_box.add_child(_label)

func _button(parent:Control, text:String, hint:String, action:Callable)->Button:
	var _b:Button = Button.new()
	_b.text = text
	_b.tooltip_text = hint
	_b.focus_mode = Control.FOCUS_NONE
	_b.clip_text = true
	_b.pressed.connect(func ()->void: action.call())
	parent.add_child(_b)
	return _b

## Icon button opening room `room_key` (switch_room: unsaved edits ask twice).
func _open_button(parent:Control, room_key:String)->Button:
	var _b:Button = Button.new()
	_b.icon = creator.open_room_icon()
	_b.tooltip_text = "Open room_%s" % room_key
	_b.focus_mode = Control.FOCUS_NONE
	_b.pressed.connect(func ()->void: creator.switch_room(room_key))
	parent.add_child(_b)
	return _b
