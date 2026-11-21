## Mods and the active one (shared resource). A mod's rooms are JSON layouts, baked
## locally into cache_dir/<mod>/room_<key>.tscn; while the mod is active every scene
## load of canonical_dir/room_<key>.tscn resolves to the mod's baked room when it has
## one (overrides and new rooms alike). Rebakes when a layout or the game version changes.
class_name MapModState
extends Resource

signal mods_changed

@export_dir var mods_dir:String = "user://mods/"
@export_dir var cache_dir:String = "user://map_creator/cache/"
## Where built-in rooms live; baked doors and portals always link here.
@export_dir var canonical_dir:String = "res://game/scenes/"
## Cache file of the mod rooms' maps.json "rooms" entries.
const MAPS_FILE:String = "maps.json"
## Autoload given the mod rooms' room entries (register_rooms / clear_registered).
@export var balance_node:NodePath = ^"/root/Balance"

## Active mod id ("" = the base game).
var active:String
## Room keys the active mod has.
var _active_keys:PackedStringArray = []
var _problems:PackedStringArray = []

func is_active()->bool:
	return !active.is_empty()

## Mod id -> MapModInfo for every folder in mods_dir.
func scan()->Dictionary:
	var _mods:Dictionary = {}
	for _dir:String in DirAccess.get_directories_at(mods_dir):
		var _info:MapModInfo = MapModInfo.load_dir(mods_dir.path_join(_dir))
		if _info != null:
			_mods[_info.id] = _info
	return _mods

func mod(id:String)->MapModInfo:
	if id.is_empty() || !DirAccess.dir_exists_absolute(mods_dir.path_join(id)):
		return null
	return MapModInfo.load_dir(mods_dir.path_join(id))

func active_mod()->MapModInfo:
	return mod(active)

func create_mod(id:String, display_name:String = "")->MapModInfo:
	if !LayoutCodec.valid_key(id) || DirAccess.dir_exists_absolute(mods_dir.path_join(id)):
		return null
	var _info:MapModInfo = MapModInfo.new()
	_info.id = id
	_info.dir = mods_dir.path_join(id)
	_info.name = display_name if !display_name.is_empty() else id
	return _info if _info.save() == OK else null

func mods_folder()->String:
	DirAccess.make_dir_recursive_absolute(mods_dir)
	return ProjectSettings.globalize_path(mods_dir)

# --- scene paths ------------------------------------------------------------------------

func cache_folder(id:String)->String:
	return cache_dir.path_join(id)

func cache_scene(id:String, key:String)->String:
	return cache_folder(id).path_join("room_%s.tscn" % key)

func canonical_scene(key:String)->String:
	return canonical_dir.path_join("room_%s.tscn" % key)

## The scene actually loaded for `path` (see the header).
func resolve(path:String)->String:
	if active.is_empty() || !path.begins_with(canonical_dir):
		return path
	var _key:String = path.get_file().get_basename().trim_prefix("room_")
	return cache_scene(active, _key) if _active_keys.has(_key) else path

## The room scene a key loads right now.
func scene_for(key:String)->String:
	return resolve(canonical_scene(key))

# --- layouts ----------------------------------------------------------------------------

func read_layout(info:MapModInfo, key:String, catalog:MapCatalog)->RoomLayoutResource:
	if !info.has_room(key):
		return null
	var _codec:LayoutCodec = LayoutCodec.new()
	var _layout:RoomLayoutResource = _codec.from_json(FileAccess.get_file_as_string(info.layout_file(key)), catalog)
	for _warning:String in _codec.warnings:
		_problems.append("%s/%s: %s" % [info.id, key, _warning])
	if _layout != null && _layout.key != key:
		_layout.key = key
	return _layout

func read_layouts(info:MapModInfo, catalog:MapCatalog)->Dictionary:
	var _layouts:Dictionary = {}
	for _key:String in info.keys():
		var _layout:RoomLayoutResource = read_layout(info, _key, catalog)
		if _layout != null:
			_layouts[_key] = _layout
	return _layouts

