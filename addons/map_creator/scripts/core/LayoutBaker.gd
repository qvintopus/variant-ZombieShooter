## Turns a RoomLayoutResource into a room scene inheriting the room template: floor,
## then the editor's Generate-from-floor + Fix Visual passes (TileVisualAutotiler),
## colliders, BlockWalls, the catalog entities and the fight sections. Overwrites
## <scenes_dir>room_<key>.tscn (keeping its uid). The map creator's live editing
## runs the same tile passes (paint_floor / generate_tiles), so a baked room matches
## what was seen while editing.
## A game subclass adds the project's own nodes (_bake_extras) and checks (_validate).
class_name LayoutBaker
extends Resource

const DIAMOND:PackedVector2Array = [Vector2(0, -8), Vector2(16, 0), Vector2(0, 8), Vector2(-16, 0)]
const AUTOTILER:String = "TileVisualAutotiler.gd"

@export_file("*.tscn") var template_path:String = "res://addons/top_down/scenes/levels/room_template.tscn"
@export_dir var scenes_dir:String = "res://game/scenes/"
@export_dir var layouts_dir:String = "res://game/rooms/layouts/"
@export var catalog:MapCatalog
## Atlas coord of the BlockWall marker tile on BlockWallMarkerLayer.
@export var block_wall_marker:Vector2i = Vector2i(3, 0)
## Trigger polygon parent per section.
@export var trigger_nodes:PackedStringArray = ["ArenaEntry", "ArenaSection1Entry", "ArenaSection2Entry"]
## ArenaSection path per section, relative to a WallLayer_Ysorted child.
@export var section_paths:PackedStringArray = ["../../EnemyManager/Section1", "../../EnemyManager/Section2", "../../EnemyManager/Section3"]
## Tag of a boss room's victory exit portal (Portal.VICTORY).
@export var victory_tag:String = "victory"
@export_file("*.gd") var wave_script_path:String = "res://addons/top_down/scripts/arena/SpawnWaveList.gd"
@export_file("*.gd") var instance_script_path:String = "res://addons/great_games_library/resources/InstanceResource/InstanceResource.gd"

## Problems found since the last reset (each also printed).
var problems:int = 0
## Every problem since the last reset_problems(): {text, cell (Vector2i or null)}.
var problem_list:Array[Dictionary] = []
## Every layout by key (portal destination names and links).
var layouts:Dictionary = {}
## No printing (the editor's live checks list problems themselves).
var quiet:bool
## Writes the scenes here instead of scenes_dir (checks); links and uids stay scenes_dir's.
var write_dir:String

## Loads every layout in layouts_dir into `layouts`.
func load_layouts()->Dictionary:
	layouts.clear()
	for _file:String in DirAccess.get_files_at(layouts_dir):
		# exported builds list converted resources as <name>.tres.remap
		_file = _file.trim_suffix(".remap")
		if !_file.ends_with(".tres"):
			continue
		var _layout:RoomLayoutResource = ResourceLoader.load(layouts_dir.path_join(_file), "", ResourceLoader.CACHE_MODE_REPLACE)
		if _layout != null:
			layouts[_layout.key] = _layout
	return layouts

func layout_path(key:String)->String:
	return layouts_dir.path_join("room_%s.tres" % key)

func scene_path(key:String)->String:
	return scenes_dir + "room_" + key + ".tscn"

## Where bake() writes room_<key>.tscn (write_dir in checks, else scene_path).
func written_path(key:String)->String:
	return scene_path(key) if write_dir.is_empty() else write_dir.path_join("room_%s.tscn" % key)

func save_layout(layout:RoomLayoutResource)->Error:
	layouts[layout.key] = layout
	return ResourceSaver.save(layout, layout_path(layout.key))

## Paints the layout floor (sources and atlas before the visual autotile).
static func paint_floor(floor_layer:TileMapLayer, layout:RoomLayoutResource)->void:
	floor_layer.clear()
	for _cell:Vector2i in sorted_cells(layout.floor.keys()):
		var _v:Vector3i = layout.floor[_cell]
		floor_layer.set_cell(_cell, _v.x, Vector2i(_v.y, _v.z))

