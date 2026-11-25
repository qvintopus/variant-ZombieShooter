## RoomLayoutResource <-> plain JSON data, for mods and stamps. Mods never ship .tres or
## .tscn (those can carry scripts): only this data, checked against the catalog on load.
##   {key, display_name, campaign, writes_balance, user_made, look, accent, patches, start, home,
##    side_room, boss_section, sections, floor: [[x, y, src, ax, ay]...],
##    walls / holes: [[x, y, 0|1]...], entities: [{item, cell: [x, y], props}...]}
class_name LayoutCodec
extends RefCounted

const VERSION:int = 1
const SECTION_KEYS:Array[String] = ["waves", "spawn_density", "max_simultaneous"]
const WAVE_KEYS:Array[String] = ["count", "enemies", "is_boss", "display_name", "max_alive"]
## Cells further out than this are dropped (keeps bakes and checks bounded).
const MAX_COORD:int = 400
const KEY_CHARS:String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

## What from_dict() dropped or fixed, for the caller to show.
var warnings:PackedStringArray = []

static func to_dict(layout:RoomLayoutResource)->Dictionary:
	var _floor:Array = []
	for _cell:Vector2i in LayoutBaker.sorted_cells(layout.floor.keys()):
		var _v:Vector3i = layout.floor[_cell]
		_floor.append([_cell.x, _cell.y, _v.x, _v.y, _v.z])
	var _entities:Array = []
	for _entity:LayoutEntity in layout.entities:
		_entities.append({"item": String(_entity.item_id), "cell": [_entity.cell.x, _entity.cell.y], "props": _entity.props.duplicate(true)})
	return {
		"version": VERSION,
		"key": layout.key, "display_name": layout.display_name, "campaign": String(layout.campaign),
		"writes_balance": layout.writes_balance, "user_made": layout.user_made, "look": layout.look, "accent": layout.accent,
		"patches": layout.patches.duplicate(true), "start": layout.start, "home": layout.home,
		"side_room": layout.side_room, "boss_section": layout.boss_section,
		"sections": layout.sections.duplicate(true),
		"floor": _floor, "walls": _flags(layout.wall_overrides), "holes": _flags(layout.hole_overrides),
		"entities": _entities,
	}

static func _flags(overrides:Dictionary)->Array:
	var _rows:Array = []
	for _cell:Vector2i in LayoutBaker.sorted_cells(overrides.keys()):
		_rows.append([_cell.x, _cell.y, 1 if overrides[_cell] else 0])
	return _rows

static func to_json(layout:RoomLayoutResource)->String:
	return JSON.stringify(to_dict(layout), "\t")

## A key usable in file and node names (letters, digits, _).
static func valid_key(text:String)->bool:
	if text.is_empty() || text.length() > 32:
		return false
	for _c:String in text:
		if !KEY_CHARS.contains(_c):
			return false
	return true

## null when the data isn't a layout; unknown items/props are dropped into `warnings`.
func from_dict(data:Variant, catalog:MapCatalog)->RoomLayoutResource:
	warnings.clear()
	if !(data is Dictionary) || !valid_key(str(data.get("key", ""))):
		warnings.append("not a room layout (missing or bad key)")
		return null
	var _layout:RoomLayoutResource = RoomLayoutResource.new()
	_layout.key = data.key
	_layout.display_name = _text(data, "display_name")
	_layout.campaign = StringName(_id(data, "campaign"))
	_layout.writes_balance = _b(data.get("writes_balance", true))
	_layout.user_made = _b(data.get("user_made", false))
	_layout.look = _id(data, "look", "base")
	_layout.accent = _id(data, "accent")
	_layout.start = _b(data.get("start", false))
	_layout.home = _b(data.get("home", false))
	_layout.side_room = _i(data.get("side_room", 0))
	_layout.boss_section = _i(data.get("boss_section", 0))
	var _patches:Array = []
	for _patch:Variant in _array(data, "patches"):
		if _patch is Array && _patch.size() == 5:
			_patches.append([_i(_patch[0]), _i(_patch[1]), _i(_patch[2]), _i(_patch[3]), safe_id(_patch[4])])
	_layout.patches = _patches
	var _sections:Array[Dictionary] = []
	for _section:Variant in _array(data, "sections"):
		if _section is Dictionary:
			_sections.append(_clean_section(_section))
	_layout.sections = _sections
	_layout.migrate()
	for _row:Variant in _array(data, "floor"):
		if _row is Array && _row.size() == 5:
			var _cell:Vector2i = Vector2i(_i(_row[0]), _i(_row[1]))
			if in_bounds(_cell):
				_layout.floor[_cell] = Vector3i(_i(_row[2]), _i(_row[3]), _i(_row[4]))
	_read_flags(_array(data, "walls"), _layout.wall_overrides)
	_read_flags(_array(data, "holes"), _layout.hole_overrides)
	var _entities:Array[LayoutEntity] = []
	for _raw:Variant in _array(data, "entities"):
		var _entity:LayoutEntity = _read_entity(_raw, catalog)
		if _entity != null:
			_entities.append(_entity)
	_layout.entities = _entities
	return _layout

