## One mod folder: user://mods/<id>/mod.json plus layouts/room_<key>.json. Plain data
## only (see LayoutCodec); share a mod by copying its folder.
##   mod.json: {id, name, author, version, description,
##              campaigns: [{id, display_name, start, nodes: {key: [x, y]}}]}
class_name MapModInfo
extends RefCounted

var id:String
var dir:String
var name:String
var author:String
var version:String = "1"
var description:String
## Campaign dicts (see the header); MapCampaign.from_dict reads them.
var campaigns:Array = []

static func load_dir(path:String)->MapModInfo:
	var _id:String = path.trim_suffix("/").get_file()
	if !LayoutCodec.valid_key(_id):
		return null
	var _info:MapModInfo = MapModInfo.new()
	_info.id = _id
	_info.dir = path
	_info.name = _id
	var _file:String = path.path_join("mod.json")
	if FileAccess.file_exists(_file):
		var _data:Variant = JSON.parse_string(FileAccess.get_file_as_string(_file))
		if _data is Dictionary:
			_info.name = str(_data.get("name", _id)).left(60)
			_info.author = str(_data.get("author", "")).left(60)
			_info.version = str(_data.get("version", "1")).left(20)
			_info.description = str(_data.get("description", "")).left(500)
			var _campaigns:Variant = _data.get("campaigns", [])
			_info.campaigns = _campaigns if _campaigns is Array else []
	return _info

func layouts_dir()->String:
	return dir.path_join("layouts")

func layout_file(key:String)->String:
	return layouts_dir().path_join("room_%s.json" % key)

func keys()->PackedStringArray:
	var _keys:PackedStringArray = []
	for _file:String in DirAccess.get_files_at(layouts_dir()):
		if _file.begins_with("room_") && _file.ends_with(".json"):
			_keys.append(_file.trim_prefix("room_").trim_suffix(".json"))
	_keys.sort()
	return _keys

func has_room(key:String)->bool:
	return FileAccess.file_exists(layout_file(key))

func save()->Error:
	DirAccess.make_dir_recursive_absolute(layouts_dir())
	var _file:FileAccess = FileAccess.open(dir.path_join("mod.json"), FileAccess.WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	_file.store_string(JSON.stringify({
		"id": id, "name": name, "author": author, "version": version,
		"description": description, "campaigns": campaigns,
	}, "\t"))
	_file.close()
	return OK
