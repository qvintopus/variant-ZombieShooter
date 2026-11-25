## Moving live entities after a fight started (its trigger parent ArenaEntry is freed):
## no freed-instance errors, triggers come back, gates keep their raised look, and R
## rotates the selection / the carried move around its centre.
##   Godot --headless --path . res://game/tests/map_creator_move_check.tscn
extends Node

const BAKER:String = "res://game/resources/map_creator/layout_baker.tres"
const CREATOR:String = "res://addons/map_creator/scenes/map_creator.tscn"
const OUT:String = "user://map_creator_move_check/"
const KEY:String = "N01"

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
	var _source:GameLayoutBaker = load(BAKER)
	var _baker:GameLayoutBaker = _source.duplicate()
	_baker.catalog = _source.catalog
	_baker.layouts_dir = OUT + "layouts/"
	_baker.write_dir = OUT + "scenes/"
	_baker.balance_path = OUT + "balance.json"
	_baker.maps_path = OUT + "maps.json"
	for _dir:String in [_baker.layouts_dir, _baker.write_dir]:
		DirAccess.make_dir_recursive_absolute(_dir)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/rooms/layouts/room_%s.tres" % KEY), ProjectSettings.globalize_path(_baker.layout_path(KEY)))
	_baker.load_layouts()
	var _room:Node2D = (load("res://game/scenes/room_%s.tscn" % KEY) as PackedScene).instantiate()
	var _creator:MapCreator = (load(CREATOR) as PackedScene).instantiate()
	_creator.baker = _baker
	_creator.settings = MapCreatorSettings.new()
	_creator.settings.not_saved = true
	_creator.settings.auto_clean = false
	_creator.room = _room
	add_child(_room)
	_room.add_child(_creator)
	await _frames(3)
	# a fight frees its ArenaEntry (the trigger polygons' parent)
	var _entry:Node = _room.get_node_or_null(String(_baker.trigger_nodes[0]))
	check(_entry != null, "room has %s" % _baker.trigger_nodes[0])
	if _entry != null:
		_entry.free()
	_creator.set_editing(true)
	await _frames(1)
	await _check_move(_creator)
	_check_rotate(_creator)
	_creator.set_editing(false)
	_room.queue_free()
	await _frames(2)
	print("map_creator_move_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _gate_nodes(creator:MapCreator)->Array:
	var _out:Array = []
	for _child:Node in creator.walls_layer.get_children():
		if _child is BlockWall && is_instance_valid(_child):
			_out.append(_child)
	return _out

func _check_move(creator:MapCreator)->void:
	var _entries:Array = []
	for _type:StringName in [&"trigger", &"gate"]:
		for _entity:LayoutEntity in creator.layout.entities_of(_type):
			_entries.append({"cell": _entity.cell, "type": _type})
	var _gate:LayoutEntity = creator.layout.entities_of(&"gate")[0]
	var _old:BlockWall = creator.entities.nodes_of(_gate)[0]
	var _offset:Vector2 = _old.position - creator.walls_layer.map_to_local(_gate.cell)
	creator.hover_cell = _entries[0].cell
	creator.begin_move(_entries, false)
	creator.confirm_move(_entries[0].cell + Vector2i(1, 0))
	await _frames(2)
	check(creator.layout.entities_of(&"trigger").size() == 3, "triggers moved (%d)" % creator.layout.entities_of(&"trigger").size())
	var _moved:LayoutEntity = creator.layout.entities_of(&"gate")[0]
	var _nodes:Array = creator.entities.nodes_of(_moved)
	check(_nodes.size() == 1 && is_instance_valid(_nodes[0]), "moved gate has a live node")
	if _nodes.size() == 1:
		var _new:BlockWall = _nodes[0]
		check(_new.position - creator.walls_layer.map_to_local(_moved.cell) == _offset, "moved gate keeps its offset (%s vs %s)" % [_new.position - creator.walls_layer.map_to_local(_moved.cell), _offset])
		var _raised:bool = _new.arena_door_block.is_raised()
		check(_raised, "moved gate (section not cleared) is raised")
		check(_new.get_node("Sprite2D").frame == (3 if _raised else 0), "moved gate shows its raised look at once (frame %d)" % _new.get_node("Sprite2D").frame)
	check(_gate_nodes(creator).size() == creator.layout.entities_of(&"gate").size() + creator.layout.entities_of(&"barrier").size(), "no stale wall nodes (%d)" % _gate_nodes(creator).size())

func _spot(creator:MapCreator)->Vector2i:
	# a free 3x3 floor patch
	for _cell:Vector2i in creator.layout.floor:
		var _ok:bool = true
		for _dx:int in range(-1, 2):
			for _dy:int in range(-1, 2):
				var _c:Vector2i = _cell + Vector2i(_dx, _dy)
				_ok = _ok && creator.layout.floor.has(_c) && creator.layout.entity_at(_c) == null
		if _ok:
			return _cell
	return Vector2i(1 << 20, 0)

func _cells_of(creator:MapCreator, type:StringName)->Array:
	var _out:Array = []
	for _entity:LayoutEntity in creator.layout.entities_of(type):
		_out.append(_entity.cell)
	_out.sort()
	return _out

func _check_rotate(creator:MapCreator)->void:
	var _c:Vector2i = _spot(creator)
	check(_c.x < (1 << 20), "free 3x3 floor spot (floor %d)" % creator.layout.floor.size())
	var _spawns:int = creator.layout.entities_of(&"spawn").size()
	var _before:Array = _cells_of(creator, &"spawn")
	for _cell:Vector2i in [_c + Vector2i(-1, 0), _c, _c + Vector2i(1, 0)]:
		creator.add_at(_cell, creator.catalog.item(&"spawn"))
	var _row:Array = []
	for _cell:Vector2i in [_c + Vector2i(-1, 0), _c, _c + Vector2i(1, 0)]:
		_row.append({"cell": _cell, "type": &"spawn"})
	creator.selection.set_entries(_row)
	var _undo:int = creator._undo.size()
	creator.rotate_selection(1)
	var _after:Array = _cells_of(creator, &"spawn")
	for _cell:Vector2i in [_c + Vector2i(0, -1), _c, _c + Vector2i(0, 1)]:
		check(_after.has(_cell), "R: row turned around its centre (%s)" % _cell)
	check(!_after.has(_c + Vector2i(-1, 0)) && !_after.has(_c + Vector2i(1, 0)), "R: old ends gone")
	check(creator.layout.entities_of(&"spawn").size() == _spawns + 3, "R keeps the count")
	check(creator._undo.size() == _undo + 1, "R is one undo step")
	check(creator.selection.size() == 3 && creator.selection.has(_c + Vector2i(0, 1), &"spawn"), "R keeps the turned selection")
	creator.rotate_selection(-1)
	check(_cells_of(creator, &"spawn").has(_c + Vector2i(1, 0)) && !_cells_of(creator, &"spawn").has(_c + Vector2i(0, 1)), "Shift+R turns back")
	# while carrying: turn the ghost, drop 2 cells over
	creator.hover_cell = _c
	creator.begin_move(creator.selection.entries(), false)
	for _i:int in 4:
		creator.rotate_selection(1)
	creator.rotate_selection(1)
	creator.confirm_move(_c + Vector2i(0, 0))
	var _moved:Array = _cells_of(creator, &"spawn")
	check(_moved.has(_c + Vector2i(0, -1)) && _moved.has(_c + Vector2i(0, 1)) && !_moved.has(_c + Vector2i(1, 0)), "R while moving turns the drop (5 turns = 1)")
	creator.undo()
	creator.undo()
	creator.undo()
	check(_cells_of(creator, &"spawn").size() == _spawns + 3, "undo back to the row")
