## Live problems of the edited room, without baking: the game baker's rules
## (LayoutBaker._validate), things under a wall collider or hole, barrier / trigger lines
## with gaps (_report / _check_spans on the live layers), links to missing rooms, broken
## stairs links (CampaignLinks: one way, arriving at a missing tag, shared tags), and a
## reachability flood from the player spawn and entries over walkable cells (floor
## without wall colliders or holes) that flags what the player can't get to.
class_name MapChecks
extends RefCounted

## Entities the player has to reach (bake kinds).
const MUST_REACH:Array = [MapCatalogItem.Bake.DOOR, MapCatalogItem.Bake.PORTAL, MapCatalogItem.Bake.VICTORY,
	MapCatalogItem.Bake.TRIGGER, MapCatalogItem.Bake.SCENE, MapCatalogItem.Bake.WEAPON_SPOT]
## Spawns need a path to the player too (enemies walk).
const SPAWNS:Array = [MapCatalogItem.Bake.SPAWN, MapCatalogItem.Bake.BOSS_SPAWN]

## [{text, cell}] for the creator's layout and live layers.
static func run(creator:MapCreator)->Array[Dictionary]:
	var _out:Array[Dictionary] = []
	var _layout:RoomLayoutResource = creator.layout
	var _baker:LayoutBaker = creator.baker
	if _layout == null || _baker == null:
		return _out
	var _quiet:bool = _baker.quiet
	_baker.quiet = true
	var _problems:int = _baker.problems
	_baker.problem_list.clear()
	_baker._validate(_layout)
	var _cells:Dictionary = _baker.legend_cells(_layout)
	var _blocked:Dictionary = LayoutBaker.collider_cells(creator.walls_layer)
	_baker._report(_layout, _cells, _blocked, creator.holes_layer)
	_baker._check_spans(_layout.key, _cells, _blocked, creator.holes_layer)
	_out.append_array(_baker.problem_list)
	_baker.problem_list.clear()
	_baker.problems = _problems
	_baker.quiet = _quiet
	for _entity:LayoutEntity in _layout.entities:
		var _room:String = String(_entity.props.get("room", "")).trim_prefix("room_")
		if _entity.props.has("room") && (_room.is_empty() || !(_baker.layouts.has(_room) || ResourceLoader.exists(creator.scene_of(_room)))):
			_out.append({"text": "%s at %s leads to %s" % [_entity.item_id, _entity.cell, "nowhere" if _room.is_empty() else "missing room_" + _room], "cell": _entity.cell})
	for _problem:Dictionary in link_problems(creator):
		if !(_problem.kind in [CampaignLinks.NOWHERE, CampaignLinks.MISSING]):
			_out.append({"text": _problem.text, "cell": _problem.cell})
	_out.append_array(reachability(creator, _blocked))
	return _out

## CampaignLinks problems of the open room (its live layout against the stored others).
static func link_problems(creator:MapCreator)->Array[Dictionary]:
	if creator.layout == null || creator.baker == null:
		return []
	var _layouts:Dictionary = creator.baker.layouts.duplicate()
	_layouts[creator.key] = creator.layout
	return CampaignLinks.problems(_layouts, [creator.key],
		func (k:String)->bool: return ResourceLoader.exists(creator.scene_of(k)))

static func walkable(layout:RoomLayoutResource, cell:Vector2i, blocked:Dictionary, holes:TileMapLayer)->bool:
	return layout.floor.has(cell) && !blocked.has(cell) && holes.get_cell_source_id(cell) == -1

## Cells reachable from the player spawn (and every door / portal: a way in).
static func reachable(creator:MapCreator, blocked:Dictionary)->Dictionary:
	var _layout:RoomLayoutResource = creator.layout
	var _seen:Dictionary = {}
	var _queue:Array[Vector2i] = []
	for _entity:LayoutEntity in _layout.entities:
		var _item:MapCatalogItem = creator.catalog.item(_entity.item_id)
		if _item != null && _item.bake in [MapCatalogItem.Bake.PLAYER_SPAWN, MapCatalogItem.Bake.DOOR, MapCatalogItem.Bake.PORTAL]:
			for _start:Vector2i in _around(_entity.cell):
				if !_seen.has(_start) && walkable(_layout, _start, blocked, creator.holes_layer):
					_seen[_start] = true
					_queue.append(_start)
	while !_queue.is_empty():
		var _c:Vector2i = _queue.pop_back()
		for _d:Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var _n:Vector2i = _c + _d
			if !_seen.has(_n) && walkable(_layout, _n, blocked, creator.holes_layer):
				_seen[_n] = true
				_queue.append(_n)
	return _seen

static func reachability(creator:MapCreator, blocked:Dictionary)->Array[Dictionary]:
	var _out:Array[Dictionary] = []
	var _seen:Dictionary = reachable(creator, blocked)
	if _seen.is_empty():
		_out.append({"text": "No player spawn or entry to start from", "cell": null})
		return _out
	for _entity:LayoutEntity in creator.layout.entities:
		var _item:MapCatalogItem = creator.catalog.item(_entity.item_id)
		if _item == null || !(_item.bake in MUST_REACH || _item.bake in SPAWNS):
			continue
		var _ok:bool = false
		for _cell:Vector2i in _around(_entity.cell):
			_ok = _ok || _seen.has(_cell)
		if !_ok:
			var _what:String = "spawn has no path to the player" if _item.bake in SPAWNS else "can't be reached"
			_out.append({"text": "%s at %s %s" % [_item.display_name, _entity.cell, _what], "cell": _entity.cell})
	return _out

## A cell and its four neighbours (things stand on edges and against walls).
static func _around(cell:Vector2i)->Array[Vector2i]:
	return [cell, cell + Vector2i(1, 0), cell - Vector2i(1, 0), cell + Vector2i(0, 1), cell - Vector2i(0, 1)]
