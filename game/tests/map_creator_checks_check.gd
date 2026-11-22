## Map creator waves panel + live checks: panel edits make the expected `sections` (one
## undo step each, boss / side flags, enemy rows from balance.json), the baked scene has
## the waves; MapChecks is clean on every built-in room and flags an unreachable spawn and
## a link to a missing room; autosave + Ctrl+R restore; play from cursor; layer toggles;
## per-room history kept for a saved room; a pending section test starts that fight.
##   Godot --headless --path . res://game/tests/map_creator_checks_check.tscn
extends Node

const BAKER:String = "res://game/resources/map_creator/layout_baker.tres"
const CREATOR:String = "res://addons/map_creator/scenes/map_creator.tscn"
const OUT:String = "user://map_creator_checks_check/"

var failures:int = 0
var checks:int = 0

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _frames(count:int)->void:
	for _i:int in count:
		await get_tree().process_frame

func _ready()->void:
	(load("res://addons/top_down/resources/global_resources/action_resource.tres") as ActionResource).reset_resource()
	var _baker:GameLayoutBaker = _test_baker()
	_baker.quiet = true
	await _check_builtin_clean(_baker)
	var _creator:MapCreator = _open("N01", _baker, MapCreatorSettings.new())
	await _frames(3)
	_creator.set_editing(true)
	await _frames(1)
	await _check_waves(_creator, _baker)
	await _check_problems(_creator)
	_check_autosave(_creator)
	_check_play_here(_creator)
	_check_layers(_creator)
	var _settings:MapCreatorSettings = _creator.settings
	await _check_history(_creator, _baker, _settings)
	print("map_creator_checks_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_baker()->GameLayoutBaker:
	var _source:GameLayoutBaker = load(BAKER)
	var _baker:GameLayoutBaker = _source.duplicate()
	_baker.catalog = _source.catalog
	_baker.layouts_dir = OUT + "layouts/"
	_baker.write_dir = OUT + "scenes/"
	_baker.balance_path = OUT + "balance.json"
	_baker.maps_path = OUT + "maps.json"
	for _dir:String in [_baker.layouts_dir, _baker.write_dir]:
		DirAccess.make_dir_recursive_absolute(_dir)
	for _file:String in DirAccess.get_files_at("res://game/rooms/layouts/"):
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/rooms/layouts/" + _file), ProjectSettings.globalize_path(_baker.layouts_dir + _file))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/balance/balance.json"), ProjectSettings.globalize_path(_baker.balance_path))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/balance/maps.json"), ProjectSettings.globalize_path(_baker.maps_path))
	_baker.load_layouts()
	return _baker

func _open(key:String, baker:LayoutBaker, settings:MapCreatorSettings)->MapCreator:
	var _room:Node2D = (load("res://game/scenes/room_%s.tscn" % key) as PackedScene).instantiate()
	var _creator:MapCreator = (load(CREATOR) as PackedScene).instantiate()
	_creator.baker = baker
	_creator.settings = settings
	_creator.settings.not_saved = true
	_creator.settings.auto_clean = false
	_creator.room = _room
	add_child(_room)
	_room.add_child(_creator)
	return _creator

## The built-in rooms pass the live checks (no false alarms).
func _check_builtin_clean(baker:GameLayoutBaker)->void:
	for _key:String in baker.layouts:
		var _creator:MapCreator = _open(_key, baker, MapCreatorSettings.new())
		await _frames(1)
		var _found:Array[Dictionary] = MapChecks.run(_creator)
		var _texts:Array = _found.map(func (p:Dictionary)->String: return p.text)
		check(_found.is_empty(), "room_%s has no live problems %s" % [_key, _texts])
		_creator.room.free()

