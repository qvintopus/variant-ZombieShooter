## Keeps the live room's entity nodes in step with the edited layout. Each entity has a
## signature (item, cell, props). sync() frees the nodes of entities that are gone and
## builds new ones the way LayoutBaker writes them, so moves, prop edits and undo are
## all one diff. The baked nodes found at start are claimed by cell and kind.
## Starting weapon spots, the piston grid and plain marker nodes don't change live: the
## overlay shows them, and they take effect after Save and a room reload. Play can free
## nodes (a started fight frees its triggers' ArenaEntry, pickups get taken): those are
## skipped, and what has no parent left shows in the overlay only until a reload.
class_name LiveEntities
extends RefCounted

var creator:MapCreator
## signature -> Array of node lists (one per entity with that signature)
var _live:Dictionary = {}

func _init(owner:MapCreator)->void:
	creator = owner

static func signature(entity:LayoutEntity)->String:
	return "%s|%d,%d|%s" % [entity.item_id, entity.cell.x, entity.cell.y, JSON.stringify(entity.props, "", true)]

## Claims the baked nodes of every layout entity.
func claim(layout:RoomLayoutResource)->void:
	_live.clear()
	for _entity:LayoutEntity in layout.entities:
		_add_live(signature(_entity), _find_nodes(_entity))

## Frees what the layout no longer has, builds what it gained.
func sync(layout:RoomLayoutResource)->void:
	var _want:Dictionary = {}
	for _entity:LayoutEntity in layout.entities:
		var _sig:String = signature(_entity)
		_want[_sig] = _want.get(_sig, []) + [_entity]
	for _sig:String in _live.keys():
		var _lists:Array = _live[_sig]
		var _keep:int = _want.get(_sig, []).size()
		while _lists.size() > _keep:
			_free_nodes(_lists.pop_back())
		if _lists.is_empty():
			_live.erase(_sig)
	for _sig:String in _want:
		var _have:int = _live.get(_sig, []).size()
		var _entities:Array = _want[_sig]
		for _i:int in range(_have, _entities.size()):
			_add_live(_sig, _build(_entities[_i]))

## Live nodes of `entity` (freed ones left out).
func nodes_of(entity:LayoutEntity)->Array:
	var _lists:Array = _live.get(signature(entity), [])
	return _lists[0].filter(func (n:Variant)->bool: return is_instance_valid(n)) if !_lists.is_empty() else []

func _add_live(sig:String, nodes:Array)->void:
	if !_live.has(sig):
		_live[sig] = []
	_live[sig].append(nodes)

func _free_nodes(nodes:Array)->void:
	for _value:Variant in nodes:
		# play may have freed it (a typed loop variable would error on assign)
		if !is_instance_valid(_value):
			continue
		var _node:Node = _value
		if _node is BlockWall && _node.has_meta(&"source_cell"):
			creator.walls_layer.get_node("BlockWallMarkerLayer").erase_cell(_node.get_meta(&"source_cell"))
			# a raised wall leaves its cell solid for pathing
			var _block:ArenaDoorBlock = (_node as BlockWall).arena_door_block
			if _block != null && _block.is_raised():
				_block.set_raised(false, true)
		if _node.name == &"PlayerSpawner":
			continue
		_node.get_parent().remove_child(_node)
		_node.queue_free()

func _item(entity:LayoutEntity)->MapCatalogItem:
	return creator.catalog.item(entity.item_id)

func _cell_of(node:Node2D)->Vector2i:
	return creator.cell_at(node.global_position)

func _room()->Node:
	return creator.room

# --- finding baked nodes ----------------------------------------------------------------