## Holes and walls from the floor (plus the layout overrides), then every layer's
## visual autotile. step(fraction) reports progress.
static func generate_tiles(floor_layer:TileMapLayer, holes:TileMapLayer, walls:TileMapLayer, layout:RoomLayoutResource, step:Callable = Callable())->void:
	var _layers:Array[TileMapLayer] = [holes, walls]
	var _overrides:Array = [layout.hole_overrides, layout.wall_overrides]
	for _i:int in _layers.size():
		var _autotiler:TileVisualAutotiler = autotiler_of(_layers[_i])
		_layers[_i].clear()
		_autotiler.generate_from_floor()
		apply_overrides(_layers[_i], floor_layer, _autotiler.marker_atlas, _overrides[_i])
		_autotiler.autotile()
		if step.is_valid():
			step.call(0.3 + 0.3 * _i)
	autotiler_of(floor_layer).autotile()

## Forces cells on (true, in the nearest floor's look) or off (false).
static func apply_overrides(layer:TileMapLayer, floor_layer:TileMapLayer, marker_atlas:Vector2i, overrides:Dictionary)->void:
	if overrides.is_empty():
		return
	var _default:int = layer.tile_set.get_source_id(0)
	for _cell:Vector2i in overrides:
		if !overrides[_cell]:
			layer.erase_cell(_cell)
		elif layer.get_cell_source_id(_cell) == -1:
			layer.set_cell(_cell, TileVisualAutotiler.nearest_look_source(floor_layer, layer.tile_set, _cell, _default), marker_atlas)

## Row by row (y, then x): the order cells were first painted in, so a bake is stable.
static func sorted_cells(cells:Array)->Array:
	cells.sort_custom(func (a:Vector2i, b:Vector2i)->bool: return a.y < b.y || (a.y == b.y && a.x < b.x))
	return cells

static func autotiler_of(layer:Node)->TileVisualAutotiler:
	for _child:Node in layer.get_children():
		if _child is TileVisualAutotiler:
			return _child
	return null

