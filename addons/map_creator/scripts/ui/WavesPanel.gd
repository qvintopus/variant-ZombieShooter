## Waves editor (topbar Waves / K in Edit mode), a left side panel: the room's fight
## sections, each with its flags (boss, side room, spawn density, spawner cap) and waves,
## each wave with its count, alive cap, boss name and enemy rows (ids from balance.json).
## Every change is one undo step (set_layout_field). Clicking a section's title highlights
## its spawns, triggers and barriers on the map; Test saves, reloads and starts the fight.
class_name WavesPanel
extends PanelContainer

@export var creator:MapCreator
@export var width:float = 150.0

var _box:VBoxContainer
var _enemy_ids:PackedStringArray = []

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if !creator.is_node_ready():
		await creator.ready
	var _style:StyleBoxFlat = StyleBoxFlat.new()
	_style.bg_color = creator.preset.bar_color
	_style.set_content_margin_all(2)
	add_theme_stylebox_override(&"panel", _style)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_right = width
	offset_top = 40
	var _scroll:ScrollContainer = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override(&"separation", 1)
	_scroll.add_child(_box)
	_enemy_ids = enemy_ids()
	creator.waves_requested.connect(toggle)
	creator.history_changed.connect(_on_change)
	creator.layout_changed.connect(_on_change)
	creator.mode_changed.connect(func (editing:bool)->void:
		if !editing:
			close())

func toggle()->void:
	if visible:
		close()
	else:
		open()

func open()->void:
	if !creator.can_edit():
		creator.message.emit("No layout for this room")
		return
	visible = true
	rebuild()

func close()->void:
	visible = false
	creator.highlight_section = 0

## Enemy and boss ids of balance.json (the baker's), sorted.
func enemy_ids()->PackedStringArray:
	var _ids:PackedStringArray = []
	if creator.baker != null && creator.baker.has_method(&"balance"):
		var _data:Dictionary = creator.baker.call(&"balance")
		for _category:String in ["enemies", "bosses"]:
			for _id:String in _data.get(_category, {}):
				_ids.append(_id)
	_ids.sort()
	return _ids

func _on_change()->void:
	if visible && !_has_focus():
		rebuild()

func _has_focus()->bool:
	var _focus:Control = get_viewport().gui_get_focus_owner()
	return _focus != null && is_ancestor_of(_focus) && (_focus is LineEdit || _focus is SpinBox)

# --- editing (each one undo step) -------------------------------------------------------

func sections()->Array[Dictionary]:
	var _copy:Array[Dictionary] = []
	for _section:Dictionary in creator.layout.sections:
		_copy.append(_section.duplicate(true))
	return _copy

func commit(list:Array[Dictionary])->void:
	creator.set_layout_field(&"sections", list)

func change_section(index:int, change:Callable)->void:
	var _list:Array[Dictionary] = sections()
	change.call(_list[index])
	commit(_list)

func change_wave(section:int, wave:int, change:Callable)->void:
	var _list:Array[Dictionary] = sections()
	change.call(_list[section].waves[wave])
	commit(_list)

func add_section()->void:
	if creator.layout.sections.size() >= creator.baker.section_paths.size():
		creator.message.emit("At most %d sections" % creator.baker.section_paths.size())
		return
	var _list:Array[Dictionary] = sections()
	_list.append({"waves": [{"count": 4, "enemies": [_enemy_ids[0] if !_enemy_ids.is_empty() else "zombie"]}]})
	commit(_list)

func remove_section(index:int)->void:
	var _list:Array[Dictionary] = sections()
	_list.remove_at(index)
	creator.edit(func ()->void:
		var _layout:RoomLayoutResource = creator.layout
		_layout.sections = _list
		# flags pointing past the end go back to none
		if _layout.boss_section > _list.size():
			_layout.boss_section = 0
		if _layout.side_room > _list.size():
			_layout.side_room = 0)

func move_section(index:int, step:int)->void:
	var _to:int = index + step
	var _list:Array[Dictionary] = sections()
	if _to < 0 || _to >= _list.size():
		return
	var _moved:Dictionary = _list[index]
	_list[index] = _list[_to]
	_list[_to] = _moved
	commit(_list)