func _find_nodes(entity:LayoutEntity)->Array:
	var _item:MapCatalogItem = _item(entity)
	if _item == null:
		return []
	var _room:Node = _room()
	match _item.bake:
		MapCatalogItem.Bake.SCENE:
			var _parent:Node = _room.get_node_or_null(_item.parent_path)
			if _parent == null:
				return []
			for _child:Node in _parent.get_children():
				if !(_child is Node2D) || _cell_of(_child) != entity.cell:
					continue
				if (!_item.scene_path.is_empty() && _child.scene_file_path == _item.scene_path) || (_item.scene_path.is_empty() && _child.name == StringName(_item.node_name)):
					return [_child]
		MapCatalogItem.Bake.DOOR, MapCatalogItem.Bake.PORTAL, MapCatalogItem.Bake.VICTORY:
			for _child:Node in _room.get_node("Behind").get_children():
				if _child is SceneEntry && (_child.scene_file_path == _item.scene_path) && _cell_of(_child) == entity.cell:
					return [_child]
		MapCatalogItem.Bake.BLOCK_WALL:
			for _child:Node in creator.walls_layer.get_children():
				if _child is BlockWall && _child.get_meta(&"source_cell", Vector2i(-99999, -99999)) == entity.cell:
					return [_child]
		MapCatalogItem.Bake.SPAWN, MapCatalogItem.Bake.BOSS_SPAWN:
			for _child:Node in _room.get_node("EnemySpawnPoints").get_children():
				if _child is SpawnPoint && _cell_of(_child) == entity.cell:
					return [_child]
		MapCatalogItem.Bake.TRIGGER:
			var _parent:Node = _room.get_node_or_null(creator.baker.trigger_nodes[_section(entity) - 1])
			if _parent != null:
				var _node:Node = _parent.get_node_or_null("Trigger_X%d_Y%d" % [entity.cell.x, entity.cell.y])
				if _node != null:
					return [_node]
		MapCatalogItem.Bake.PLAYER_SPAWN:
			return [_room.get_node("PlayerSpawner")]
	return []

func _section(entity:LayoutEntity)->int:
	return clampi(int(entity.props.get("section", 1)), 1, creator.baker.section_paths.size())

# --- building nodes ---------------------------------------------------------------------

