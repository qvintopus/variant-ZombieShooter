## Waves editor (topbar Waves / K in Edit mode), a left side panel: the room's fight
## sections as color-coded cards (border = the section's map color), each with its flags
## (boss, side room, spawn density, spawner cap), its linked map entities and its waves as
## nested, cooler cards (count, alive cap, boss name, enemy rows from balance.json).
## Every change is one undo step (set_layout_field / creator.edit). Deleting asks first
## (creator.confirm_requested) and says what else goes: a section's triggers, spawners and
## barriers are deleted or moved to a neighbour section, later sections renumber (their
## entities and boss / side flags follow). Inspecting a sectioned entity scrolls its
## section into view and flashes it. Clicking a section's title highlights its spawns,
## triggers and barriers on the map; Test saves, reloads and starts the fight.
class_name WavesPanel
extends PanelContainer

@export var creator:MapCreator
## 0 = the preset's waves_panel_width.
@export var width:float = 0.0

var _scroll:ScrollContainer
var _box:VBoxContainer
var _enemy_ids:PackedStringArray = []
## Section number -> collapsed.
var _collapsed:Dictionary = {}
## Section number -> its card (current build).
var _cards:Dictionary = {}
## Section of the inspected entity (0 = none): scrolled to and flashed.
var focus_number:int
var _rebuild_queued:bool
## Section / wave / enemy counts the UI was built for (a changed shape always rebuilds).
var _built_shape:String

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if !creator.is_node_ready():
		await creator.ready
	var _style:StyleBoxFlat = StyleBoxFlat.new()
	_style.bg_color = creator.preset.bar_color
	_style.set_content_margin_all(3)
	add_theme_stylebox_override(&"panel", _style)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_right = width if width > 0.0 else creator.preset.waves_panel_width
	offset_top = 40
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override(&"separation", 4)
	_scroll.add_child(_box)
	_enemy_ids = enemy_ids()
	creator.waves_requested.connect(toggle)
	creator.history_changed.connect(_on_change)
	creator.layout_changed.connect(_on_change)
	creator.inspected_changed.connect(_on_inspected)
	creator.waves_section_requested.connect(open_section)
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
	if creator.inspected != null && _sectioned(creator.inspected):
		_on_inspected(creator.inspected)
	else:
		rebuild()

## Opens (or keeps open) on section `number`: expanded, highlighted, scrolled to.
func open_section(number:int)->void:
	if !creator.can_edit():
		creator.message.emit("No layout for this room")
		return
	visible = true
	if number < 1 || number > creator.layout.sections.size():
		rebuild()
		return
	focus_number = number
	_collapsed[number] = false
	creator.highlight_section = number
	rebuild()
	scroll_to(number)

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

func _default_enemy()->String:
	return _enemy_ids[0] if !_enemy_ids.is_empty() else "zombie"

func _on_change()->void:
	if !visible || _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild_later.call_deferred()

## Not while a number / name here is typed in, unless the shape changed (undo, deletes):
## then the typed field goes (its indices would be stale).
func _rebuild_later()->void:
	_rebuild_queued = false
	if !visible:
		return
	if _has_focus():
		if _shape() == _built_shape:
			return
		get_viewport().gui_release_focus()
	rebuild(true)

func _has_focus()->bool:
	var _focus:Control = get_viewport().gui_get_focus_owner()
	return _focus != null && is_ancestor_of(_focus) && (_focus is LineEdit || _focus is SpinBox)

func _shape()->String:
	if !creator.can_edit():
		return ""
	var _parts:PackedStringArray = []
	for _section:Dictionary in creator.layout.sections:
		var _waves:PackedStringArray = []
		for _wave:Dictionary in _section.get("waves", []):
			_waves.append("%d%s" % [_wave.get("enemies", []).size(), "b" if _wave.get("is_boss", false) else ""])
		_parts.append(",".join(_waves))
	return "|".join(_parts)

