## Map creator painting on a live room (room_N01): Admin tools add the editor through the
## room template hook, Edit mode pauses the room, floor/wall/hole painting and erasing
## change the layout and the live layers, Clean regenerates walls, holes (and their hole
## scenes), colliders and the AStar grid with progress, undo/redo restore the layout and
## Save writes the layout and bakes the scene (into user://, not the project).
##   Godot --headless --path . res://game/tests/map_creator_paint_check.tscn
extends Node

const BAKER:String = "res://game/resources/map_creator/layout_baker.tres"
const CREATOR:String = "res://addons/map_creator/scenes/map_creator.tscn"
const SETTINGS:String = "res://addons/map_creator/resources/settings/map_creator_settings.tres"
const OUT:String = "user://map_creator_check/"
const KEY:String = "N01"

var failures:int = 0
var checks:int = 0

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	(load("res://addons/top_down/resources/global_resources/action_resource.tres") as ActionResource).reset_resource()
	var _settings:MapCreatorSettings = load(SETTINGS)
	_settings.not_saved = true
	await _check_hook(_settings)
	await _check_painting(_settings)
	print("map_creator_paint_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _frames(count:int)->void:
	for _i:int in count:
		await get_tree().process_frame

func _load_room()->Node2D:
	var _room:Node2D = (load("res://game/scenes/room_%s.tscn" % KEY) as PackedScene).instantiate()
	add_child(_room)
	return _room

func _creator_in(room:Node)->MapCreator:
	for _child:Node in room.get_children():
		if _child is MapCreator:
			return _child
	return null

## The template's hook adds and removes the editor with the setting.
func _check_hook(settings:MapCreatorSettings)->void:
	settings.set_admin_enabled(false)
	var _room:Node2D = _load_room()
	await _frames(3)
	check(_creator_in(_room) == null, "no editor while Admin tools are off")
	settings.set_admin_enabled(true)
	await _frames(2)
	var _creator:MapCreator = _creator_in(_room)
	check(_creator != null, "turning Admin tools on adds the editor to the room")
	check(_creator != null && _creator.can_edit(), "room_%s has a layout to edit" % KEY)
	check(settings.recent_rooms.size() > 0 && settings.recent_rooms[0] == KEY, "the room is first in the recent list")
	settings.set_admin_enabled(false)
	await _frames(2)
	check(_creator_in(_room) == null, "turning Admin tools off removes it")
	_room.queue_free()
	await _frames(2)

func _check_painting(settings:MapCreatorSettings)->void:
	# a test baker: layouts and scenes go to user://
	var _baker:GameLayoutBaker = (load(BAKER) as GameLayoutBaker).duplicate()
	_baker.catalog = (load(BAKER) as GameLayoutBaker).catalog
	_baker.layouts_dir = OUT + "layouts/"
	_baker.write_dir = OUT + "scenes/"
	_baker.balance_path = OUT + "balance.json"
	_baker.maps_path = OUT + "maps.json"
	for _dir:String in [_baker.layouts_dir, _baker.write_dir]:
		DirAccess.make_dir_recursive_absolute(_dir)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/rooms/layouts/room_%s.tres" % KEY), ProjectSettings.globalize_path(_baker.layout_path(KEY)))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/balance/balance.json"), ProjectSettings.globalize_path(_baker.balance_path))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/balance/maps.json"), ProjectSettings.globalize_path(_baker.maps_path))
	_baker.load_layouts()

	var _room:Node2D = _load_room()
	var _creator:MapCreator = (load(CREATOR) as PackedScene).instantiate()
	_creator.baker = _baker
	_creator.settings = settings.duplicate()
	_creator.settings.not_saved = true
	_creator.settings.auto_clean = false
	_room.add_child(_creator)
	await _frames(3)
	var _floor:TileMapLayer = _creator.floor_layer
	var _holes:TileMapLayer = _creator.holes_layer
	var _walls:TileMapLayer = _creator.walls_layer
	var _catalog:MapCatalog = _creator.catalog

	_creator.set_editing(true)
	await _frames(2)
	check(_creator.editing_flag.value, "Edit mode raises the editing flag")
	check(_room.process_mode == Node.PROCESS_MODE_DISABLED, "Edit mode pauses the room")
	check(_creator.can_process(), "the editor keeps running")
	check(_creator.camera.is_current(), "the edit camera takes over")

	# floor on an island far from the room
	var _island:Vector2i = Vector2i(120, 120)
	var _colliders_before:int = _walls.get_node("StaticBody2D").get_child_count()
	_creator.select_item(_catalog.item(&"floor_mossy"))
	_creator.set_brush(MapCreator.Brush.THREE)
	_creator.begin_stroke(_island)
	_creator.end_stroke()
	check(_creator.layout.floor.has(_island) && _creator.layout.floor[_island].x == 10, "painting floor goes into the layout")
	check(_floor.get_cell_source_id(_island) == 10 && _floor.get_cell_source_id(_island + Vector2i(1, 1)) == 10, "the 3x3 brush paints the live floor")
	check(_creator.dirty, "an edit makes the room dirty")
	check(_creator.can_undo(), "a stroke can be undone")
	var _fractions:Array[float] = []
	_creator.clean_progress.connect(func (f:float)->void: _fractions.append(f))
	_creator.clean()
	check(_creator.busy, "Clean runs over several frames")
	await _frames(12)
	check(!_creator.busy, "Clean finishes")
	check(_fractions.size() > 3 && _fractions[-1] == -1.0 && _fractions.has(1.0), "Clean reports progress (%s)" % [_fractions])
	check(_walls.get_cell_source_id(_island + Vector2i(-2, 0)) != -1, "Clean rings the new floor with walls")
	check(_walls.get_node("StaticBody2D").get_child_count() > _colliders_before, "Clean rebuilds the wall colliders")
	var _astar:AStarGrid2D = (_floor.get_node("TileNavigationSetter") as TileNavigationSetter).astargrid_resource.value
	check(_astar != null && _astar.region.has_point(_island), "Clean rebuilds the AStar grid over the new floor")

	# walls and holes inside the room
	var _inner:Vector2i = _interior_cell(_creator.layout)
	check(_inner != Vector2i(-999, -999), "found an interior floor cell")
	_creator.select_item(_catalog.item(&"wall"))
	_creator.set_brush(MapCreator.Brush.ONE)
	_creator.begin_stroke(_inner)
	_creator.end_stroke()
	check(_creator.layout.wall_overrides.get(_inner, false), "painting a wall sets a wall override")
	check(_walls.get_cell_source_id(_inner) != -1, "the wall shows on the live layer")
	_creator.clean(false)
	check(_walls.get_cell_source_id(_inner) != -1, "Clean keeps the painted wall")
	_creator.set_tool(MapCreator.Tool.ERASE)
	_creator.begin_stroke(_inner)
	_creator.end_stroke()
	_creator.clean(false)
	check(_walls.get_cell_source_id(_inner) == -1, "erasing the wall removes it")

	var _hole_scenes:int = _tile_spawned(_room)
	_creator.set_tool(MapCreator.Tool.PAINT)
	_creator.select_item(_catalog.item(&"hole"))
	_creator.begin_stroke(_inner)
	_creator.end_stroke()
	check(!_creator.layout.floor.has(_inner) && _floor.get_cell_source_id(_inner) == -1, "painting a hole removes the floor")
	_creator.clean(false)
	await _frames(2)
	check(_holes.get_cell_source_id(_inner) != -1, "Clean makes the gap a hole")
	check(_tile_spawned(_room) > _hole_scenes, "the new hole gets its hole scene")
	_creator.set_tool(MapCreator.Tool.ERASE)
	_creator.begin_stroke(_inner)
	_creator.end_stroke()
	_creator.clean(false)
	check(_creator.layout.floor.has(_inner) && _holes.get_cell_source_id(_inner) == -1, "erasing the hole brings the floor back")

	# undo / redo
	var _strokes:int = 0
	while _creator.can_undo():
		_creator.undo()
		_strokes += 1
	check(_strokes == 5, "every stroke is one undo step (%d)" % _strokes)
	check(!_creator.layout.floor.has(_island), "undo takes the island away again")
	await _frames(1)
	check(_floor.get_cell_source_id(_island) == -1, "undo updates the live floor")
	_creator.redo()
	check(_creator.layout.floor.has(_island), "redo paints it back")

	# save + bake
	check(_creator.save(), "Save succeeds")
	var _saved:RoomLayoutResource = ResourceLoader.load(_baker.layout_path(KEY), "", ResourceLoader.CACHE_MODE_IGNORE)
	check(_saved != null && _saved.floor.has(_island), "Save writes the layout")
	check(FileAccess.file_exists(_baker.write_dir + "room_%s.tscn" % KEY), "Save bakes the room scene")
	check(!_creator.dirty, "Save clears the dirty flag")
	var _baked:Node = (ResourceLoader.load(_baker.write_dir + "room_%s.tscn" % KEY, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(_baked.get_node("Background/FloorLayer").get_cell_source_id(_island) == 10, "the baked scene has the painted floor")
	_baked.free()

	# save into a mod workspace: JSON layout + cached scene, the project untouched
	var _mods:MapModState = _creator.mod_state
	_mods.mods_dir = OUT + "mods/"
	_mods.cache_dir = OUT + "cache/"
	if DirAccess.dir_exists_absolute(_mods.mods_dir.path_join("paint_test")):
		for _file:String in DirAccess.get_files_at(_mods.mods_dir.path_join("paint_test/layouts")):
			DirAccess.remove_absolute(_mods.mods_dir.path_join("paint_test/layouts").path_join(_file))
	check(_creator.create_mod("Paint test", false) && _mods.active == "paint_test", "New mod becomes the workspace")
	check(_creator.workspace_name() == "Paint test", "workspace named after the mod")
	_creator.dirty = true
	check(_creator.save(), "Save into the mod succeeds")
	var _info:MapModInfo = _mods.active_mod()
	check(_info != null && _info.has_room(KEY), "the mod got the room's JSON layout")
	check(FileAccess.file_exists(_mods.cache_scene("paint_test", KEY)) && _mods.scene_for(KEY) == _mods.cache_scene("paint_test", KEY), "the mod room is baked and resolves")
	var _from_mod:RoomLayoutResource = _mods.read_layout(_info, KEY, _creator.catalog) if _info != null else null
	check(_from_mod != null && _from_mod.floor.has(_island), "the mod layout has the edit")
	_mods.deactivate(_baker)

	_creator.set_editing(false)
	check(!_creator.editing_flag.value && _room.process_mode != Node.PROCESS_MODE_DISABLED, "Play mode resumes the room")
	_room.queue_free()
	await _frames(2)

## A floor cell with floor all around and nothing on it.
func _interior_cell(layout:RoomLayoutResource)->Vector2i:
	for _cell:Vector2i in LayoutBaker.sorted_cells(layout.floor.keys()):
		var _ok:bool = layout.entity_at(_cell) == null
		for _y:int in range(-1, 2):
			for _x:int in range(-1, 2):
				var _n:Vector2i = _cell + Vector2i(_x, _y)
				if !layout.floor.has(_n) || layout.entity_at(_n) != null:
					_ok = false
		if _ok && _cell.x > 4 && _cell.y > 4:
			return _cell
	return Vector2i(-999, -999)

func _tile_spawned(room:Node)->int:
	var _count:int = 0
	for _child:Node in room.get_node("Behind").get_children():
		if _child.has_meta(TileSpawner.SPAWNED_META) && !_child.is_queued_for_deletion():
			_count += 1
	return _count
