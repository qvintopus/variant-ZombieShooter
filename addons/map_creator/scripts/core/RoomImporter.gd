## Hand-made room scene -> RoomLayoutResource, best effort. The scene is instantiated
## outside the tree (no _ready runs) and read:
##   floor cells (source kept, atlas mapped back to the catalog floor look),
##   holes / walls compared with what the floor generates (the difference becomes overrides),
##   doors / portals, block walls, spawn points, triggers (every floor cell inside a trigger
##   polygon), the player spawner, catalog scene items, and the sections' waves.
## What it can't map goes to `warnings`.
class_name RoomImporter
extends RefCounted

var warnings:PackedStringArray = []

func import_scene(path:String, key:String, baker:LayoutBaker)->RoomLayoutResource:
	warnings.clear()
	var _packed:PackedScene = load(path) as PackedScene
	if _packed == null:
		warnings.append("can't load %s" % path)
		return null
	var _root:Node = _packed.instantiate()
	var _floor:TileMapLayer = _root.get_node_or_null("Background/FloorLayer")
	var _holes:TileMapLayer = _root.get_node_or_null("Background/ObstacleLayer")
	var _walls:TileMapLayer = _root.get_node_or_null("WallLayer_Ysorted")
	if _floor == null || _holes == null || _walls == null:
		warnings.append("%s doesn't have the room template's tile layers" % path)
		_root.free()
		return null
	var _layout:RoomLayoutResource = RoomLayoutResource.new()
	_layout.key = key
	_layout.display_name = "room_" + key
	_layout.writes_balance = false
	var _catalog:MapCatalog = baker.catalog
	for _cell:Vector2i in _floor.get_used_cells():
		var _src:int = _floor.get_cell_source_id(_cell)
		var _item:MapCatalogItem = _floor_look(_catalog, _src, _floor.get_cell_atlas_coords(_cell))
		var _atlas:Vector2i = _item.floor_atlas if _item != null else _floor.get_cell_atlas_coords(_cell)
		_layout.floor[_cell] = Vector3i(_src, _atlas.x, _atlas.y)
	_read_overrides(_layout, _holes, _walls, baker)
	var _floor_xform:Transform2D = _xform(_floor, _root)
	var _cell_of:Callable = func (node:Node)->Vector2i:
		return _floor.local_to_map(_floor_xform.affine_inverse() * _xform(node, _root).origin)
	_read_entries(_layout, _root, _catalog, baker, _cell_of)
	_read_block_walls(_layout, _walls, _root, _catalog, baker)
	_read_spawns(_layout, _root, _catalog, _cell_of)
	_read_triggers(_layout, _root, _floor, _floor_xform, baker)
	_read_scene_items(_layout, _root, _catalog, _cell_of)
	_read_sections(_layout, _root, baker)
	var _spawner:Node = _root.get_node_or_null("PlayerSpawner")
	if _spawner != null:
		# first, so it wins its cell over a trigger area
		_layout.entities.insert(0, LayoutEntity.make(&"player_spawn", _cell_of.call(_spawner)))
	_root.free()
	# one entity per cell; the first found wins
	var _by_cell:Dictionary = {}
	var _kept:Array[LayoutEntity] = []
	for _entity:LayoutEntity in _layout.entities:
		if _by_cell.has(_entity.cell):
			warnings.append("%s at %s dropped: %s is there" % [_entity.item_id, _entity.cell, _by_cell[_entity.cell]])
			continue
		_by_cell[_entity.cell] = _entity.item_id
		_kept.append(_entity)
	_layout.entities = _kept
	return _layout

## Local -> root transform without the tree.
static func _xform(node:Node, root:Node)->Transform2D:
	var _t:Transform2D = Transform2D.IDENTITY
	var _n:Node = node
	while _n != null && _n != root:
		if _n is Node2D:
			_t = (_n as Node2D).transform * _t
		_n = _n.get_parent()
	return _t

static func _floor_look(catalog:MapCatalog, source:int, atlas:Vector2i)->MapCatalogItem:
	var _exact:MapCatalogItem = catalog.floor_item(source, atlas)
	if _exact != null:
		return _exact
	for _item:MapCatalogItem in catalog.all_items():
		if _item.kind == MapCatalogItem.Kind.FLOOR && _item.floor_source == source:
			return _item
	return null