func _check_waves(creator:MapCreator, baker:GameLayoutBaker)->void:
	var _panel:WavesPanel = creator.get_node("UI/Root/WavesPanel")
	creator.waves_requested.emit()
	check(_panel.visible, "K / Waves opens the panel")
	check(!_panel.enemy_ids().is_empty() && _panel.enemy_ids().has("zombie"), "enemy ids from balance.json")
	var _sections:int = creator.layout.sections.size()
	var _undo:int = creator._undo.size()
	_panel.add_section()
	check(creator.layout.sections.size() == _sections + 1 && creator._undo.size() == _undo + 1, "add section: one undo step")
	var _last:int = creator.layout.sections.size() - 1
	_panel.add_wave(_last)
	check(creator.layout.sections[_last].waves.size() == 2, "add wave")
	_panel.change_wave(_last, 1, func (w:Dictionary)->void: w.count = 9)
	_panel.set_enemy(_last, 1, 1, "slime")
	check(creator.layout.sections[_last].waves[1].count == 9 && creator.layout.sections[_last].waves[1].enemies.size() == 2 && creator.layout.sections[_last].waves[1].enemies[1] == "slime", "edit count and add an enemy")
	_panel.remove_enemy(_last, 1, 0)
	check(creator.layout.sections[_last].waves[1].enemies == ["slime"], "remove an enemy")
	_panel.set_flag(&"boss_section", _last + 1, true)
	check(creator.layout.boss_section == _last + 1, "boss flag")
	_panel.move_wave(_last, 1, -1)
	check(creator.layout.sections[_last].waves[0].count == 9, "move a wave up")
	_panel.rebuild()
	check(_panel._cards.size() == creator.layout.sections.size(), "one card per section")
	_panel.focus_section(1)
	check(creator.highlight_section == 1 && !creator.selection.is_empty(), "section title highlights + selects its entities")
	# stale indices never crash
	_panel.change_section(99, func (s:Dictionary)->void: s.x = 1)
	_panel.change_wave(_last, 99, func (w:Dictionary)->void: w.x = 1)
	check(creator._undo.size() == _undo + 7, "stale indices: no edit")
	# a spawner + trigger in the new (last) section, one in section 1
	var _spawn_item:MapCatalogItem = creator.catalog.item(&"spawn")
	var _cells:Array[Vector2i] = []
	for _cell:Vector2i in creator.layout.floor:
		if creator.layout.entity_at(_cell) == null:
			_cells.append(_cell)
		if _cells.size() == 2:
			break
	creator.edit(func ()->void:
		creator._put(_cells[0], _spawn_item, {"section": _last + 1})
		creator._put(_cells[1], _spawn_item, {"section": _last + 1}))
	var _usage:Dictionary = _panel.section_usage(_last + 1)
	check(_usage.spawners == 2 && _usage.total == 2, "section usage counts its spawners")
	# move up: entities + boss flag follow
	_panel.move_section(_last, -1)
	check(creator.layout.entity_at(_cells[0]).props.section == _last && creator.layout.boss_section == _last && creator.layout.sections[_last - 1].waves[0].count == 9, "move section: entities and boss flag follow")
	creator.undo()
	check(creator.layout.entity_at(_cells[0]).props.section == _last + 1 && creator.layout.boss_section == _last + 1, "undo move")
	# inspecting a spawner scrolls to its section
	creator.inspect(creator.layout.entity_at(_cells[0]))
	check(_panel.focus_number == _last + 1 && creator.highlight_section == _last + 1 && !_panel._collapsed.get(_last + 1, false), "inspect: panel focuses its section")
	await _frames(2)
	creator.inspect(null)
	# trigger inspector: button opens the waves panel on its section
	_panel.close()
	var _trigger:LayoutEntity = creator.layout.entities_of(&"trigger")[0]
	creator.inspect(_trigger)
	var _inspector:MapInspector = creator.get_node("UI/Root/Inspector")
	var _open:Button = null
	for _child:Node in _inspector._box.get_children():
		if _child is Button && (_child as Button).text.begins_with("Edit section"):
			_open = _child
	check(_open != null, "trigger inspector has an open-waves button")
	if _open != null:
		_open.pressed.emit()
	check(_panel.visible && _panel.focus_number == creator.section_of(_trigger) && creator.highlight_section == _panel.focus_number, "open-waves button opens the panel on its section")
	await _frames(2)
	creator.inspect(null)
	# delete prompts
	var _prompt:MapPrompt = creator.get_node("UI/Root/Prompt")
	_panel.ask_remove_section(_last)
	check(_prompt.visible && _prompt.choice_labels().size() == 3 && _prompt.choice_labels()[0].contains("2 map entities"), "section delete asks: delete all / move / cancel %s" % [_prompt.choice_labels()])
	_prompt.press_choice(2)
	check(!_prompt.visible && creator.layout.sections.size() == _sections + 1, "cancel keeps it")
	_panel.ask_remove_wave(_last, 0)
	check(_prompt.visible && _prompt.choice_labels().size() == 2, "wave delete asks (not the only wave)")
	_prompt.press_choice(0)
	check(creator.layout.sections[_last].waves.size() == 1, "delete wave")
	_panel.ask_remove_wave(_last, 0)
	check(_prompt.choice_labels().size() == 3, "only wave also offers the whole section")
	_prompt.close()
	creator.undo()
	# keep entities: they move to the previous section
	_panel.remove_section(_last, false)
	check(creator.layout.sections.size() == _sections && creator.layout.boss_section == 0 && creator.layout.entity_at(_cells[0]) != null && creator.layout.entity_at(_cells[0]).props.section == _last, "remove section keeping entities: moved to previous, boss flag cleared")
	creator.undo()
	# delete entities, via the prompt
	_panel.ask_remove_section(_last)
	_prompt.press_choice(0)
	check(creator.layout.sections.size() == _sections && creator.layout.entity_at(_cells[0]) == null && creator.layout.entity_at(_cells[1]) == null, "remove section + its entities in one step")
	creator.undo()
	check(creator.layout.sections.size() == _sections + 1 && creator.layout.boss_section == _last + 1 && creator.layout.entity_at(_cells[0]) != null, "undo brings it back")
	# removing an earlier section renumbers later entities
	if _last >= 1:
		_panel.remove_section(0, true)
		check(creator.layout.entity_at(_cells[0]).props.section == _last && creator.layout.boss_section == _last, "later sections renumber (entities + flags)")
		creator.undo()
	# a structural undo while a spin is focused still rebuilds
	_panel.rebuild()
	var _spin:SpinBox = _find_spin(_panel)
	if _spin != null:
		_spin.get_line_edit().grab_focus()
		creator.undo()
		await _frames(2)
		check(_panel._built_shape == _panel._shape(), "shape change rebuilds despite focus")
		creator.redo()
		_spin.get_viewport().gui_release_focus()
	creator.undo()
	creator.undo()
	creator.undo()
	_panel.close()
	check(!_panel.visible && creator.highlight_section == 0, "close")

