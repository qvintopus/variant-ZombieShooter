## The map creator's extra painting tools: flood fill, line cells, mirror, scatter (random
## variants), the clipboard and stamps (a selection saved as JSON to reuse in any room).
## Payloads are the move ghost's: [{type, cell, floor? (Vector3i), entity? (LayoutEntity)}].
class_name MapTools
extends RefCounted

const STAMP_DIRS:PackedStringArray = ["res://addons/map_creator/resources/stamps/", "user://map_creator/stamps/"]
const USER_STAMPS:String = "user://map_creator/stamps/"

var creator:MapCreator
## Mirror the brush across the room's middle column (x) / row (y).
var mirror_x:bool
var mirror_y:bool
## Paint picks randomly among the item and its variants (MapCatalogItem.weight).
var scatter:bool
var _rng:RandomNumberGenerator = RandomNumberGenerator.new()

func _init(owner:MapCreator)->void:
	creator = owner

# --- fill -------------------------------------------------------------------------------

## Cells a fill from `cell` covers: the connected cells with the same floor value, or for
## an empty cell the connected empty cells (null when that runs past `limit`: not enclosed).
static func flood(layout:RoomLayoutResource, cell:Vector2i, limit:int)->Variant:
	var _match:Variant = layout.floor.get(cell, null)
	var _out:Array[Vector2i] = []
	var _seen:Dictionary = {cell: true}
	var _queue:Array[Vector2i] = [cell]
	while !_queue.is_empty():
		var _c:Vector2i = _queue.pop_back()
		_out.append(_c)
		if _out.size() > limit:
			return null
		for _d:Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var _n:Vector2i = _c + _d
			if _seen.has(_n) || layout.floor.get(_n, null) != _match:
				continue
			# an empty fill stops at walls painted on empty cells
			if _match == null && layout.wall_overrides.get(_n, false):
				continue
			_seen[_n] = true
			_queue.append(_n)
	return _out

## Bucket fill with the brush item at `cell` (one undo step).
func fill(cell:Vector2i, with:MapCatalogItem)->bool:
	if with == null || !creator.can_edit():
		return false
	if with.kind == MapCatalogItem.Kind.ENTITY:
		creator.message.emit("Fill paints floor, walls or holes")
		return false
	var _limit:int = creator.preset.fill_max if creator.preset != null else 4000
	var _cells:Variant = flood(creator.layout, cell, _limit)
	if _cells == null:
		creator.message.emit("Fill area isn't enclosed (over %d cells)" % _limit)
		return false
	creator.edit(func ()->void:
		for _c:Vector2i in _cells:
			for _m:Vector2i in mirrored(_c):
				creator._put(_m, pick_variant(with)), true)
	creator.message.emit("Filled %d cells" % (_cells as Array).size())
	return true

# --- line / mirror / scatter ------------------------------------------------------------

## Cells on the line from a to b (Bresenham, 8-connected).
static func line(a:Vector2i, b:Vector2i)->Array[Vector2i]:
	var _out:Array[Vector2i] = []
	var _d:Vector2i = (b - a).abs()
	var _s:Vector2i = Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var _err:int = _d.x - _d.y
	var _c:Vector2i = a
	while true:
		_out.append(_c)
		if _c == b:
			break
		var _e2:int = 2 * _err
		if _e2 > -_d.y:
			_err -= _d.y
			_c.x += _s.x
		if _e2 < _d.x:
			_err += _d.x
			_c.y += _s.y
	return _out

## `cell` plus its mirror images (x / y across the floor's bounding box middle).
func mirrored(cell:Vector2i)->Array[Vector2i]:
	var _out:Array[Vector2i] = [cell]
	if !mirror_x && !mirror_y:
		return _out
	var _sum:Vector2i = _bounds_sum()
	if mirror_x:
		_out.append(Vector2i(_sum.x - cell.x, cell.y))
	if mirror_y:
		for _c:Vector2i in _out.duplicate():
			_out.append(Vector2i(_c.x, _sum.y - _c.y))
	var _unique:Array[Vector2i] = []
	for _c:Vector2i in _out:
		if !_unique.has(_c):
			_unique.append(_c)
	return _unique

## min + max of the floor's bounding box (mirror axis * 2).
func _bounds_sum()->Vector2i:
	var _layout:RoomLayoutResource = creator.layout
	if _layout == null || _layout.floor.is_empty():
		return Vector2i.ZERO
	var _min:Vector2i = Vector2i(1 << 30, 1 << 30)
	var _max:Vector2i = -_min
	for _cell:Vector2i in _layout.floor:
		_min = _min.min(_cell)
		_max = _max.max(_cell)
	return _min + _max

## The item to paint: with scatter on, a weighted pick of the item and its variants.
func pick_variant(with:MapCatalogItem)->MapCatalogItem:
	if !scatter || with == null || with.variants.is_empty():
		return with
	var _pool:Array[MapCatalogItem] = [with]
	_pool.append_array(with.variants)
	var _total:float = 0.0
	for _item:MapCatalogItem in _pool:
		_total += maxf(_item.weight, 0.0)
	var _roll:float = _rng.randf() * _total
	for _item:MapCatalogItem in _pool:
		_roll -= maxf(_item.weight, 0.0)
		if _roll <= 0.0:
			return _item
	return with

