## Selected tiles of the map creator: (cell, type) pairs. The type of what's on a cell
## (topmost wins) is an entity's item id, a painted wall, the floor look, a generated
## wall, or a hole. Floor looks group their cracked variants under the plain look.
class_name MapSelection
extends RefCounted

signal changed

const WALL:StringName = &"wall"
const HOLE:StringName = &"hole"

var creator:MapCreator
## "x,y|type" -> {cell, type}
var items:Dictionary = {}

func _init(owner:MapCreator)->void:
	creator = owner

static func entry_key(cell:Vector2i, type:StringName)->String:
	return "%d,%d|%s" % [cell.x, cell.y, type]

func is_empty()->bool:
	return items.is_empty()

func size()->int:
	return items.size()

func has(cell:Vector2i, type:StringName)->bool:
	return items.has(entry_key(cell, type))

func has_cell(cell:Vector2i)->bool:
	for _entry:Dictionary in items.values():
		if _entry.cell == cell:
			return true
	return false

func add(cell:Vector2i, type:StringName)->void:
	if type.is_empty():
		return
	items[entry_key(cell, type)] = {"cell": cell, "type": type}
	changed.emit()

func remove(cell:Vector2i, type:StringName)->void:
	if items.erase(entry_key(cell, type)):
		changed.emit()

func toggle(cell:Vector2i, type:StringName)->void:
	if has(cell, type):
		remove(cell, type)
	else:
		add(cell, type)

func clear()->void:
	if items.is_empty():
		return
	items.clear()
	changed.emit()

func set_entries(entries:Array)->void:
	items.clear()
	for _entry:Dictionary in entries:
		items[entry_key(_entry.cell, _entry.type)] = _entry
	changed.emit()

## Entries, optionally of one type.
func entries(type:StringName = &"")->Array:
	var _list:Array = []
	for _entry:Dictionary in items.values():
		if type.is_empty() || _entry.type == type:
			_list.append(_entry)
	return _list

## Distinct types, in selection order.
func types()->Array[StringName]:
	var _list:Array[StringName] = []
	for _entry:Dictionary in items.values():
		if !_list.has(_entry.type):
			_list.append(_entry.type)
	return _list

## Drops entries whose thing is gone (after an edit or undo).
func prune()->void:
	var _changed:bool = false
	for _key:String in items.keys():
		var _entry:Dictionary = items[_key]
		if !types_at(_entry.cell).has(_entry.type):
			items.erase(_key)
			_changed = true
	if _changed:
		changed.emit()

# --- what is on a cell ------------------------------------------------------------------

## Every type on a cell, topmost first.
func types_at(cell:Vector2i)->Array[StringName]:
	var _list:Array[StringName] = []
	var _layout:RoomLayoutResource = creator.layout
	if _layout == null:
		return _list
	var _entity:LayoutEntity = _layout.entity_at(cell)
	if _entity != null:
		_list.append(_entity.item_id)
	if _layout.wall_overrides.get(cell, false):
		_list.append(WALL)
	if _layout.floor.has(cell):
		var _look:StringName = floor_type(_layout.floor[cell])
		if !_look.is_empty():
			_list.append(_look)
	if !_list.has(WALL) && creator.walls_layer.get_cell_source_id(cell) != -1 && !(_layout.wall_overrides.has(cell) && !_layout.wall_overrides[cell]):
		_list.append(WALL)
	if !_layout.floor.has(cell) && creator.holes_layer.get_cell_source_id(cell) != -1:
		_list.append(HOLE)
	return _list

func type_at(cell:Vector2i)->StringName:
	var _list:Array[StringName] = types_at(cell)
	return _list[0] if !_list.is_empty() else &""

## Plain look item of a floor value (cracked variants count as their look).
func floor_type(value:Vector3i)->StringName:
	var _item:MapCatalogItem = creator.catalog.floor_item(value.x, Vector2i(0, 3))
	return _item.id if _item != null else &""

## Every cell holding `type` in the room.
func cells_of(type:StringName)->Array[Vector2i]:
	var _cells:Array[Vector2i] = []
	var _layout:RoomLayoutResource = creator.layout
	if type == WALL:
		for _cell:Vector2i in creator.walls_layer.get_used_cells():
			_cells.append(_cell)
		for _cell:Vector2i in _layout.wall_overrides:
			if _layout.wall_overrides[_cell] && !_cells.has(_cell):
				_cells.append(_cell)
	elif type == HOLE:
		for _cell:Vector2i in creator.holes_layer.get_used_cells():
			if !_layout.floor.has(_cell):
				_cells.append(_cell)
	else:
		var _item:MapCatalogItem = creator.catalog.item(type)
		if _item != null && _item.kind == MapCatalogItem.Kind.FLOOR:
			for _cell:Vector2i in _layout.floor:
				if floor_type(_layout.floor[_cell]) == type:
					_cells.append(_cell)
		else:
			for _entity:LayoutEntity in _layout.entities_of(type):
				_cells.append(_entity.cell)
	return _cells

## Types present in the room (for the radial menu), entities first.
func room_types()->Array[StringName]:
	var _list:Array[StringName] = []
	var _layout:RoomLayoutResource = creator.layout
	for _entity:LayoutEntity in _layout.entities:
		if !_list.has(_entity.item_id):
			_list.append(_entity.item_id)
	_list.append(WALL)
	if !creator.holes_layer.get_used_cells().is_empty():
		_list.append(HOLE)
	for _cell:Vector2i in _layout.floor:
		var _look:StringName = floor_type(_layout.floor[_cell])
		if !_look.is_empty() && !_list.has(_look):
			_list.append(_look)
	return _list