func _find_spin(node:Node)->SpinBox:
	for _child:Node in node.get_children():
		if _child is SpinBox:
			return _child
		var _found:SpinBox = _find_spin(_child)
		if _found != null:
			return _found
	return null

func _check_problems(creator:MapCreator)->void:
	creator.run_checks()
	var _before:int = creator.problems.size()
	# a spawn on an island nobody can reach, and a door to nowhere
	var _base:MapCatalogItem = creator.catalog.item(&"floor_base")
	creator.edit(func ()->void:
		for _y:int in range(140, 143):
			for _x:int in range(140, 143):
				creator._put(Vector2i(_x, _y), _base)
		creator._put(Vector2i(141, 141), creator.catalog.item(&"spawn"), {"section": 1})
		creator._put(Vector2i(160, 160), _base)
		creator._put(Vector2i(160, 160), creator.catalog.item(&"door"), {"tag": "t", "connect_tag": "x", "room": "room_NOPE"}), false)
	creator.run_checks()
	var _texts:String = " ".join(creator.problems.map(func (p:Dictionary)->String: return p.text))
	check(creator.problems.size() > _before, "new problems found")
	check(_texts.contains("141, 141") && _texts.contains("no path"), "unreachable spawn flagged (%s)" % _texts)
	check(_texts.contains("room_NOPE"), "link to a missing room flagged")
	var _with_cell:bool = creator.problems.any(func (p:Dictionary)->bool: return p.cell == Vector2i(141, 141))
	check(_with_cell, "problems carry their cell")
	var _panel:ProblemsPanel = creator.get_node("UI/Root/ProblemsPanel")
	creator.problems_requested.emit()
	check(_panel.visible && _panel._list.item_count == creator.problems.size(), "problems panel lists them")
	var _index:int = creator.problems.find(creator.problems.filter(func (p:Dictionary)->bool: return p.cell == Vector2i(141, 141))[0])
	_panel._go_to(_index)
	check(creator.camera.global_position.distance_to(creator.cell_center(Vector2i(141, 141))) < 1.0, "clicking one moves the camera there")
	_panel.toggle()
	# edits rerun the checks by themselves
	creator.undo()
	await _frames(30)
	check(creator.problems.size() == _before, "checks rerun after an edit (%d vs %d)" % [creator.problems.size(), _before])