## Bakes one layout; returns its context (path, spawns, door_names...) or {} on failure.
## With target_dir (a mod's cache) the scene is written there without a uid, so it
## never clashes with the built-in room it overrides; links stay canonical (scenes_dir).
func bake(layout:RoomLayoutResource, target_dir:String = "")->Dictionary:
	if !layouts.has(layout.key):
		layouts[layout.key] = layout
	_validate(layout)
	var _root:Node2D = (load(template_path) as PackedScene).instantiate()
	var _floor:TileMapLayer = _root.get_node("Background/FloorLayer")
	var _holes:TileMapLayer = _root.get_node("Background/ObstacleLayer")
	var _walls:TileMapLayer = _root.get_node("WallLayer_Ysorted")
	var _markers:TileMapLayer = _walls.get_node("BlockWallMarkerLayer")
	for _layer:TileMapLayer in [_floor, _holes, _walls, _markers]:
		_layer.clear()

	var _cells:Dictionary = legend_cells(layout)
	paint_floor(_floor, layout)
	generate_tiles(_floor, _holes, _walls, layout)
	var _sorted:Array[LayoutEntity] = layout.sorted_entities()
	for _entity:LayoutEntity in _sorted:
		if _item(_entity).bake == MapCatalogItem.Bake.BLOCK_WALL:
			_markers.set_cell(_entity.cell, 1, block_wall_marker)
	_walls.get_node("BlockWallGenerator").setup_scenes()
	for _body:Node in [_holes.get_node("StaticBody2D"), _walls.get_node("StaticBody2D")]:
		_body.setup_colliders()
	var _blocked:Dictionary = collider_cells(_walls)
	_report(layout, _cells, _blocked, _holes)
	_check_spans(layout.key, _cells, _blocked, _holes)

	var _out:SceneText = SceneText.new()
	var _path:String = scene_path(layout.key) if target_dir.is_empty() else target_dir.path_join("room_%s.tscn" % layout.key)
	_out.uid = _existing_uid(_path) if target_dir.is_empty() else ""
	_out.node("Room", "", {}, _out.ext("PackedScene", template_path))
	for _layer:TileMapLayer in [_floor, _holes, _walls]:
		_out.node(_layer.name, _root.get_path_to(_layer.get_parent()), {
			"tile_map_data": "PackedByteArray(\"%s\")" % Marshalls.raw_to_base64(_layer.tile_map_data) if !_layer.tile_map_data.is_empty() else "PackedByteArray()",
		})
	for _body:Node in [_holes.get_node("StaticBody2D"), _walls.get_node("StaticBody2D")]:
		for _shape:CollisionPolygon2D in _body.get_children():
			_out.node(_shape.name, _root.get_path_to(_body), {
				"position": var_to_str(_shape.position),
				"polygon": var_to_str(_shape.polygon),
			}, "", "CollisionPolygon2D")

	var _block_wall:String = _out.ext("PackedScene", _catalog_scene(MapCatalogItem.Bake.BLOCK_WALL))
	for _node:Node in _walls.get_children():
		if !_node.has_meta("source_cell"):
			continue
		var _cell:Vector2i = _node.get_meta("source_cell")
		var _entity:LayoutEntity = layout.entity_at(_cell)
		var _props:Dictionary = {"position": var_to_str(_node.position)}
		_props.section = "NodePath(\"%s\")" % section_paths[_section_index(_entity)]
		if int(_entity.props.get("mode", _item(_entity).defaults.get("mode", 0))) == 1:
			_props.mode = "1" # ArenaDoorBlock.WallMode.GATE
		_props["metadata/generated_by_scene_tile"] = "true"
		_props["metadata/source_cell"] = var_to_str(_cell)
		_out.node(_node.name, "WallLayer_Ysorted", _props, _block_wall)

	var _door_scene:String = _out.ext("PackedScene", _catalog_scene(MapCatalogItem.Bake.DOOR))
	var _spawn_script:String = _out.ext("Script", _catalog_item(MapCatalogItem.Bake.SPAWN).script_path)
	var _ctx:Dictionary = {
		"path": _path, "spawns": {}, "door_names": PackedStringArray(), "weapon_spots": PackedStringArray(),
	}
	var _portal_index:int = 0
	var _spawn_counts:Array[int] = [0, 0, 0]
	var _door_index:int = 0
	var _prop_counts:Dictionary = {}
	for _entity:LayoutEntity in _sorted:
		var _item:MapCatalogItem = _item(_entity)
		var _p:Dictionary = _entity.props
		var _pos:String = var_to_str(_floor.map_to_local(_entity.cell))
		match _item.bake:
			MapCatalogItem.Bake.DOOR:
				_door_index += 1
				var _door_name:String = "Stairs" if _door_index == 1 else "Stairs%d" % _door_index
				_ctx.door_names.append("NodePath(\"../Behind/%s\")" % _door_name)
				_out.node(_door_name, "Behind", {
					"position": _pos,
					"tag": "\"%s\"" % _p.get("tag", ""),
					"connect_tag": "\"%s\"" % _p.get("connect_tag", ""),
					"scene_path": "\"%s%s.tscn\"" % [scenes_dir, _p.get("room", "")],
				}, _door_scene)
			MapCatalogItem.Bake.PORTAL, MapCatalogItem.Bake.VICTORY:
				_portal_index += 1
				var _portal:Array = [victory_tag, victory_tag, victory_tag, layout.key]
				if _item.bake == MapCatalogItem.Bake.PORTAL:
					_portal = [_p.get("tag", ""), _p.get("connect_tag", ""), _p.get("room", ""), _p.get("waits_for", "")]
				var _portal_props:Dictionary = {
					"position": _pos,
					"tag": "\"%s\"" % _portal[0],
					"connect_tag": "\"%s\"" % _portal[1],
					"scene_path": "\"%s%s.tscn\"" % [scenes_dir, _portal[2]],
					"open_when_cleared": "&\"room_%s\"" % String(_portal[3]).trim_prefix("room_"),
				}
				# the victory exit labels itself EXTRACT
				var _destination:RoomLayoutResource = layouts.get(String(_portal[2]).trim_prefix("room_"), null)
				if _destination != null && !_destination.display_name.is_empty():
					_portal_props.destination_name = "\"%s\"" % _destination.display_name
				_out.node("Portal" if _portal_index == 1 else "Portal%d" % _portal_index, "Behind", _portal_props, _out.ext("PackedScene", _item.scene_path))
			MapCatalogItem.Bake.SCENE:
				_bake_scene(_out, _item, _entity, _pos, _prop_counts)
			MapCatalogItem.Bake.PLAYER_SPAWN:
				_out.node("PlayerSpawner", ".", {"position": _pos})
			MapCatalogItem.Bake.WEAPON_SPOT:
				_ctx.weapon_spots.append(_pos)
			MapCatalogItem.Bake.PISTON_GRID:
				_out.node("PistonGrid", "WallLayer_Ysorted", {
					"script": _out.ext("Script", _item.script_path),
					"y_sort_enabled": "true",
					"size": str(_p.get("grid_size", 30)),
					"origin_cell": var_to_str(_entity.cell),
					"floor_layer": "NodePath(\"../../Background/FloorLayer\")",
					"piston_scene": _out.ext("PackedScene", _item.fixed_props.get("piston_scene", "")),
					"lever_scene": _out.ext("PackedScene", _item.fixed_props.get("lever_scene", "")),
				}, "", "Node2D")
			MapCatalogItem.Bake.SPAWN, MapCatalogItem.Bake.BOSS_SPAWN:
				var _boss:bool = _item.bake == MapCatalogItem.Bake.BOSS_SPAWN
				var _index:int = maxi(layout.boss_section, 1) - 1 if _boss else _section_index(_entity)
				var _props:Dictionary = {"position": _pos, "script": _spawn_script, "section": "NodePath(\"%s\")" % section_paths[_index]}
				var _name:String = "SpawnBoss"
				var _max:int = 1
				if _boss:
					_props.boss_position = "true"
				else:
					_spawn_counts[_index] += 1
					_name = "Spawn_S%d_%d" % [_index + 1, _spawn_counts[_index]]
					_max = int(_p.get("max_simultaneous", layout.section_spec(_index).get("max_simultaneous", 1)))
					_props.max_simultaneous = str(_max)
				_ctx.spawns[_name] = {"section": _index, "max_simultaneous": _max}
				_out.node(_name, "EnemySpawnPoints", _props, "", "Marker2D")
			MapCatalogItem.Bake.TRIGGER:
				_out.node("Trigger_X%d_Y%d" % [_entity.cell.x, _entity.cell.y], trigger_nodes[_section_index(_entity)], {
					"position": _pos,
					"polygon": var_to_str(DIAMOND),
				}, "", "CollisionPolygon2D")

	_write_sections(_out, layout)
	_bake_extras(_out, layout, _ctx)
	_out.editable.append("EnemyManager")

	var _write_path:String = _path if write_dir.is_empty() || !target_dir.is_empty() else write_dir.path_join(_path.get_file())
	var _file:FileAccess = FileAccess.open(_write_path, FileAccess.WRITE)
	if _file == null:
		problem("%s: can't write %s" % [layout.key, _write_path])
		_ctx = {}
	else:
		_file.store_string(_out.text())
		_file.close()
	_root.free()
	return _ctx