func write_layout(info:MapModInfo, layout:RoomLayoutResource)->Error:
	DirAccess.make_dir_recursive_absolute(info.layouts_dir())
	var _file:FileAccess = FileAccess.open(info.layout_file(layout.key), FileAccess.WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	_file.store_string(LayoutCodec.to_json(layout))
	_file.close()
	if info.id == active && !_active_keys.has(layout.key):
		_active_keys.append(layout.key)
	return OK

## Removes a mod's room (an override falls back to the built-in room).
func delete_layout(info:MapModInfo, key:String)->void:
	DirAccess.remove_absolute(info.layout_file(key))
	DirAccess.remove_absolute(cache_scene(info.id, key))
	var _balance:Dictionary = _read_json(cache_folder(info.id).path_join(MAPS_FILE))
	_balance.erase("room_" + key)
	_write_json(cache_folder(info.id).path_join(MAPS_FILE), _balance)
	if info.id == active:
		var _at:int = _active_keys.find(key)
		if _at != -1:
			_active_keys.remove_at(_at)
		_register_balance(_balance)

## Problems (codec warnings) since the last call.
func take_problems()->PackedStringArray:
	var _taken:PackedStringArray = _problems.duplicate()
	_problems.clear()
	return _taken

# --- activation and baking --------------------------------------------------------------

## Makes `id` the active mod ("" = none): layouts merged into the baker (built-in, then
## the mod's), stale rooms baked, balance entries registered. Returns false if missing.
func activate(id:String, baker:LayoutBaker)->bool:
	var _info:MapModInfo = mod(id)
	if !id.is_empty() && _info == null:
		return false
	active = id
	_active_keys = _info.keys() if _info != null else PackedStringArray()
	if baker != null:
		baker.load_layouts()
		if _info != null:
			baker.layouts.merge(read_layouts(_info, baker.catalog), true)
			ensure_baked(_info, baker)
	if _info == null:
		_clear_balance()
	mods_changed.emit()
	return true

func deactivate(baker:LayoutBaker = null)->void:
	if active.is_empty():
		return
	activate("", baker)

## Bakes every room of `info` whose layout (or the game version) changed.
func ensure_baked(info:MapModInfo, baker:LayoutBaker)->void:
	var _hashes:Dictionary = _read_json(cache_folder(info.id).path_join("hashes.json"))
	var _balance:Dictionary = _read_json(cache_folder(info.id).path_join(MAPS_FILE))
	if !FileAccess.file_exists(cache_folder(info.id).path_join(MAPS_FILE)):
		_hashes.clear() # older cache (room entries were in balance.json): rebake all
	var _keys:PackedStringArray = info.keys()
	for _key:String in _hashes.keys():
		if !_keys.has(_key):
			_hashes.erase(_key)
			_balance.erase("room_" + _key)
	for _key:String in _keys:
		var _hash:String = _layout_hash(info, _key)
		if _hashes.get(_key, "") == _hash && FileAccess.file_exists(cache_scene(info.id, _key)):
			continue
		var _layout:RoomLayoutResource = baker.layouts.get(_key, null)
		if _layout == null:
			_layout = read_layout(info, _key, baker.catalog)
		if _layout == null:
			continue
		if _bake_into(info, _layout, baker, _balance):
			_hashes[_key] = _hash
	_write_json(cache_folder(info.id).path_join("hashes.json"), _hashes)
	_write_json(cache_folder(info.id).path_join(MAPS_FILE), _balance)
	if info.id == active:
		_register_balance(_balance)

## Bakes one (just saved) mod room now; returns the bake context ({} on failure).
func bake_room(info:MapModInfo, layout:RoomLayoutResource, baker:LayoutBaker)->Dictionary:
	var _balance:Dictionary = _read_json(cache_folder(info.id).path_join(MAPS_FILE))
	var _hashes:Dictionary = _read_json(cache_folder(info.id).path_join("hashes.json"))
	var _ctx:Dictionary = _bake(info, layout, baker, _balance)
	if !_ctx.is_empty():
		_hashes[layout.key] = _layout_hash(info, layout.key)
	_write_json(cache_folder(info.id).path_join("hashes.json"), _hashes)
	_write_json(cache_folder(info.id).path_join(MAPS_FILE), _balance)
	if info.id == active:
		_register_balance(_balance)
	return _ctx

func _bake_into(info:MapModInfo, layout:RoomLayoutResource, baker:LayoutBaker, balance:Dictionary)->bool:
	return !_bake(info, layout, baker, balance).is_empty()

func _bake(info:MapModInfo, layout:RoomLayoutResource, baker:LayoutBaker, balance:Dictionary)->Dictionary:
	DirAccess.make_dir_recursive_absolute(cache_folder(info.id))
	var _ctx:Dictionary = baker.bake(layout, cache_folder(info.id))
	if baker.has_method(&"take_entries"):
		var _entries:Dictionary = baker.call(&"take_entries")
		balance.erase("room_" + layout.key)
		balance.merge(_entries, true)
	var _path:String = cache_scene(info.id, layout.key)
	if !_ctx.is_empty() && ResourceLoader.has_cached(_path):
		ResourceLoader.load(_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	return _ctx

func _layout_hash(info:MapModInfo, key:String)->String:
	var _text:String = FileAccess.get_file_as_string(info.layout_file(key))
	return "%d:%s" % [_text.hash(), ProjectSettings.get_setting("application/config/version", "")]

func _balance_node()->Node:
	var _tree:SceneTree = Engine.get_main_loop() as SceneTree
	return _tree.root.get_node_or_null(balance_node) if _tree != null else null

func _register_balance(entries:Dictionary)->void:
	var _node:Node = _balance_node()
	if _node != null && _node.has_method(&"register_rooms"):
		_node.call(&"clear_registered")
		_node.call(&"register_rooms", entries)

func _clear_balance()->void:
	var _node:Node = _balance_node()
	if _node != null && _node.has_method(&"clear_registered"):
		_node.call(&"clear_registered")

static func _read_json(path:String)->Dictionary:
	if !FileAccess.file_exists(path):
		return {}
	var _data:Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _data if _data is Dictionary else {}

static func _write_json(path:String, data:Dictionary)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var _file:FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if _file != null:
		_file.store_string(JSON.stringify(data, "\t"))
		_file.close()