func add_wave(section:int, copy_of:int = -1)->void:
	change_section(section, func (s:Dictionary)->void:
		var _wave:Dictionary = s.waves[copy_of].duplicate(true) if copy_of >= 0 else {"count": 4, "enemies": [_enemy_ids[0] if !_enemy_ids.is_empty() else "zombie"]}
		s.waves.insert(copy_of + 1 if copy_of >= 0 else s.waves.size(), _wave))

func remove_wave(section:int, wave:int)->void:
	change_section(section, func (s:Dictionary)->void: s.waves.remove_at(wave))

func move_wave(section:int, wave:int, step:int)->void:
	change_section(section, func (s:Dictionary)->void:
		var _to:int = wave + step
		if _to < 0 || _to >= s.waves.size():
			return
		var _moved:Dictionary = s.waves[wave]
		s.waves[wave] = s.waves[_to]
		s.waves[_to] = _moved)

func set_enemy(section:int, wave:int, slot:int, id:String)->void:
	change_wave(section, wave, func (w:Dictionary)->void:
		if slot >= w.enemies.size():
			w.enemies.append(id)
		else:
			w.enemies[slot] = id)

func remove_enemy(section:int, wave:int, slot:int)->void:
	change_wave(section, wave, func (w:Dictionary)->void:
		if w.enemies.size() > 1:
			w.enemies.remove_at(slot))

## Section number (1-based) of the boss / side room flags.
func set_flag(field:StringName, section_number:int, on:bool)->void:
	creator.set_layout_field(field, section_number if on else 0)

## Spawns, triggers and barriers of a section (1-based): highlighted and selected.
func focus_section(number:int)->void:
	creator.highlight_section = number
	var _entries:Array = []
	for _entity:LayoutEntity in creator.layout.entities:
		if _entity.props.has("section") && int(_entity.props.section) == number:
			_entries.append({"cell": _entity.cell, "type": _entity.item_id})
	creator.selection.set_entries(_entries)

# --- UI ---------------------------------------------------------------------------------

func rebuild()->void:
	for _child:Node in _box.get_children():
		_box.remove_child(_child)
		_child.queue_free()
	if !creator.can_edit():
		return
	var _head:HBoxContainer = _hbox(_box)
	var _title:Label = Label.new()
	_title.text = "Sections"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(_title)
	_button(_head, "+", "Add a section", add_section)
	_button(_head, "x", "Close (%s)" % OS.get_keycode_string(creator.preset.key_waves), close)
	var _layout:RoomLayoutResource = creator.layout
	for _i:int in _layout.sections.size():
		_build_section(_i, _layout.sections[_i])
	if _layout.sections.is_empty():
		var _none:Label = Label.new()
		_none.text = "No fight in this room."
		_box.add_child(_none)

func _build_section(index:int, section:Dictionary)->void:
	var _number:int = index + 1
	var _layout:RoomLayoutResource = creator.layout
	_box.add_child(HSeparator.new())
	var _row:HBoxContainer = _hbox(_box)
	var _name:Button = _button(_row, "Section %d" % _number, "Highlight and select its spawns, triggers and barriers", focus_section.bind(_number))
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.modulate = MapOverlay.section_color(_number)
	_button(_row, "Test", "Save, reload the room and start this fight", creator.test_section.bind(_number))
	_button(_row, "^", "Move up", move_section.bind(index, -1))
	_button(_row, "v", "Move down", move_section.bind(index, 1))
	_button(_row, "x", "Remove the section", remove_section.bind(index))
	var _flags:HBoxContainer = _hbox(_box)
	_check(_flags, "Boss", _layout.boss_section == _number, "The boss fight (must be the last section)", set_flag.bind(&"boss_section", _number))
	_check(_flags, "Side", _layout.side_room == _number, "An optional alcove (must be the last section)", set_flag.bind(&"side_room", _number))
	var _numbers:HBoxContainer = _hbox(_box)
	_spin(_numbers, "Dens", int(section.get("spawn_density", 1)), 1, 6, "Spawn density", func (v:int)->void:
		change_section(index, func (s:Dictionary)->void:
			if v == 1:
				s.erase("spawn_density")
			else:
				s.spawn_density = v))
	_spin(_numbers, "Cap", int(section.get("max_simultaneous", 1)), 1, 20, "Enemies alive per spawner (spawners without their own value)", func (v:int)->void:
		change_section(index, func (s:Dictionary)->void:
			if v == 1:
				s.erase("max_simultaneous")
			else:
				s.max_simultaneous = v))
	var _waves:Array = section.get("waves", [])
	for _j:int in _waves.size():
		_build_wave(index, _j, _waves[_j])
	_button(_hbox(_box), "+ wave", "Add a wave", add_wave.bind(index))