## Contraptions, hazards and markers: an instance of scene_path (named after its root,
## numbered) or a plain node_type node.
func _bake_scene(out:SceneText, item:MapCatalogItem, entity:LayoutEntity, pos:String, counts:Dictionary)->void:
	var _props:Dictionary = {}
	if !item.script_path.is_empty():
		_props.script = out.ext("Script", item.script_path)
	_props.position = pos
	for _key:String in item.fixed_props:
		_props[_key] = item.fixed_props[_key]
	for _spec:MapPropertySpec in item.properties:
		if !_spec.node_property.is_empty() && entity.props.has(_spec.key):
			_props[_spec.node_property] = _spec.to_scene_value(entity.props[_spec.key])
	if item.scene_path.is_empty():
		out.node(item.node_name, item.parent_path, _props, "", item.node_type)
		return
	var _name:String = item.node_name
	if _name.is_empty():
		var _base:String = (load(item.scene_path) as PackedScene).get_state().get_node_name(0)
		counts[_base] = counts.get(_base, 0) + 1
		_name = "%s%d" % [_base, counts[_base]]
	out.node(_name, item.parent_path, _props, out.ext("PackedScene", item.scene_path))

func _write_sections(out:SceneText, layout:RoomLayoutResource)->void:
	var _wave_script:String = out.ext("Script", wave_script_path)
	var _instance_script:String = out.ext("Script", instance_script_path)
	for _i:int in layout.sections.size():
		var _spec:Dictionary = layout.sections[_i]
		var _waves:PackedStringArray = []
		for _wave_spec:Dictionary in _spec.waves:
			var _props:Dictionary = {"script": _wave_script}
			if _wave_spec.get("is_boss", false):
				_props.is_boss = "true"
				_props.display_name = "\"%s\"" % _wave_spec.display_name
			_props.count = str(_wave_spec.count)
			if _wave_spec.has("max_alive"):
				_props.max_alive = str(_wave_spec.max_alive)
			var _instances:PackedStringArray = []
			for _id:String in _wave_spec.enemies:
				_instances.append(out.ext("Resource", _enemy_instance_path(_id)))
			_props.instance_list = "Array[%s]([%s])" % [_instance_script, ", ".join(_instances)]
			_waves.append(out.sub("Resource", _props))
		var _props:Dictionary = {"waves": "Array[%s]([%s])" % [_wave_script, ", ".join(_waves)]}
		if _spec.has("spawn_density"):
			_props.spawn_density = "%.1f" % _spec.spawn_density
		if _i + 1 == layout.side_room:
			# The template chains every section to the one before; a side room opts out.
			_props.requires = "NodePath(\"\")"
		elif _i > 0:
			_props.requires = "NodePath(\"../Section%d\")" % _i
		out.node("Section%d" % (_i + 1), "EnemyManager", _props)