func from_json(text:String, catalog:MapCatalog)->RoomLayoutResource:
	return from_dict(JSON.parse_string(text), catalog)

## Free text (names): no quotes, backslashes or line breaks, since baked values are
## written into .tscn text and must never break out of their string.
static func safe_text(value:Variant, limit:int = 60)->String:
	var _out:String = ""
	for _c:String in str(value).left(limit):
		if !(_c in ["\"", "\\", "\n", "\r", "\t"]):
			_out += _c
	return _out

## Ids, tags, room keys: letters, digits, _ and - only.
static func safe_id(value:Variant, limit:int = 64)->String:
	var _out:String = ""
	for _c:String in str(value).left(limit):
		if KEY_CHARS.contains(_c) || _c == "-":
			_out += _c
	return _out

static func _text(data:Dictionary, key:String, fallback:String = "")->String:
	return safe_text(data.get(key, fallback))

static func _id(data:Dictionary, key:String, fallback:String = "")->String:
	return safe_id(data.get(key, fallback))

static func _array(data:Dictionary, key:String)->Array:
	var _value:Variant = data.get(key, [])
	return _value if _value is Array else []

static func _read_flags(rows:Array, into:Dictionary)->void:
	for _row:Variant in rows:
		if _row is Array && _row.size() == 3:
			var _cell:Vector2i = Vector2i(_i(_row[0]), _i(_row[1]))
			if in_bounds(_cell):
				into[_cell] = _i(_row[2]) != 0

func _clean_section(section:Dictionary)->Dictionary:
	var _out:Dictionary = {}
	for _key:String in section:
		if !SECTION_KEYS.has(_key):
			warnings.append("section key '%s' dropped" % _key)
		elif _key == "waves":
			var _waves:Array = []
			for _wave:Variant in section.waves if section.waves is Array else []:
				if _wave is Dictionary:
					_waves.append(_clean_wave(_wave))
			_out.waves = _waves
		else:
			_out[_key] = _i(section[_key])
	if !_out.has("waves"):
		_out.waves = []
	return _out

func _clean_wave(wave:Dictionary)->Dictionary:
	var _out:Dictionary = {}
	for _key:String in wave:
		if !WAVE_KEYS.has(_key):
			warnings.append("wave key '%s' dropped" % _key)
			continue
		match _key:
			"enemies":
				var _ids:Array = []
				for _id:Variant in wave.enemies if wave.enemies is Array else []:
					_ids.append(safe_id(_id))
				_out.enemies = _ids
			"is_boss":
				_out.is_boss = _b(wave.is_boss)
			"display_name":
				_out.display_name = safe_text(wave.display_name)
			_:
				_out[_key] = _i(wave[_key])
	return _out

func _read_entity(raw:Variant, catalog:MapCatalog)->LayoutEntity:
	if !(raw is Dictionary) || !(raw.get("cell") is Array) || raw.cell.size() != 2:
		warnings.append("bad entity dropped")
		return null
	var _item:MapCatalogItem = catalog.item(StringName(str(raw.get("item", ""))))
	if _item == null || _item.kind != MapCatalogItem.Kind.ENTITY:
		warnings.append("unknown item '%s' dropped" % raw.get("item", ""))
		return null
	var _props:Dictionary = {}
	var _raw_props:Variant = raw.get("props", {})
	for _key:Variant in _raw_props if _raw_props is Dictionary else {}:
		var _spec:MapPropertySpec = _item.property(StringName(str(_key)))
		if _spec == null:
			warnings.append("%s: prop '%s' dropped" % [_item.id, _key])
			continue
		_props[str(_key)] = coerce(_spec, _raw_props[_key])
	var _cell:Vector2i = Vector2i(_i(raw.cell[0]), _i(raw.cell[1]))
	if !in_bounds(_cell):
		warnings.append("%s at %s is out of bounds" % [_item.id, _cell])
		return null
	return LayoutEntity.make(_item.id, _cell, _props)

## A JSON value as the spec's type.
static func coerce(spec:MapPropertySpec, value:Variant)->Variant:
	match spec.type:
		MapPropertySpec.Type.FLOAT:
			return _f(value)
		MapPropertySpec.Type.BOOL:
			return _b(value)
		MapPropertySpec.Type.STRING, MapPropertySpec.Type.ROOM:
			return safe_id(value)
		_:
			return _i(value)

static func in_bounds(cell:Vector2i)->bool:
	return absi(cell.x) <= MAX_COORD && absi(cell.y) <= MAX_COORD

## Number/bool from JSON; anything else (a dict, a list) counts as 0 / false.
static func _i(value:Variant)->int:
	if value is int || value is float || value is bool:
		return int(value)
	return str(value).to_int() if value is String else 0

static func _f(value:Variant)->float:
	if value is int || value is float || value is bool:
		return float(value)
	return str(value).to_float() if value is String else 0.0

static func _b(value:Variant)->bool:
	return _i(value) != 0