func _on_inspected(entity:LayoutEntity)->void:
	if entity == null || !_sectioned(entity):
		return
	focus_number = creator.section_of(entity)
	if visible:
		open_section(focus_number)

## Brings section `number`'s card to the top of the panel and flashes it.
func scroll_to(number:int)->void:
	await get_tree().process_frame
	var _card:Control = _cards.get(number)
	if _card == null || !is_instance_valid(_card):
		return
	_scroll.scroll_vertical = int(_card.position.y) - 2
	_card.modulate = creator.preset.focus_flash_color
	var _tween:Tween = _card.create_tween()
	_tween.tween_property(_card, ^"modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)

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
	if index < 0 || index >= _list.size():
		return
	change.call(_list[index])
	commit(_list)

func change_wave(section:int, wave:int, change:Callable)->void:
	var _list:Array[Dictionary] = sections()
	if section < 0 || section >= _list.size() || wave < 0 || wave >= _list[section].get("waves", []).size():
		return
	change.call(_list[section].waves[wave])
	commit(_list)

## Structural edits drop the typed field first (so the panel rebuilds).
func _structural()->void:
	if is_inside_tree():
		get_viewport().gui_release_focus()

func add_section()->void:
	_structural()
	if creator.layout.sections.size() >= creator.baker.section_paths.size():
		creator.message.emit("At most %d sections" % creator.baker.section_paths.size())
		return
	var _list:Array[Dictionary] = sections()
	_list.append({"waves": [{"count": 4, "enemies": [_default_enemy()]}]})
	commit(_list)
	_collapsed[_list.size()] = false

## Removes section `index` (0-based). Its entities are deleted, or (keep) moved to the
## section taking the previous one's place; later sections' entities and the boss / side
## flags renumber. One undo step.
func remove_section(index:int, delete_entities:bool = true)->void:
	_structural()
	var _list:Array[Dictionary] = sections()
	if index < 0 || index >= _list.size():
		return
	var _number:int = index + 1
	_list.remove_at(index)
	var _target:int = keep_target(_number)
	creator.edit(func ()->void:
		var _layout:RoomLayoutResource = creator.layout
		_layout.sections = _list
		for _entity:LayoutEntity in _layout.entities.duplicate():
			if !_sectioned(_entity):
				continue
			var _n:int = creator.section_of(_entity)
			if _n == _number:
				if delete_entities || _target == 0:
					_layout.entities.erase(_entity)
				else:
					_entity.props.section = _target
			elif _n > _number:
				_entity.props.section = _n - 1
		for _field:StringName in [&"boss_section", &"side_room"]:
			var _v:int = _layout.get(_field)
			if _v == _number:
				_layout.set(_field, 0)
			elif _v > _number:
				_layout.set(_field, _v - 1))
	_shift_collapsed(_number)
	if creator.highlight_section == _number:
		creator.highlight_section = 0

## Section number (after the removal of `number`) its kept entities move to; 0 = none left.
func keep_target(number:int)->int:
	if creator.layout.sections.size() <= 1:
		return 0
	return number - 1 if number > 1 else 1

func _shift_collapsed(removed:int)->void:
	var _new:Dictionary = {}
	for _n:int in _collapsed:
		if _n < removed:
			_new[_n] = _collapsed[_n]
		elif _n > removed:
			_new[_n - 1] = _collapsed[_n]
	_collapsed = _new

## Swaps section `index` with its neighbour; entities and boss / side flags follow.
func move_section(index:int, step:int)->void:
	_structural()
	var _to:int = index + step
	var _list:Array[Dictionary] = sections()
	if index < 0 || _to < 0 || _to >= _list.size():
		return
	var _moved:Dictionary = _list[index]
	_list[index] = _list[_to]
	_list[_to] = _moved
	var _a:int = index + 1
	var _b:int = _to + 1
	creator.edit(func ()->void:
		var _layout:RoomLayoutResource = creator.layout
		_layout.sections = _list
		for _entity:LayoutEntity in _layout.entities:
			if !_sectioned(_entity):
				continue
			var _n:int = creator.section_of(_entity)
			if _n == _a:
				_entity.props.section = _b
			elif _n == _b:
				_entity.props.section = _a
		for _field:StringName in [&"boss_section", &"side_room"]:
			var _v:int = _layout.get(_field)
			if _v == _a:
				_layout.set(_field, _b)
			elif _v == _b:
				_layout.set(_field, _a))
	var _ca:bool = _collapsed.get(_a, false)
	_collapsed[_a] = _collapsed.get(_b, false)
	_collapsed[_b] = _ca
	if creator.highlight_section == _a:
		creator.highlight_section = _b
	elif creator.highlight_section == _b:
		creator.highlight_section = _a

func add_wave(section:int, copy_of:int = -1)->void:
	_structural()
	change_section(section, func (s:Dictionary)->void:
		if !s.has("waves"):
			s.waves = []
		var _copy:bool = copy_of >= 0 && copy_of < s.waves.size()
		var _wave:Dictionary = s.waves[copy_of].duplicate(true) if _copy else {"count": 4, "enemies": [_default_enemy()]}
		s.waves.insert(copy_of + 1 if _copy else s.waves.size(), _wave))

func remove_wave(section:int, wave:int)->void:
	_structural()
	change_section(section, func (s:Dictionary)->void:
		if wave >= 0 && wave < s.get("waves", []).size():
			s.waves.remove_at(wave))

func move_wave(section:int, wave:int, step:int)->void:
	_structural()
	change_section(section, func (s:Dictionary)->void:
		var _to:int = wave + step
		if wave < 0 || _to < 0 || _to >= s.waves.size():
			return
		var _moved:Dictionary = s.waves[wave]
		s.waves[wave] = s.waves[_to]
		s.waves[_to] = _moved)

func set_enemy(section:int, wave:int, slot:int, id:String)->void:
	change_wave(section, wave, func (w:Dictionary)->void:
		if !w.has("enemies"):
			w.enemies = []
		if slot >= w.enemies.size():
			w.enemies.append(id)
		else:
			w.enemies[slot] = id)

func add_enemy(section:int, wave:int)->void:
	_structural()
	var _list:Array = creator.layout.sections[section].waves[wave].get("enemies", []) if _valid_wave(section, wave) else []
	set_enemy(section, wave, _list.size(), _default_enemy())

func remove_enemy(section:int, wave:int, slot:int)->void:
	_structural()
	change_wave(section, wave, func (w:Dictionary)->void:
		if w.enemies.size() > 1 && slot < w.enemies.size():
			w.enemies.remove_at(slot))

func _valid_wave(section:int, wave:int)->bool:
	var _all:Array = creator.layout.sections
	return section >= 0 && section < _all.size() && wave >= 0 && wave < _all[section].get("waves", []).size()

## Section number (1-based) of the boss / side room flags.
func set_flag(field:StringName, section_number:int, on:bool)->void:
	creator.set_layout_field(field, section_number if on else 0)

## Spawns, triggers and barriers of a section (1-based): highlighted and selected.
func focus_section(number:int)->void:
	creator.highlight_section = number
	var _entries:Array = []
	for _entity:LayoutEntity in creator.layout.entities:
		if _sectioned(_entity) && creator.section_of(_entity) == number:
			_entries.append({"cell": _entity.cell, "type": _entity.item_id})
	creator.selection.set_entries(_entries)

## The entity's item has a section property (triggers, spawners, barriers, gates).
func _sectioned(entity:LayoutEntity)->bool:
	var _item:MapCatalogItem = creator.catalog.item(entity.item_id)
	return _item != null && _item.properties.any(func (p:MapPropertySpec)->bool: return p.type == MapPropertySpec.Type.SECTION)

## Map entities of section `number`: {triggers, spawners, barriers, total}.
func section_usage(number:int)->Dictionary:
	var _usage:Dictionary = {
		"triggers": creator.section_entities(number, MapCatalogItem.Bake.TRIGGER).size(),
		"spawners": creator.section_entities(number, MapCatalogItem.Bake.SPAWN).size(),
		"barriers": creator.section_entities(number, MapCatalogItem.Bake.BLOCK_WALL).size(),
	}
	var _total:int = 0
	for _entity:LayoutEntity in creator.layout.entities:
		if _sectioned(_entity) && creator.section_of(_entity) == number:
			_total += 1
	_usage.total = _total
	return _usage

func _enemy_total(section:Dictionary)->int:
	var _total:int = 0
	for _wave:Dictionary in section.get("waves", []):
		_total += int(_wave.get("count", 0))
	return _total

## "1 wave", "3 waves" (`plural`: irregular form).
static func _plural(count:int, word:String, plural:String = "")->String:
	return "%d %s" % [count, word if count == 1 else (plural if !plural.is_empty() else word + "s")]

# --- delete prompts ---------------------------------------------------------------------

## Asks before removing section `index`, listing what goes with it.
func ask_remove_section(index:int)->void:
	if index < 0 || index >= creator.layout.sections.size():
		return
	var _number:int = index + 1
	var _section:Dictionary = creator.layout.sections[index]
	var _usage:Dictionary = section_usage(_number)
	var _lines:PackedStringArray = []
	_lines.append("%s, %s." % [_plural(_section.get("waves", []).size(), "wave"), _plural(_enemy_total(_section), "enemy", "enemies")])
	if _usage.total > 0:
		var _parts:PackedStringArray = []
		for _entry:Array in [["triggers", "trigger"], ["spawners", "spawner"], ["barriers", "barrier/gate", "barriers/gates"]]:
			if _usage[_entry[0]] > 0:
				_parts.append(_plural(_usage[_entry[0]], _entry[1], _entry[2] if _entry.size() > 2 else ""))
		var _other:int = _usage.total - _usage.triggers - _usage.spawners - _usage.barriers
		if _other > 0:
			_parts.append(_plural(_other, "other entity", "other entities"))
		_lines.append("On the map: %s." % ", ".join(_parts))
	else:
		_lines.append("Nothing on the map uses it.")
	if creator.layout.boss_section == _number:
		_lines.append("It is the boss section (flag cleared).")
	if creator.layout.side_room == _number:
		_lines.append("It is the side room (flag cleared).")
	var _count:int = creator.layout.sections.size()
	if _number == _count - 1:
		_lines.append("Section %d becomes %d (its map entities follow)." % [_count, _number])
	elif _number < _count:
		_lines.append("Sections %d-%d become %d-%d (their map entities follow)." % [_number + 1, _count, _number, _count - 1])
	var _choices:Array = []
	var _target:int = keep_target(_number)
	if _usage.total > 0:
		_choices.append({"label": "Delete section + its %s" % _plural(_usage.total, "map entity", "map entities"),
			"action": remove_section.bind(index, true), "danger": true})
		if _target > 0:
			var _to:int = _target + 1 if _target >= _number else _target
			_choices.append({"label": "Delete section, move entities to Section %d" % _to, "action": remove_section.bind(index, false), "danger": false})
	else:
		_choices.append({"label": "Delete section", "action": remove_section.bind(index, true), "danger": true})
	creator.confirm_requested.emit("Delete Section %d?" % _number, "\n".join(_lines), _choices)

## Asks before removing a wave; its section's only wave also offers the whole section.
func ask_remove_wave(section:int, wave:int)->void:
	if !_valid_wave(section, wave):
		return
	var _waves:Array = creator.layout.sections[section].waves
	var _data:Dictionary = _waves[wave]
	var _lines:PackedStringArray = []
	_lines.append("%s of %s." % [_plural(int(_data.get("count", 0)), "enemy", "enemies"), ", ".join(_data.get("enemies", []))])
	if _data.get("is_boss", false):
		_lines.append("Boss wave \"%s\"." % String(_data.get("display_name", "")))
	_lines.append("Spawners belong to the section: none are removed.")
	if wave < _waves.size() - 1:
		_lines.append("Waves %d-%d move up." % [wave + 2, _waves.size()])
	var _choices:Array = [{"label": "Delete wave", "action": remove_wave.bind(section, wave), "danger": true}]
	if _waves.size() == 1:
		_lines.append("It is the only wave: the section would have no fight.")
		_choices.append({"label": "Delete whole Section %d..." % (section + 1), "action": ask_remove_section.bind(section), "danger": false})
	creator.confirm_requested.emit("Delete Wave %d of Section %d?" % [wave + 1, section + 1], "\n".join(_lines), _choices)

# --- UI ---------------------------------------------------------------------------------

func rebuild(keep_scroll:bool = false)->void:
	var _scroll_at:int = _scroll.scroll_vertical if _scroll != null else 0
	for _child:Node in _box.get_children():
		_box.remove_child(_child)
		_child.queue_free()
	_cards.clear()
	_built_shape = _shape()
	if !creator.can_edit():
		return
	var _layout:RoomLayoutResource = creator.layout
	var _head:HBoxContainer = _hbox(_box)
	var _title:Label = Label.new()
	_title.text = "Sections  %d/%d" % [_layout.sections.size(), creator.baker.section_paths.size()]
	_title.modulate = creator.preset.active_color.lightened(0.4)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(_title)
	var _add:Button = _button(_head, "+ Section", "Add a section", add_section)
	_add.disabled = _layout.sections.size() >= creator.baker.section_paths.size()
	_button(_head, "x", "Close (%s)" % OS.get_keycode_string(creator.preset.key_waves), close)
	for _i:int in _layout.sections.size():
		_build_section(_i, _layout.sections[_i])
	if _layout.sections.is_empty():
		var _none:Label = Label.new()
		_none.text = "No fight in this room. Add a section, then place its trigger and spawners."
		_none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_none.modulate.a = 0.7
		_box.add_child(_none)
	if keep_scroll:
		_restore_scroll(_scroll_at)

func _restore_scroll(value:int)->void:
	await get_tree().process_frame
	_scroll.scroll_vertical = value

func _card(parent:Control, bg:Color, accent:Color, border:int)->VBoxContainer:
	var _panel:PanelContainer = PanelContainer.new()
	var _style:StyleBoxFlat = StyleBoxFlat.new()
	_style.bg_color = bg
	_style.border_color = accent
	_style.border_width_left = border
	_style.set_corner_radius_all(2)
	_style.content_margin_left = 2 + border
	_style.content_margin_right = 2
	_style.content_margin_top = 2
	_style.content_margin_bottom = 2
	_panel.add_theme_stylebox_override(&"panel", _style)
	parent.add_child(_panel)
	var _inner:VBoxContainer = VBoxContainer.new()
	_inner.add_theme_constant_override(&"separation", 2)
	_panel.add_child(_inner)
	return _inner

func _build_section(index:int, section:Dictionary)->void:
	var _number:int = index + 1
	var _layout:RoomLayoutResource = creator.layout
	var _color:Color = MapOverlay.section_color(_number)
	var _bg:Color = creator.preset.section_card_color.lerp(_color.darkened(0.6), 0.25)
	var _inner:VBoxContainer = _card(_box, _bg, _color, 3)
	_cards[_number] = _inner.get_parent()
	var _waves:Array = section.get("waves", [])
	var _collapsed_now:bool = _collapsed.get(_number, false)
	# header
	var _row:HBoxContainer = _hbox(_inner)
	_button(_row, "+" if _collapsed_now else "-", "Expand / collapse", func ()->void:
		_collapsed[_number] = !_collapsed_now
		rebuild(true))
	var _name:Button = _button(_row, "Section %d" % _number, "Highlight and select its spawns, triggers and barriers", focus_section.bind(_number))
	_name.add_theme_color_override(&"font_color", _color)
	_name.add_theme_color_override(&"font_hover_color", _color.lightened(0.3))
	_name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var _tags:PackedStringArray = []
	if _layout.boss_section == _number:
		_tags.append("BOSS")
	if _layout.side_room == _number:
		_tags.append("SIDE")
	var _summary:Label = Label.new()
	_summary.text = "%s%dw %d" % [(" ".join(_tags) + " ") if !_tags.is_empty() else "", _waves.size(), _enemy_total(section)]
	_summary.tooltip_text = "%s, %s in total" % [_plural(_waves.size(), "wave"), _plural(_enemy_total(section), "enemy", "enemies")]
	_summary.mouse_filter = Control.MOUSE_FILTER_PASS
	_summary.modulate.a = 0.75
	_row.add_child(_summary)
	_button(_row, "Test", "Save, reload the room and start this fight", creator.test_section.bind(_number))
	_button(_row, "^", "Move up (its map entities follow)", move_section.bind(index, -1)).disabled = index == 0
	_button(_row, "v", "Move down (its map entities follow)", move_section.bind(index, 1)).disabled = index == _layout.sections.size() - 1
	_danger(_button(_row, "Del", "Delete the section (asks what to do with its map entities)", ask_remove_section.bind(index)))
	if _collapsed_now:
		return
	# flags + numbers
	var _flags:HBoxContainer = _hbox(_inner)
	_check(_flags, "Boss", _layout.boss_section == _number, "The boss fight (must be the last section)", set_flag.bind(&"boss_section", _number))
	_check(_flags, "Side room", _layout.side_room == _number, "An optional alcove (must be the last section)", set_flag.bind(&"side_room", _number))
	var _numbers:HBoxContainer = _hbox(_inner)
	_spin(_numbers, "Density", int(section.get("spawn_density", 1)), 1, 6, "Spawn density", func (v:int)->void:
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
	# linked map entities
	var _usage:Dictionary = section_usage(_number)
	var _links:HBoxContainer = _hbox(_inner)
	for _entry:Array in [[MapCatalogItem.Bake.TRIGGER, "triggers", "Trig"], [MapCatalogItem.Bake.SPAWN, "spawners", "Spawn"], [MapCatalogItem.Bake.BLOCK_WALL, "barriers", "Bar"]]:
		var _n:int = _usage[_entry[1]]
		var _b:Button = _button(_links, "%s %d" % [_entry[2], _n], "Select section %d's %s" % [_number, _entry[1]], creator.select_section_entities.bind(_number, _entry[0]))
		_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_b.disabled = _n == 0
		if _entry[0] == MapCatalogItem.Bake.TRIGGER && _n == 0:
			_b.add_theme_color_override(&"font_disabled_color", Color(creator.preset.danger_color, 0.8))
			_b.tooltip_text = "No trigger: this fight never starts"
	# waves
	for _j:int in _waves.size():
		_build_wave(_inner, index, _j, _waves[_j], _waves.size())
	if _waves.is_empty():
		var _none:Label = Label.new()
		_none.text = "No waves: no fight here."
		_none.modulate = Color(creator.preset.danger_color, 0.8)
		_inner.add_child(_none)
	_button(_hbox(_inner), "+ Wave", "Add a wave", add_wave.bind(index)).size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _build_wave(parent:Control, section:int, wave:int, data:Dictionary, wave_count:int)->void:
	var _boss:bool = data.get("is_boss", false)
	var _accent:Color = creator.preset.boss_wave_color if _boss else creator.preset.wave_accent_color
	var _inner:VBoxContainer = _card(parent, creator.preset.wave_card_color, _accent, 2)
	var _row:HBoxContainer = _hbox(_inner)
	var _label:Label = Label.new()
	_label.text = "Wave %d%s" % [wave + 1, "  BOSS" if _boss else ""]
	_label.add_theme_color_override(&"font_color", _accent.lightened(0.3))
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(_label)
	_button(_row, "Dup", "Duplicate the wave", add_wave.bind(section, wave))
	_button(_row, "^", "Move up", move_wave.bind(section, wave, -1)).disabled = wave == 0
	_button(_row, "v", "Move down", move_wave.bind(section, wave, 1)).disabled = wave == wave_count - 1
	_danger(_button(_row, "Del", "Delete the wave (asks first)", ask_remove_wave.bind(section, wave)))
	var _numbers:HBoxContainer = _hbox(_inner)
	_spin(_numbers, "Count", int(data.get("count", 1)), 1, 200, "Enemies in the wave", func (v:int)->void:
		change_wave(section, wave, func (w:Dictionary)->void: w.count = v))
	_spin(_numbers, "Max", int(data.get("max_alive", 0)), 0, 50, "Alive at once (0 = no cap)", func (v:int)->void:
		change_wave(section, wave, func (w:Dictionary)->void:
			if v == 0:
				w.erase("max_alive")
			else:
				w.max_alive = v))
	_check(_numbers, "Boss", _boss, "A boss wave (shows its name)", func (on:bool)->void:
		change_wave(section, wave, func (w:Dictionary)->void:
			if on:
				w.is_boss = true
				w.display_name = w.get("display_name", "Boss")
			else:
				w.erase("is_boss")
				w.erase("display_name")))
	if _boss:
		var _name:LineEdit = LineEdit.new()
		_name.text = String(data.get("display_name", ""))
		_name.placeholder_text = "Boss name"
		_name.tooltip_text = "Name shown for the boss (Enter)"
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name.text_submitted.connect(func (t:String)->void:
			_name.release_focus()
			change_wave(section, wave, func (w:Dictionary)->void: w.display_name = LayoutCodec.safe_text(t)))
		_inner.add_child(_name)
	var _enemies:Array = data.get("enemies", [])
	for _k:int in _enemies.size():
		var _enemy_row:HBoxContainer = _hbox(_inner)
		var _option:OptionButton = OptionButton.new()
		_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_option.fit_to_longest_item = false
		_option.focus_mode = Control.FOCUS_NONE
		for _id:String in _enemy_ids:
			_option.add_item(_id)
		var _at:int = _enemy_ids.find(String(_enemies[_k]))
		if _at == -1:
			_option.add_item(String(_enemies[_k]))
			_at = _option.item_count - 1
		_option.select(_at)
		_option.item_selected.connect(func (i:int)->void: set_enemy(section, wave, _k, _option.get_item_text(i)))
		_enemy_row.add_child(_option)
		var _x:Button = _button(_enemy_row, "x", "Remove this enemy type" if _enemies.size() > 1 else "A wave needs one enemy type", remove_enemy.bind(section, wave, _k))
		_x.disabled = _enemies.size() <= 1
	_button(_hbox(_inner), "+ Enemy type", "Add an enemy type to the wave", add_enemy.bind(section, wave)).size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _danger(b:Button)->void:
	b.add_theme_color_override(&"font_color", creator.preset.danger_color)
	b.add_theme_color_override(&"font_hover_color", creator.preset.danger_color.lightened(0.3))

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
		_l.tooltip_text = tooltip
		_l.mouse_filter = Control.MOUSE_FILTER_PASS
		_l.modulate.a = 0.75
		parent.add_child(_l)
	var _s:SpinBox = SpinBox.new()
	_s.min_value = min_value
	_s.max_value = max_value
	_s.value = value
	_s.tooltip_text = tooltip
	_s.custom_minimum_size.x = 34
	_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_s.value_changed.connect(func (v:float)->void: action.call(int(v)))
	parent.add_child(_s)