## Rules a layout can't show (override in the game baker).
func _validate(_layout:RoomLayoutResource)->void:
	pass

## Project nodes after the sections (override in the game baker).
func _bake_extras(_out:SceneText, _layout:RoomLayoutResource, _ctx:Dictionary)->void:
	pass

## InstanceResource path of an enemy id (override to look ids up).
func _enemy_instance_path(id:String)->String:
	return id

func _item(entity:LayoutEntity)->MapCatalogItem:
	var _found:MapCatalogItem = catalog.item(entity.item_id)
	assert(_found != null, "unknown catalog item '%s'" % entity.item_id)
	return _found

func _catalog_item(bake_kind:MapCatalogItem.Bake)->MapCatalogItem:
	for _entry:MapCatalogItem in catalog.all_items():
		if _entry.kind == MapCatalogItem.Kind.ENTITY && _entry.bake == bake_kind:
			return _entry
	return null

func _catalog_scene(bake_kind:MapCatalogItem.Bake)->String:
	return _catalog_item(bake_kind).scene_path

func _section_index(entity:LayoutEntity)->int:
	return clampi(int(entity.props.get("section", 1)) - 1, 0, section_paths.size() - 1)

## Cell -> legend char: "." floor, entities by their catalog legend (span checks, report).
func legend_cells(layout:RoomLayoutResource)->Dictionary:
	var _cells:Dictionary = {}
	for _cell:Vector2i in layout.floor:
		_cells[_cell] = "."
	for _entity:LayoutEntity in layout.entities:
		var _item:MapCatalogItem = catalog.item(_entity.item_id)
		var _c:String = _item.legend_char(_entity.props) if _item != null else "?"
		_cells[_entity.cell] = _c if !_c.is_empty() else "?"
	return _cells

