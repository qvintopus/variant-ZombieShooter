## Campaigns of the workspace: {id, display_name, start, nodes: {key: [x, y]}} dicts.
## A room belongs to the campaign named by its layout's `campaign`; the dicts add the
## start room and the graph positions. Kept in the mod's mod.json, or in
## project_file for the base game (editor only). Campaigns only named by layouts get a dict.
class_name CampaignStore
extends RefCounted

const PROJECT_FILE:String = "res://game/rooms/campaigns.json"

var baker:LayoutBaker
var mods:MapModState
var campaigns:Array[Dictionary] = []

func _init(layout_baker:LayoutBaker, mod_state:MapModState)->void:
	baker = layout_baker
	mods = mod_state
	reload()

func _mod()->MapModInfo:
	return mods.active_mod() if mods != null && mods.is_active() else null

func reload()->void:
	campaigns.clear()
	var _raw:Array = []
	var _mod:MapModInfo = _mod()
	if _mod != null:
		_raw = _mod.campaigns
	elif FileAccess.file_exists(PROJECT_FILE):
		var _data:Variant = JSON.parse_string(FileAccess.get_file_as_string(PROJECT_FILE))
		_raw = _data if _data is Array else []
	for _entry:Variant in _raw:
		var _clean:Dictionary = clean(_entry)
		if !_clean.is_empty() && find(_clean.id).is_empty():
			campaigns.append(_clean)
	# campaigns named by layouts but not listed yet
	for _key:String in baker.layouts:
		var _id:String = String(baker.layouts[_key].campaign)
		if !_id.is_empty() && find(_id).is_empty():
			campaigns.append({"id": _id, "display_name": _id.capitalize(), "start": "", "nodes": {}})
	for _campaign:Dictionary in campaigns:
		if String(_campaign.start).is_empty() || !baker.layouts.has(_campaign.start):
			_campaign.start = _guess_start(_campaign.id)

## A campaign dict from JSON (mod.json is shared data): ids and keys stay safe.
static func clean(entry:Variant)->Dictionary:
	if !(entry is Dictionary):
		return {}
	var _id:String = LayoutCodec.safe_id(entry.get("id", ""), 32)
	if _id.is_empty():
		return {}
	var _nodes:Dictionary = {}
	var _raw_nodes:Variant = entry.get("nodes", {})
	for _key:Variant in _raw_nodes if _raw_nodes is Dictionary else {}:
		var _pos:Variant = _raw_nodes[_key]
		if _pos is Array && _pos.size() == 2:
			_nodes[LayoutCodec.safe_id(_key, 32)] = [LayoutCodec._f(_pos[0]), LayoutCodec._f(_pos[1])]
	return {
		"id": _id,
		"display_name": LayoutCodec.safe_text(entry.get("display_name", _id)),
		"start": LayoutCodec.safe_id(entry.get("start", ""), 32),
		"nodes": _nodes,
	}

func find(id:String)->Dictionary:
	for _campaign:Dictionary in campaigns:
		if _campaign.id == id:
			return _campaign
	return {}

func rooms_of(id:String)->PackedStringArray:
	var _keys:PackedStringArray = []
	for _key:String in baker.layouts:
		if String(baker.layouts[_key].campaign) == id:
			_keys.append(_key)
	_keys.sort()
	return _keys

func _guess_start(id:String)->String:
	for _key:String in rooms_of(id):
		if baker.layouts[_key].start || baker.layouts[_key].home:
			return _key
	var _keys:PackedStringArray = rooms_of(id)
	return _keys[0] if !_keys.is_empty() else ""

func add(id:String, display_name:String)->Dictionary:
	var _id:String = LayoutCodec.safe_id(id.to_lower().replace(" ", "_"), 32)
	if _id.is_empty() || !find(_id).is_empty():
		return {}
	var _campaign:Dictionary = {"id": _id, "display_name": LayoutCodec.safe_text(display_name), "start": "", "nodes": {}}
	campaigns.append(_campaign)
	return _campaign

func save()->Error:
	var _mod:MapModInfo = _mod()
	if _mod != null:
		_mod.campaigns = campaigns.duplicate(true)
		return _mod.save()
	if !OS.has_feature("editor"):
		return ERR_UNAUTHORIZED
	var _file:FileAccess = FileAccess.open(PROJECT_FILE, FileAccess.WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	_file.store_string(JSON.stringify(campaigns, "\t"))
	_file.close()
	return OK

## Door / portal links between rooms: [{from, entity (index), to, tag, kind}].
func links()->Array[Dictionary]:
	var _out:Array[Dictionary] = []
	for _key:String in baker.layouts:
		var _layout:RoomLayoutResource = baker.layouts[_key]
		for _i:int in _layout.entities.size():
			var _entity:LayoutEntity = _layout.entities[_i]
			if !_entity.props.has("room"):
				continue
			_out.append({
				"from": _key, "entity": _i, "to": String(_entity.props.room).trim_prefix("room_"),
				"tag": String(_entity.props.get("connect_tag", "")), "kind": _entity.item_id,
			})
	return _out

## Entities of `key` that rooms link into or out of (doors, portals, victory): indices.
static func exits_of(layout:RoomLayoutResource)->Array[int]:
	var _out:Array[int] = []
	for _i:int in layout.entities.size():
		if layout.entities[_i].item_id in [&"door", &"portal", &"victory"]:
			_out.append(_i)
	return _out

## Grid positions for rooms without one: columns by link distance from the start.
func auto_layout(id:String, spacing:Vector2 = Vector2(200, 110))->void:
	var _campaign:Dictionary = find(id)
	if _campaign.is_empty():
		return
	var _rooms:PackedStringArray = rooms_of(id)
	var _depth:Dictionary = {}
	var _queue:Array = []
	if _rooms.has(_campaign.start):
		_depth[_campaign.start] = 0
		_queue.append(_campaign.start)
	var _all_links:Array[Dictionary] = links()
	while !_queue.is_empty():
		var _key:String = _queue.pop_front()
		for _link:Dictionary in _all_links:
			if _link.from == _key && _rooms.has(_link.to) && !_depth.has(_link.to):
				_depth[_link.to] = _depth[_key] + 1
				_queue.append(_link.to)
	var _max:int = 0
	for _key:String in _depth:
		_max = maxi(_max, _depth[_key])
	var _rows:Dictionary = {}
	for _key:String in _rooms:
		var _column:int = _depth.get(_key, _max + 1)
		var _row:int = _rows.get(_column, 0)
		_rows[_column] = _row + 1
		_campaign.nodes[_key] = [_column * spacing.x, _row * spacing.y]