## Generates walls / holes from the imported floor and keeps the differences as overrides.
func _read_overrides(layout:RoomLayoutResource, holes:TileMapLayer, walls:TileMapLayer, baker:LayoutBaker)->void:
	var _template:Node = (load(baker.template_path) as PackedScene).instantiate()
	var _floor:TileMapLayer = _template.get_node("Background/FloorLayer")
	var _gen_holes:TileMapLayer = _template.get_node("Background/ObstacleLayer")
	var _gen_walls:TileMapLayer = _template.get_node("WallLayer_Ysorted")
	for _layer:TileMapLayer in [_floor, _gen_holes, _gen_walls]:
		_layer.clear()
	LayoutBaker.paint_floor(_floor, layout)
	LayoutBaker.generate_tiles(_floor, _gen_holes, _gen_walls, layout)
	for _pair:Array in [[holes, _gen_holes, layout.hole_overrides], [walls, _gen_walls, layout.wall_overrides]]:
		var _have:TileMapLayer = _pair[0]
		var _gen:TileMapLayer = _pair[1]
		for _cell:Vector2i in _have.get_used_cells():
			if _gen.get_cell_source_id(_cell) == -1:
				_pair[2][_cell] = true
		for _cell:Vector2i in _gen.get_used_cells():
			if _have.get_cell_source_id(_cell) == -1:
				_pair[2][_cell] = false
	_template.free()

func _read_entries(layout:RoomLayoutResource, root:Node, catalog:MapCatalog, baker:LayoutBaker, cell_of:Callable)->void:
	var _behind:Node = root.get_node_or_null("Behind")
	if _behind == null:
		return
	for _child:Node in _behind.get_children():
		if !(_child is SceneEntry):
			continue
		var _item:MapCatalogItem = _item_by_scene(catalog, _child.scene_file_path, [MapCatalogItem.Bake.DOOR, MapCatalogItem.Bake.PORTAL])
		if _item == null:
			warnings.append("entry %s (%s) has no catalog item" % [_child.name, _child.scene_file_path])
			continue
		var _entry:SceneEntry = _child
		if _item.bake == MapCatalogItem.Bake.PORTAL && _entry.tag == baker.victory_tag:
			layout.entities.append(LayoutEntity.make(&"victory", cell_of.call(_child)))
			continue
		var _props:Dictionary = {
			"tag": _entry.tag, "connect_tag": _entry.connect_tag,
			"room": _entry.scene_path.get_file().get_basename(),
		}
		if _item.bake == MapCatalogItem.Bake.PORTAL:
			var _waits:String = String(_child.get(&"open_when_cleared"))
			if !_waits.is_empty():
				_props.waits_for = _waits.trim_prefix("room_")
		layout.entities.append(LayoutEntity.make(_item.id, cell_of.call(_child), _props))

func _read_block_walls(layout:RoomLayoutResource, walls:TileMapLayer, root:Node, catalog:MapCatalog, baker:LayoutBaker)->void:
	var _barrier:MapCatalogItem = null
	var _gate:MapCatalogItem = null
	for _item:MapCatalogItem in catalog.all_items():
		if _item.kind == MapCatalogItem.Kind.ENTITY && _item.bake == MapCatalogItem.Bake.BLOCK_WALL:
			if int(_item.defaults.get("mode", 0)) == 1:
				_gate = _item
			elif _barrier == null:
				_barrier = _item
	var _generator:Node = walls.get_node_or_null("BlockWallGenerator")
	var _offset:Vector2 = _generator.get(&"spawn_offset") if _generator != null else Vector2.ZERO
	var _seen:Dictionary = {}
	for _child:Node in walls.get_children():
		if !(_child is BlockWall):
			continue
		var _wall:BlockWall = _child
		var _cell:Vector2i = _wall.get_meta(&"source_cell") if _wall.has_meta(&"source_cell") else walls.local_to_map(_wall.position - _offset)
		if _seen.has(_cell):
			continue
		_seen[_cell] = true
		var _item:MapCatalogItem = _gate if int(_wall.mode) == 1 && _gate != null else _barrier
		if _item != null:
			layout.entities.append(LayoutEntity.make(_item.id, _cell, {"section": _section_number(_wall.section, root, baker)}))

func _read_spawns(layout:RoomLayoutResource, root:Node, catalog:MapCatalog, cell_of:Callable)->void:
	var _points:Node = root.get_node_or_null("EnemySpawnPoints")
	if _points == null:
		return
	for _child:Node in _points.get_children():
		if !(_child is SpawnPoint):
			continue
		if bool(_child.get(&"boss_position")):
			layout.entities.append(LayoutEntity.make(&"boss_spawn", cell_of.call(_child)))
			continue
		var _section:Variant = _child.get(&"section")
		var _number:int = int(String(_section.name).trim_prefix("Section")) if _section is Node else 1
		layout.entities.append(LayoutEntity.make(&"spawn", cell_of.call(_child), {
			"section": maxi(_number, 1), "max_simultaneous": int(_child.get(&"max_simultaneous")),
		}))