## Keeps a rebuilt room's uid so references made by the editor stay valid.
func _existing_uid(path:String)->String:
	if FileAccess.file_exists(path):
		var _header:String = FileAccess.get_file_as_string(path).get_slice("\n", 0)
		var _at:int = _header.find("uid=\"")
		if _at != -1:
			return _header.substr(_at + 5).get_slice("\"", 0)
	return ResourceUID.id_to_text(ResourceUID.create_id())

## Cells with a wall collider. The wall tiles on a region's +x/+y edge are drawn on
## floor cells but their colliders sit one cell further out, so those cells stay walkable.
static func collider_cells(walls:TileMapLayer)->Dictionary:
	var _blocked:Dictionary = {}
	for _shape:Node2D in walls.get_node("StaticBody2D").get_children():
		_blocked[walls.local_to_map(_shape.position)] = true
	return _blocked

## Prints the generated layout (# wall collider, o hole) and flags marked cells that
## ended up blocked.
func _report(layout:RoomLayoutResource, cells:Dictionary, blocked:Dictionary, holes:TileMapLayer)->void:
	var _size:Vector2i = Vector2i.ZERO
	for _cell:Vector2i in cells:
		_size = _size.max(_cell + Vector2i(2, 2))
	if !quiet:
		print("room_%s (%s)" % [layout.key, layout.display_name])
	for _y:int in range(-1, _size.y):
		var _line:String = ""
		for _x:int in range(-1, _size.x):
			var _cell:Vector2i = Vector2i(_x, _y)
			var _c:String = cells.get(_cell, " ")
			var _covered:bool = blocked.has(_cell) || holes.get_cell_source_id(_cell) != -1
			if _covered && _c != " " && _c != ".":
				problem("%s: '%s' at %s is under a wall collider or hole" % [layout.key, _c, _cell], _cell)
			if blocked.has(_cell):
				_c = "#"
			elif holes.get_cell_source_id(_cell) != -1:
				_c = "o"
			_line += _c
		if !quiet:
			print("  " + _line)

## Every BlockWall and trigger line must reach a wall collider (or hole) at both ends,
## or the player walks around it.
func _check_spans(key:String, cells:Dictionary, blocked:Dictionary, holes:TileMapLayer)->void:
	var _walkable:Callable = func (cell:Vector2i)->bool:
		return cells.has(cell) && !blocked.has(cell) && holes.get_cell_source_id(cell) == -1
	for _cell:Vector2i in cells:
		var _c:String = cells[_cell]
		if !(_c in ["1", "2", "3", "a", "b", "x", "y", "z"]):
			continue
		# Blocks (pillars) stand free; only one-cell-thick lines close a passage.
		var _across:bool = cells.get(_cell + Vector2i(1, 0)) == _c || cells.get(_cell - Vector2i(1, 0)) == _c
		var _down:bool = cells.get(_cell + Vector2i(0, 1)) == _c || cells.get(_cell - Vector2i(0, 1)) == _c
		if _across && _down:
			continue
		# A line runs along the axis where it has a neighbour of the same char.
		for _dir:Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if cells.get(_cell + _dir) != _c && cells.get(_cell - _dir) != _c:
				continue
			for _step:Vector2i in [_dir, -_dir]:
				var _next:Vector2i = _cell + _step
				if cells.get(_next) != _c && _walkable.call(_next):
					problem("%s: '%s' line at %s leaves a gap at %s" % [key, _c, _cell, _next], _next)

func problem(message:String, cell:Variant = null)->void:
	problems += 1
	problem_list.append({"text": message, "cell": cell})
	if !quiet:
		printerr("PROBLEM: ", message)

func reset_problems()->void:
	problems = 0
	problem_list.clear()
