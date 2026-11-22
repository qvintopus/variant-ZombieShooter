## The source of a room: floor cells, wall/hole overrides, placed entities and the
## fight sections. LayoutBaker turns it into the room scene (inheriting
## room_template.tscn); the in-game map creator edits it live and re-bakes on save.
##
## Cells are TileMapLayer coords: +x is screen bottom-right, +y screen bottom-left.
## Walls are generated around the floor (outside on the -x/-y edges, ON the floor cell on
## the +x/+y edges, so keep doors, spawns and triggers off a region's last column/row);
## empty cells enclosed by floor become holes. wall_overrides / hole_overrides force a
## cell on (true) or off (false) after that generation.
##
## Entities (catalog item ids, see addons/map_creator/resources/catalog):
##   door (stairs: tag, connect_tag, room)  portal (tag, connect_tag, room, waits_for)
##   victory (boss room exit)  barrier / gate (BlockWall of a section)
##   trigger (starts a section)  spawn (section, max_simultaneous)  boss_spawn
##   player_spawn  weapon_spot (start rooms: the doors stay shut until every one is
##   picked up)  contraptions, hazards and home base pieces (piston_grid: grid_size,
##   lever column/row at +1 x/y of the corner, keep them floor).
## Section dicts: {waves: [{count, enemies, is_boss?, display_name?, max_alive?}],
## spawn_density?}. spawn_density = enemies each spawner keeps alive (a spawner's own
## max_simultaneous caps it); max_alive = the wave's alive target (spawners keep that
## many up, past their density). Old layouts' section max_simultaneous is folded into
## spawn_density on load (migrate()).
class_name RoomLayoutResource
extends Resource

## Room key: the scene is room_<key>.tscn, the room id &"room_<key>".
@export var key:String
@export var display_name:String
## Campaign it belongs to (new_game, new_game_plus, boss_path, home).
@export var campaign:StringName
## Campaign rooms get a maps.json "rooms" entry (waves, spawn caps, loot) and portal/victory checks.
@export var writes_balance:bool = true
## Made in the map creator (New / Copy): not a shipped original, edited without asking.
@export var user_made:bool

@export_group("Look")
## Default floor look (base, mossy, bloody, metal, sandstone, flesh, blotch).
@export var look:String = "base"
@export var accent:String
## [x0, y0, x1, y1, look] rects the floor was first painted with.
@export var patches:Array = []

@export_group("Room")
## The campaign's first room (FreshStart, no sections).
@export var start:bool
## The home base (HomeBase instead of FreshStart).
@export var home:bool
## 1-based section of an optional alcove (no "requires"); 0 = none.
@export var side_room:int
## 1-based boss section (must be the last); 0 = none.
@export var boss_section:int
@export var sections:Array[Dictionary] = []

@export_group("Cells")
## Cell -> Vector3i(tileset source, atlas x, atlas y), before the visual autotile.
@export var floor:Dictionary[Vector2i, Vector3i] = {}
@export var wall_overrides:Dictionary[Vector2i, bool] = {}
@export var hole_overrides:Dictionary[Vector2i, bool] = {}
@export var entities:Array[LayoutEntity] = []

## Independent copy (undo snapshots, editing without touching the cached layout).
func clone()->RoomLayoutResource:
	var _copy:RoomLayoutResource = RoomLayoutResource.new()
	for _property:Dictionary in get_property_list():
		var _name:String = _property.name
		if _property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE && _property.usage & PROPERTY_USAGE_STORAGE && _name != "entities":
			var _value:Variant = get(_name)
			_copy.set(_name, _value.duplicate(true) if _value is Array || _value is Dictionary else _value)
	var _list:Array[LayoutEntity] = []
	for _entity:LayoutEntity in entities:
		_list.append(_entity.copy())
	_copy.entities = _list
	return _copy

func scene_name()->String:
	return "room_" + key

func room_id()->StringName:
	return StringName(scene_name())

func entity_at(cell:Vector2i)->LayoutEntity:
	for _entity:LayoutEntity in entities:
		if _entity.cell == cell:
			return _entity
	return null

func entities_of(id:StringName)->Array[LayoutEntity]:
	var _list:Array[LayoutEntity] = []
	for _entity:LayoutEntity in entities:
		if _entity.item_id == id:
			_list.append(_entity)
	return _list

## Row by row (y, then x): the order Stairs/spawn numbering follows.
func sorted_entities()->Array[LayoutEntity]:
	var _list:Array[LayoutEntity] = entities.duplicate()
	_list.sort_custom(func (a:LayoutEntity, b:LayoutEntity)->bool: return a.cell.y < b.cell.y || (a.cell.y == b.cell.y && a.cell.x < b.cell.x))
	return _list

func has_item(id:StringName)->bool:
	return !entities_of(id).is_empty()

## Folds the old per-section spawner cap into spawn_density (same baked result:
## a spawner kept min(density, cap) alive). True when something changed.
func migrate()->bool:
	var _changed:bool = false
	for _section:Dictionary in sections:
		if !_section.has("max_simultaneous"):
			continue
		var _density:float = float(_section.get("spawn_density", 1))
		var _cap:int = int(_section.max_simultaneous)
		_section.erase("max_simultaneous")
		if _density >= 1.0 && _cap < roundi(_density):
			if _cap <= 1:
				_section.erase("spawn_density")
			else:
				_section.spawn_density = _cap
		_changed = true
	return _changed

func section_spec(index:int)->Dictionary:
	return sections[index] if index >= 0 && index < sections.size() else {}

## Bounding size in cells (from 0,0).
func size()->Vector2i:
	var _size:Vector2i = Vector2i.ZERO
	for _cell:Vector2i in floor:
		_size = _size.max(_cell + Vector2i.ONE)
	return _size

## The old ASCII spec shape (name, look, start, side_room, boss_section, sections,
## doors, portals...), for checks written against it.
func to_spec()->Dictionary:
	var _spec:Dictionary = {"name": display_name, "look": look, "sections": sections, "doors": {}}
	if !accent.is_empty():
		_spec.accent = accent
	if !patches.is_empty():
		_spec.patches = patches
	if start:
		_spec.start = true
	if home:
		_spec.home = true
	if side_room > 0:
		_spec.side_room = side_room
	if boss_section > 0:
		_spec.boss_section = boss_section
	var _portals:Dictionary = {}
	for _entity:LayoutEntity in sorted_entities():
		var _p:Dictionary = _entity.props
		if _entity.item_id == &"door":
			_spec.doors[str(_spec.doors.size())] = [_p.get("tag", ""), _p.get("connect_tag", ""), _p.get("room", "")]
		elif _entity.item_id == &"portal":
			_portals[str(_portals.size())] = [_p.get("tag", ""), _p.get("connect_tag", ""), _p.get("room", ""), _p.get("waits_for", "")]
	if !_portals.is_empty():
		_spec.portals = _portals
	return _spec
