## Map creator entities on live rooms: every baked entity node is claimed by its layout
## entity in every room; in room_N02 each live catalog kind can be placed (node built
## where the baker would put it), edited (props rebuild the node), moved, undone and
## erased; spawn points join and leave their section; the inspector shows the item's
## properties; Save bakes the placed entities.
##   Godot --headless --path . res://game/tests/map_creator_entity_check.tscn
extends Node

const BAKER:String = "res://game/resources/map_creator/layout_baker.tres"
const CREATOR:String = "res://addons/map_creator/scenes/map_creator.tscn"
const OUT:String = "user://map_creator_entity_check/"
const KEY:String = "N02"
## Built live (the rest show on the overlay and apply after Save).
const LIVE:Array[int] = [MapCatalogItem.Bake.SCENE, MapCatalogItem.Bake.DOOR, MapCatalogItem.Bake.PORTAL,
	MapCatalogItem.Bake.VICTORY, MapCatalogItem.Bake.BLOCK_WALL, MapCatalogItem.Bake.SPAWN,
	MapCatalogItem.Bake.BOSS_SPAWN, MapCatalogItem.Bake.TRIGGER, MapCatalogItem.Bake.PLAYER_SPAWN]

var failures:int = 0
var checks:int = 0

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	(load("res://addons/top_down/resources/global_resources/action_resource.tres") as ActionResource).reset_resource()
	var _baker:GameLayoutBaker = _test_baker()
	await _check_claims(_baker)
	await _check_editing(_baker)
	print("map_creator_entity_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _frames(count:int)->void:
	for _i:int in count:
		await get_tree().process_frame

func _test_baker()->GameLayoutBaker:
	var _source:GameLayoutBaker = load(BAKER)
	var _baker:GameLayoutBaker = _source.duplicate()
	_baker.catalog = _source.catalog
	_baker.layouts_dir = OUT + "layouts/"
	_baker.write_dir = OUT + "scenes/"
	_baker.balance_path = OUT + "balance.json"
	for _dir:String in [_baker.layouts_dir, _baker.write_dir]:
		DirAccess.make_dir_recursive_absolute(_dir)
	for _file:String in DirAccess.get_files_at("res://game/rooms/layouts/"):
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/rooms/layouts/" + _file), ProjectSettings.globalize_path(_baker.layouts_dir + _file))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/balance/balance.json"), ProjectSettings.globalize_path(_baker.balance_path))
	_baker.load_layouts()
	return _baker

func _open(key:String, baker:LayoutBaker)->MapCreator:
	var _room:Node2D = (load("res://game/scenes/room_%s.tscn" % key) as PackedScene).instantiate()
	var _creator:MapCreator = (load(CREATOR) as PackedScene).instantiate()
	_creator.baker = baker
	_creator.settings = MapCreatorSettings.new()
	_creator.settings.not_saved = true
	_creator.settings.auto_clean = false
	_creator.room = _room
	add_child(_room)
	_room.add_child(_creator)
	return _creator

func _check_claims(baker:LayoutBaker)->void:
	for _key:String in baker.layouts:
		var _creator:MapCreator = _open(_key, baker)
		await _frames(1)
		var _missing:Array[String] = []
		for _entity:LayoutEntity in _creator.layout.entities:
			var _item:MapCatalogItem = _creator.catalog.item(_entity.item_id)
			if !LIVE.has(_item.bake) || (_item.bake == MapCatalogItem.Bake.SCENE && _item.scene_path.is_empty()):
				continue
			if _creator.entities.nodes_of(_entity).is_empty():
				_missing.append("%s@%s" % [_entity.item_id, _entity.cell])
		check(_missing.is_empty(), "room_%s: every baked entity node is claimed (%s)" % [_key, _missing])
		_creator.room.free()