func _build(entity:LayoutEntity)->Array:
	var _item:MapCatalogItem = _item(entity)
	if _item == null:
		return []
	var _room:Node = _room()
	var _pos:Vector2 = creator.floor_layer.map_to_local(entity.cell)
	var _p:Dictionary = entity.props
	match _item.bake:
		MapCatalogItem.Bake.SCENE:
			if _item.scene_path.is_empty():
				return []
			var _node:Node2D = (load(_item.scene_path) as PackedScene).instantiate()
			_node.position = _pos
			for _key:String in _item.fixed_props:
				_node.set(_key, str_to_var(_item.fixed_props[_key]))
			for _spec:MapPropertySpec in _item.properties:
				if !_spec.node_property.is_empty() && _p.has(_spec.key):
					_node.set(_spec.node_property, _p[_spec.key])
			return [_add(_room.get_node(_item.parent_path), _node, _node.name)]
		MapCatalogItem.Bake.DOOR, MapCatalogItem.Bake.PORTAL, MapCatalogItem.Bake.VICTORY:
			var _node:SceneEntry = (load(_item.scene_path) as PackedScene).instantiate()
			_node.position = _pos
			var _victory:String = creator.baker.victory_tag
			var _room_name:String = _p.get("room", "") if _item.bake != MapCatalogItem.Bake.VICTORY else _victory
			_node.tag = _p.get("tag", "") if _item.bake != MapCatalogItem.Bake.VICTORY else _victory
			_node.connect_tag = _p.get("connect_tag", "") if _item.bake != MapCatalogItem.Bake.VICTORY else _victory
			_node.scene_path = "%s%s.tscn" % [creator.baker.scenes_dir, _room_name if !_room_name.is_empty() else "room_" + creator.key]
			if _node.tag.is_empty():
				_node.tag = "unset"
			if _node.connect_tag.is_empty():
				_node.connect_tag = "unset"
			if _item.bake != MapCatalogItem.Bake.DOOR:
				var _waits:String = _p.get("waits_for", "") if _item.bake == MapCatalogItem.Bake.PORTAL else creator.key
				_node.set(&"open_when_cleared", StringName("room_" + _waits.trim_prefix("room_")))
				var _target:RoomLayoutResource = creator.baker.layouts.get(_room_name.trim_prefix("room_"), null)
				if _target != null:
					_node.set(&"destination_name", _target.display_name)
			return [_add(_room.get_node("Behind"), _node, "Portal" if _item.bake != MapCatalogItem.Bake.DOOR else "Stairs")]
		MapCatalogItem.Bake.BLOCK_WALL:
			var _node:BlockWall = (load(_item.scene_path) as PackedScene).instantiate()
			var _generator:BlockWallGenerator = creator.walls_layer.get_node("BlockWallGenerator")
			_node.position = creator.walls_layer.map_to_local(entity.cell) + _generator.spawn_offset
			_node.set_meta(&"generated_by_scene_tile", true)
			_node.set_meta(&"source_cell", entity.cell)
			_node.section = _room.get_node(creator.baker.section_paths[_section(entity) - 1].trim_prefix("../../"))
			_node.mode = int(_p.get("mode", _item.defaults.get("mode", 0))) as ArenaDoorBlock.WallMode
			creator.walls_layer.get_node("BlockWallMarkerLayer").set_cell(entity.cell, 1, creator.baker.block_wall_marker)
			_add(creator.walls_layer, _node, "BlockWall")
			# its deferred raise animates, which a paused (editing) room never plays: jump to the end
			_settle.call_deferred(_node)
			return [_node]
		MapCatalogItem.Bake.SPAWN, MapCatalogItem.Bake.BOSS_SPAWN:
			var _node:Marker2D = Marker2D.new()
			_node.set_script(load(_item.script_path))
			_node.position = _pos
			var _boss:bool = _item.bake == MapCatalogItem.Bake.BOSS_SPAWN
			var _index:int = maxi(creator.layout.boss_section, 1) if _boss else _section(entity)
			_node.set(&"section", _room.get_node("EnemyManager/Section%d" % _index))
			_node.set(&"boss_position", _boss)
			_node.set(&"max_simultaneous", LayoutBaker.spawner_limit(_p))
			return [_add(_room.get_node("EnemySpawnPoints"), _node, "SpawnBoss" if _boss else "Spawn_S%d" % _index)]
		MapCatalogItem.Bake.TRIGGER:
			var _node:CollisionPolygon2D = CollisionPolygon2D.new()
			_node.position = _pos
			_node.polygon = LayoutBaker.DIAMOND
			var _parent:Node = _room.get_node_or_null(creator.baker.trigger_nodes[_section(entity) - 1])
			if _parent == null:
				# its fight started (ArenaEntry freed): back after Save / reload
				_node.free()
				return []
			_node.name = "Trigger_X%d_Y%d" % [entity.cell.x, entity.cell.y]
			_parent.add_child(_node)
			return [_node]
		MapCatalogItem.Bake.PLAYER_SPAWN:
			var _spawner:Node2D = _room.get_node("PlayerSpawner")
			_spawner.position = _pos
			return [_spawner]
	return []

## Shows a new wall's raised / lowered look at once.
func _settle(wall:BlockWall)->void:
	if !is_instance_valid(wall) || wall.arena_door_block == null:
		return
	var _player:AnimationPlayer = wall.arena_door_block.animation_player
	if _player != null && !_player.current_animation.is_empty():
		_player.seek(_player.current_animation_length, true)

## Adds with a free "<base><n>" name.
func _add(parent:Node, node:Node, base:String)->Node:
	var _n:int = 1
	while parent.has_node(NodePath("%s%d" % [base, _n])):
		_n += 1
	node.name = "%s%d" % [base, _n]
	parent.add_child(node)
	return node