func _build_wave(section:int, wave:int, data:Dictionary)->void:
	var _row:HBoxContainer = _hbox(_box)
	var _label:Label = Label.new()
	_label.text = " W%d" % (wave + 1)
	_row.add_child(_label)
	_spin(_row, "", int(data.get("count", 1)), 1, 200, "Enemies in the wave", func (v:int)->void:
		change_wave(section, wave, func (w:Dictionary)->void: w.count = v))
	_spin(_row, "max", int(data.get("max_alive", 0)), 0, 50, "Alive at once (0 = no cap)", func (v:int)->void:
		change_wave(section, wave, func (w:Dictionary)->void:
			if v == 0:
				w.erase("max_alive")
			else:
				w.max_alive = v))
	_button(_row, "+", "Duplicate the wave", add_wave.bind(section, wave))
	_button(_row, "^", "Move up", move_wave.bind(section, wave, -1))
	_button(_row, "x", "Remove the wave", remove_wave.bind(section, wave))
	var _boss_row:HBoxContainer = _hbox(_box)
	_check(_boss_row, "Boss", bool(data.get("is_boss", false)), "A boss wave (shows its name)", func (on:bool)->void:
		change_wave(section, wave, func (w:Dictionary)->void:
			if on:
				w.is_boss = true
				w.display_name = w.get("display_name", "Boss")
			else:
				w.erase("is_boss")
				w.erase("display_name")))
	if data.get("is_boss", false):
		var _name:LineEdit = LineEdit.new()
		_name.text = String(data.get("display_name", ""))
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name.text_submitted.connect(func (t:String)->void:
			change_wave(section, wave, func (w:Dictionary)->void: w.display_name = LayoutCodec.safe_text(t)))
		_boss_row.add_child(_name)
	var _enemies:Array = data.get("enemies", [])
	for _k:int in _enemies.size():
		var _enemy_row:HBoxContainer = _hbox(_box)
		var _option:OptionButton = OptionButton.new()
		_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_option.fit_to_longest_item = false
		for _id:String in _enemy_ids:
			_option.add_item(_id)
		var _at:int = _enemy_ids.find(String(_enemies[_k]))
		if _at == -1:
			_option.add_item(String(_enemies[_k]))
			_at = _option.item_count - 1
		_option.select(_at)
		_option.item_selected.connect(func (i:int)->void: set_enemy(section, wave, _k, _option.get_item_text(i)))
		_enemy_row.add_child(_option)
		_button(_enemy_row, "x", "Remove this enemy type", remove_enemy.bind(section, wave, _k))
	_button(_hbox(_box), "  + enemy", "Add an enemy type to the wave", set_enemy.bind(section, wave, _enemies.size(), _enemy_ids[0] if !_enemy_ids.is_empty() else "zombie"))

func _hbox(parent:Control)->HBoxContainer:
	var _row:HBoxContainer = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", 1)
	parent.add_child(_row)
	return _row

func _button(parent:Control, text:String, tooltip:String, action:Callable)->Button:
	var _b:Button = Button.new()
	_b.text = text
	_b.tooltip_text = tooltip
	_b.focus_mode = Control.FOCUS_NONE
	_b.pressed.connect(func ()->void: action.call())
	parent.add_child(_b)
	return _b

func _check(parent:Control, text:String, on:bool, tooltip:String, action:Callable)->void:
	var _c:CheckBox = CheckBox.new()
	_c.text = text
	_c.tooltip_text = tooltip
	_c.button_pressed = on
	_c.focus_mode = Control.FOCUS_NONE
	_c.toggled.connect(func (v:bool)->void: action.call(v))
	parent.add_child(_c)

func _spin(parent:Control, label:String, value:int, min_value:int, max_value:int, tooltip:String, action:Callable)->void:
	if !label.is_empty():
		var _l:Label = Label.new()
		_l.text = label
		parent.add_child(_l)
	var _s:SpinBox = SpinBox.new()
	_s.min_value = min_value
	_s.max_value = max_value
	_s.value = value
	_s.tooltip_text = tooltip
	_s.custom_minimum_size.x = 34
	_s.value_changed.connect(func (v:float)->void: action.call(int(v)))
	parent.add_child(_s)