# --- clipboard / stamps -----------------------------------------------------------------

## Copies the selection (Ctrl+C); it survives room switches (settings.clipboard).
func copy_selection()->bool:
	if creator.selection.is_empty():
		return false
	var _payload:Array = []
	for _entry:Dictionary in creator.selection.entries():
		_payload.append(creator._payload(_entry))
	creator.settings.clipboard = _payload
	creator.message.emit("Copied %d" % _payload.size())
	return true

## Pastes a payload at the cursor through the move ghost (click drops, Esc cancels).
func paste(payload:Array)->bool:
	if payload.is_empty() || !creator.can_edit():
		return false
	var _copy:Array = []
	var _origin:Vector2i = Vector2i(1 << 30, 1 << 30)
	for _p:Dictionary in payload:
		var _e:Dictionary = _p.duplicate()
		if _e.get("entity") != null:
			_e.entity = (_e.entity as LayoutEntity).copy()
		_copy.append(_e)
		_origin = _origin.min(_p.cell)
	# floors first, then the rest; the ghost's anchor is the payload's top-left
	creator.moving = {"entries": [], "payload": _copy, "copy": true, "origin": _origin, "drag": false}
	creator.message.emit("Paste %d: click to drop, Esc to cancel" % _copy.size())
	return true

static func payload_to_data(payload:Array)->Array:
	var _out:Array = []
	for _p:Dictionary in payload:
		var _row:Dictionary = {"type": String(_p.type), "cell": [_p.cell.x, _p.cell.y]}
		if _p.has("floor"):
			_row.floor = [_p.floor.x, _p.floor.y, _p.floor.z]
		if _p.get("entity") != null:
			_row.props = (_p.entity as LayoutEntity).props.duplicate(true)
		_out.append(_row)
	return _out

## Payload from stamp JSON, checked like a mod layout (catalog types, safe props).
static func payload_from_data(data:Variant, catalog:MapCatalog)->Array:
	var _out:Array = []
	for _row:Variant in data if data is Array else []:
		if !(_row is Dictionary) || !(_row.get("cell") is Array) || _row.cell.size() != 2:
			continue
		var _cell:Vector2i = Vector2i(LayoutCodec._i(_row.cell[0]), LayoutCodec._i(_row.cell[1]))
		if !LayoutCodec.in_bounds(_cell):
			continue
		var _type:StringName = StringName(LayoutCodec.safe_id(_row.get("type", "")))
		if _type == MapSelection.WALL || _type == MapSelection.HOLE:
			_out.append({"type": _type, "cell": _cell})
			continue
		var _item:MapCatalogItem = catalog.item(_type)
		if _item == null:
			continue
		if _item.kind == MapCatalogItem.Kind.FLOOR:
			var _f:Variant = _row.get("floor", [])
			var _v:Vector3i = Vector3i(_item.floor_source, _item.floor_atlas.x, _item.floor_atlas.y)
			if _f is Array && _f.size() == 3:
				_v = Vector3i(LayoutCodec._i(_f[0]), LayoutCodec._i(_f[1]), LayoutCodec._i(_f[2]))
			_out.append({"type": _type, "cell": _cell, "floor": _v})
		elif _item.kind == MapCatalogItem.Kind.ENTITY:
			var _codec:LayoutCodec = LayoutCodec.new()
			var _entity:LayoutEntity = _codec._read_entity({"item": String(_type), "cell": [_cell.x, _cell.y], "props": _row.get("props", {})}, catalog)
			if _entity != null:
				_out.append({"type": _type, "cell": _cell, "entity": _entity})
		else:
			_out.append({"type": _type, "cell": _cell})
	return _out

## Stamp name -> file, built-in ones first (a user stamp of the same name wins).
static func stamps()->Dictionary:
	var _out:Dictionary = {}
	for _dir:String in STAMP_DIRS:
		if !DirAccess.dir_exists_absolute(_dir):
			continue
		for _file:String in DirAccess.get_files_at(_dir):
			if _file.ends_with(".json"):
				_out[_file.get_basename()] = _dir.path_join(_file)
	return _out

func save_stamp(stamp_name:String)->bool:
	var _id:String = LayoutCodec.safe_id(stamp_name.replace(" ", "_"), 40)
	if _id.is_empty() || creator.selection.is_empty():
		creator.message.emit("Select something and give the stamp a name")
		return false
	var _payload:Array = []
	for _entry:Dictionary in creator.selection.entries():
		_payload.append(creator._payload(_entry))
	DirAccess.make_dir_recursive_absolute(USER_STAMPS)
	var _file:FileAccess = FileAccess.open(USER_STAMPS.path_join(_id + ".json"), FileAccess.WRITE)
	if _file == null:
		return false
	_file.store_string(JSON.stringify(payload_to_data(_payload), "\t"))
	_file.close()
	creator.message.emit("Stamp '%s' saved (%d)" % [_id, _payload.size()])
	return true

func load_stamp(path:String)->Array:
	return payload_from_data(JSON.parse_string(FileAccess.get_file_as_string(path)), creator.catalog)

func place_stamp(stamp_name:String)->bool:
	var _path:String = stamps().get(stamp_name, "")
	return !_path.is_empty() && paste(load_stamp(_path))