func _check_editing(baker:LayoutBaker)->void:
	var _creator:MapCreator = _open(KEY, baker)
	await _frames(2)
	var _room:Node = _creator.room
	_creator.set_editing(true)
	var _catalog:MapCatalog = _creator.catalog
	var _cell:Vector2i = _free_cell(_creator.layout)
	check(_cell != Vector2i(-999, -999), "found a free floor cell")

	# place, check and erase every live kind
	for _item:MapCatalogItem in _catalog.all_items():
		if _item.kind != MapCatalogItem.Kind.ENTITY || !LIVE.has(_item.bake) || (_item.bake == MapCatalogItem.Bake.SCENE && _item.scene_path.is_empty()):
			continue
		if _item.bake == MapCatalogItem.Bake.PLAYER_SPAWN:
			continue
		_creator.select_item(_item)
		_creator.set_tool(MapCreator.Tool.PAINT)
		_creator.begin_stroke(_cell)
		_creator.end_stroke()
		var _entity:LayoutEntity = _creator.layout.entity_at(_cell)
		check(_entity != null && _entity.item_id == _item.id, "%s goes into the layout" % _item.id)
		var _nodes:Array = _creator.entities.nodes_of(_entity) if _entity != null else []
		check(!_nodes.is_empty() && is_instance_valid(_nodes[0]) && _nodes[0].is_inside_tree(), "%s is built live" % _item.id)
		if !_nodes.is_empty():
			var _expected:Vector2i = _cell
			check(_creator.cell_at(_nodes[0].global_position) == _expected || (_item.bake == MapCatalogItem.Bake.BLOCK_WALL && _nodes[0].get_meta(&"source_cell") == _cell), "%s stands on its cell" % _item.id)
			if _item.bake == MapCatalogItem.Bake.SPAWN:
				check(_nodes[0].section.spawn_points.has(_nodes[0]), "a placed spawner joins its section")
		_creator.set_tool(MapCreator.Tool.ERASE)
		_creator.begin_stroke(_cell)
		_creator.end_stroke()
		await _frames(1)
		check(_creator.layout.entity_at(_cell) == null, "%s erases from the layout" % _item.id)
		check(_nodes.is_empty() || !is_instance_valid(_nodes[0]) || !_nodes[0].is_inside_tree(), "%s erases from the room" % _item.id)
		if _item.bake == MapCatalogItem.Bake.SPAWN && !_nodes.is_empty() && is_instance_valid(_nodes[0]):
			check(!_nodes[0].section.spawn_points.has(_nodes[0]), "an erased spawner leaves its section")

	# props, move, undo
	_creator.select_item(_catalog.item(&"door"))
	_creator.set_tool(MapCreator.Tool.PAINT)
	_creator.begin_stroke(_cell)
	_creator.end_stroke()
	var _door:LayoutEntity = _creator.layout.entity_at(_cell)
	check(_door.props.get("tag", "").begins_with("n02_door"), "a new door gets its own tag (%s)" % _door.props)
	_creator.set_entity_prop(_door, &"room", "room_N01")
	var _node:SceneEntry = _creator.entities.nodes_of(_door)[0]
	check(_node.scene_path.ends_with("room_N01.tscn"), "editing a prop rebuilds the live door")
	_creator.inspect(_door)
	await _frames(1)
	var _inspector:MapInspector = _creator.get_node("UI/Root/Inspector")
	check(_inspector.visible, "the inspector shows in Edit mode")
	var _editors:int = 0
	for _child:Node in _inspector._box.get_children():
		if _child is SpinBox || _child is LineEdit || _child is OptionButton || _child is CheckButton:
			_editors += 1
	check(_editors == _catalog.item(&"door").properties.size(), "the inspector shows the door's properties (%d)" % _editors)
	var _target:Vector2i = _cell + Vector2i(1, 0)
	_creator.edit(func ()->void: _door.cell = _target)
	_node = _creator.entities.nodes_of(_door)[0]
	check(_creator.cell_at(_node.global_position) == _target, "moving rebuilds the door on its new cell")
	_creator.undo()
	var _back:LayoutEntity = _creator.layout.entity_at(_cell)
	check(_back != null && _back.item_id == &"door", "undo puts the door back")
	check(_back != null && !_creator.entities.nodes_of(_back).is_empty() && _creator.cell_at(_creator.entities.nodes_of(_back)[0].global_position) == _cell, "undo moves the live door back")

	# loot box for the bake
	var _loot_cell:Vector2i = _cell + Vector2i(0, 1)
	_creator.select_item(_catalog.item(&"loot_box"))
	_creator.begin_stroke(_loot_cell)
	_creator.end_stroke()
	check(_creator.save(), "Save succeeds")
	var _baked:Node = (ResourceLoader.load(baker.write_dir + "room_%s.tscn" % KEY, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var _found:bool = false
	for _child:Node in _baked.get_node("WallLayer_Ysorted").get_children():
		if _child is LootBox && _creator.floor_layer.local_to_map(_child.position) == _loot_cell:
			_found = true
	check(_found, "the baked scene has the placed loot box")
	_baked.free()
	_room.queue_free()
	await _frames(2)

## Floor cell with floor around it and no entity within 2 cells.
func _free_cell(layout:RoomLayoutResource)->Vector2i:
	for _cell:Vector2i in LayoutBaker.sorted_cells(layout.floor.keys()):
		var _ok:bool = true
		for _y:int in range(-2, 3):
			for _x:int in range(-2, 3):
				var _n:Vector2i = _cell + Vector2i(_x, _y)
				if !layout.floor.has(_n) || layout.entity_at(_n) != null:
					_ok = false
		if _ok:
			return _cell
	return Vector2i(-999, -999)