func _check_autosave(creator:MapCreator)->void:
	if FileAccess.file_exists(creator.autosave_path()):
		DirAccess.remove_absolute(creator.autosave_path())
	check(!creator.has_autosave(), "no autosave yet")
	creator.add_at(creator.layout.floor.keys()[0], creator.catalog.item(&"loot_box"))
	var _edited:String = LayoutCodec.to_json(creator.layout)
	creator.autosave()
	creator.undo()
	check(creator.has_autosave(), "autosave differs from the layout")
	check(creator.restore_autosave() && LayoutCodec.to_json(creator.layout) == _edited, "Ctrl+R restores it")
	creator.undo()
	check(LayoutCodec.to_json(creator.layout) != _edited, "and undo takes it back")
	DirAccess.remove_absolute(creator.autosave_path())

func _check_play_here(creator:MapCreator)->void:
	var _player:Node2D = creator.player_reference.node as Node2D
	if _player == null:
		check(true, "no player in this headless room (play here skipped)")
		return
	var _cell:Vector2i = creator.layout.entities_of(&"player_spawn")[0].cell + Vector2i(1, 1)
	creator.hover_cell = _cell
	creator.hover_valid = true
	creator.camera.global_position = Vector2(1234, 567)
	creator.play_here()
	check(!creator.editing && _player.global_position.distance_to(creator.cell_center(_cell)) < 1.0, "play here: player at the cursor, Play mode")
	creator.set_editing(true)
	check(creator.camera.global_position == Vector2(1234, 567), "back to the same edit view")

func _check_layers(creator:MapCreator)->void:
	creator.set_layer_visible(1, false)
	creator.set_layer_visible(3, false)
	check(creator.walls_layer.self_modulate.a == 0.0 && !creator.overlay.show_entities, "layers hide")
	creator.set_layer_visible(1, true)
	creator.set_layer_visible(3, true)
	check(creator.walls_layer.self_modulate.a == 1.0 && creator.overlay.show_entities, "layers show")

func _check_history(creator:MapCreator, baker:GameLayoutBaker, settings:MapCreatorSettings)->void:
	creator.add_at(creator.layout.floor.keys()[0], creator.catalog.item(&"loot_box"))
	check(creator.save(), "save")
	var _steps:int = creator._undo.size()
	creator.room.free()
	await _frames(1)
	check(settings.histories.has("N01"), "a saved room leaves its history behind")
	settings.test_section = 1
	var _again:MapCreator = _open("N01", baker, settings)
	await _frames(6)
	check(_again._undo.size() == _steps, "history back on the next visit (%d)" % _again._undo.size())
	var _section:Node = _again.room.get_node("EnemyManager/Section1")
	check(settings.test_section == 0 && bool(_section.get(&"fight_active")), "a pending section test starts the fight")
	_again.room.queue_free()
	await _frames(2)