func _read_triggers(layout:RoomLayoutResource, root:Node, floor_layer:TileMapLayer, floor_xform:Transform2D, baker:LayoutBaker)->void:
	for _i:int in baker.trigger_nodes.size():
		var _parent:Node = root.get_node_or_null(baker.trigger_nodes[_i])
		if _parent == null:
			continue
		var _cells:Dictionary = {}
		for _shape:Node in _parent.get_children():
			if !(_shape is CollisionPolygon2D):
				continue
			var _to_floor:Transform2D = floor_xform.affine_inverse() * _xform(_shape, root)
			var _polygon:PackedVector2Array = _to_floor * (_shape as CollisionPolygon2D).polygon
			for _cell:Vector2i in layout.floor:
				if !_cells.has(_cell) && Geometry2D.is_point_in_polygon(floor_layer.map_to_local(_cell), _polygon):
					_cells[_cell] = true
		for _cell:Vector2i in LayoutBaker.sorted_cells(_cells.keys()):
			layout.entities.append(LayoutEntity.make(&"trigger", _cell, {"section": _i + 1}))

func _read_scene_items(layout:RoomLayoutResource, root:Node, catalog:MapCatalog, cell_of:Callable)->void:
	for _item:MapCatalogItem in catalog.all_items():
		if _item.kind != MapCatalogItem.Kind.ENTITY || _item.bake != MapCatalogItem.Bake.SCENE || _item.scene_path.is_empty():
			continue
		var _parent:Node = root.get_node_or_null(_item.parent_path)
		if _parent == null:
			continue
		for _child:Node in _parent.get_children():
			if _child.scene_file_path != _item.scene_path || !(_child is Node2D):
				continue
			var _props:Dictionary = {}
			for _spec:MapPropertySpec in _item.properties:
				if !_spec.node_property.is_empty():
					var _value:Variant = _child.get(_spec.node_property)
					if _value != null && _value != _item.defaults.get(_spec.key):
						_props[String(_spec.key)] = LayoutCodec.coerce(_spec, _value)
			layout.entities.append(LayoutEntity.make(_item.id, cell_of.call(_child), _props))

func _read_sections(layout:RoomLayoutResource, root:Node, baker:LayoutBaker)->void:
	var _ids:Dictionary = _enemy_ids(baker)
	var _sections:Array[Dictionary] = []
	for _i:int in baker.section_paths.size():
		var _section:Node = root.get_node_or_null(baker.section_paths[_i].trim_prefix("../../"))
		if _section == null:
			break
		var _waves:Array = []
		for _wave:Variant in _section.get(&"waves"):
			if _wave == null:
				continue
			var _enemies:Array = []
			for _instance:Resource in _wave.instance_list:
				var _id:String = _ids.get(_instance.resource_path if _instance != null else "", "")
				if _id.is_empty():
					warnings.append("section %d: enemy %s has no balance id" % [_i + 1, _instance.resource_path if _instance != null else "null"])
				else:
					_enemies.append(_id)
			var _out:Dictionary = {"count": int(_wave.count), "enemies": _enemies}
			if _wave.is_boss:
				_out.is_boss = true
				_out.display_name = String(_wave.display_name)
			if int(_wave.max_alive) > 0:
				_out.max_alive = int(_wave.max_alive)
			_waves.append(_out)
		if _waves.is_empty() && _i > 0:
			break
		var _spec:Dictionary = {"waves": _waves}
		if !is_equal_approx(float(_section.get(&"spawn_density")), 1.0):
			_spec.spawn_density = int(_section.get(&"spawn_density"))
		_sections.append(_spec)
	# a room with no fight keeps no empty section
	if _sections.size() == 1 && _sections[0].waves.is_empty():
		_sections.clear()
	layout.sections = _sections

## Enemy InstanceResource path -> balance id (GameLayoutBaker's balance.json).
static func _enemy_ids(baker:LayoutBaker)->Dictionary:
	var _ids:Dictionary = {}
	if !baker.has_method(&"balance"):
		return _ids
	var _data:Dictionary = baker.call(&"balance")
	for _category:String in ["enemies", "bosses"]:
		for _id:String in _data.get(_category, {}):
			var _entry:Variant = _data[_category][_id]
			if _entry is Dictionary && _entry.has("instance"):
				_ids[_entry.instance] = _id
	return _ids

static func _item_by_scene(catalog:MapCatalog, scene_path:String, bakes:Array)->MapCatalogItem:
	for _item:MapCatalogItem in catalog.all_items():
		if _item.kind == MapCatalogItem.Kind.ENTITY && bakes.has(_item.bake) && _item.scene_path == scene_path:
			return _item
	return null

func _section_number(section:Variant, root:Node, baker:LayoutBaker)->int:
	if section is Node:
		for _i:int in baker.section_paths.size():
			if root.get_node_or_null(baker.section_paths[_i].trim_prefix("../../")) == section:
				return _i + 1
	return 1
