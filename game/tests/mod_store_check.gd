## Mods: every built-in layout survives the JSON codec unchanged (and bakes the same
## scene), a mod overrides a built-in room and adds a new one (baked into its cache,
## resolved by scene path, balance entries registered), unchanged rooms aren't rebaked,
## and hostile JSON (bad keys, unknown items, quote/newline injection) is cleaned.
##   Godot --headless --path . res://game/tests/mod_store_check.tscn
extends Node

const BAKER:String = "res://game/resources/map_creator/layout_baker.tres"
const MODS:String = "res://addons/map_creator/resources/settings/mod_state.tres"
const OUT:String = "user://mod_store_check/out/"

var failures:int = 0
var checks:int = 0

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	var _baker:GameLayoutBaker = load(BAKER)
	var _mods:MapModState = load(MODS)
	_mods.mods_dir = "user://mod_store_check/mods/"
	_mods.cache_dir = "user://mod_store_check/cache/"
	_wipe("user://mod_store_check/")
	DirAccess.make_dir_recursive_absolute(OUT)
	_baker.quiet = true
	_check_codec(_baker)
	_check_mod(_baker, _mods)
	_check_hostile(_baker)
	_mods.deactivate(_baker)
	_baker.quiet = false
	print("mod_store_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _check_codec(baker:GameLayoutBaker)->void:
	baker.write_dir = OUT
	baker.reset_problems()
	var _layouts:Dictionary = baker.load_layouts()
	var _codec:LayoutCodec = LayoutCodec.new()
	for _key:String in _layouts:
		var _json:String = LayoutCodec.to_json(_layouts[_key])
		var _back:RoomLayoutResource = _codec.from_json(_json, baker.catalog)
		check(_back != null && _codec.warnings.is_empty(), "room_%s decodes cleanly %s" % [_key, _codec.warnings])
		if _back == null:
			continue
		check(LayoutCodec.to_json(_back) == _json, "room_%s JSON roundtrip is lossless" % _key)
		baker.bake(_back)
		check(FileAccess.get_file_as_string(OUT + "room_%s.tscn" % _key) == FileAccess.get_file_as_string(baker.scene_path(_key)), "room_%s from JSON bakes the committed scene" % _key)
	baker.write_dir = ""
	baker.take_entries()
	check(baker.problems == 0, "codec bakes: no problems (%d)" % baker.problems)

func _check_mod(baker:GameLayoutBaker, mods:MapModState)->void:
	baker.load_layouts()
	var _info:MapModInfo = mods.create_mod("testmod", "Test mod")
	check(_info != null && mods.scan().has("testmod"), "mod created and scanned")
	check(mods.create_mod("../evil") == null, "bad mod id refused")
	var _override:RoomLayoutResource = baker.layouts["N02"].clone()
	_override.display_name = "Modded N02"
	check(mods.write_layout(_info, _override) == OK, "override written")
	var _new:RoomLayoutResource = RoomLayoutResource.new()
	_new.key = "Z01"
	_new.display_name = "Mod room"
	for _x:int in 12:
		for _y:int in 12:
			_new.floor[Vector2i(_x, _y)] = Vector3i(1, 0, 3)
	_new.entities.append(LayoutEntity.make(&"player_spawn", Vector2i(3, 3)))
	_new.entities.append(LayoutEntity.make(&"spawn", Vector2i(8, 8), {"section": 1}))
	_new.entities.append(LayoutEntity.make(&"trigger", Vector2i(5, 5), {"section": 1}))
	_new.sections.append({"waves": [{"count": 2, "enemies": ["zombie"]}]})
	check(mods.write_layout(_info, _new) == OK, "new room written")

	check(mods.activate("testmod", baker), "mod activated")
	var _n02:String = mods.cache_scene("testmod", "N02")
	var _z01:String = mods.cache_scene("testmod", "Z01")
	check(mods.resolve("res://game/scenes/room_N02.tscn") == _n02, "override resolves to the mod cache")
	check(mods.resolve("res://game/scenes/room_N01.tscn") == "res://game/scenes/room_N01.tscn", "other rooms stay built-in")
	check(mods.scene_for("Z01") == _z01 && FileAccess.file_exists(_z01), "new room baked into the cache")
	check(baker.layouts.has("Z01") && baker.layouts["N02"].display_name == "Modded N02", "baker sees the mod's layouts")
	var _scene:PackedScene = ResourceLoader.load(_z01, "", ResourceLoader.CACHE_MODE_REPLACE)
	var _room:Node = _scene.instantiate() if _scene != null else null
	check(_room != null && _room.get_node_or_null("PlayerSpawner") != null, "baked mod room loads")
	if _room != null:
		_room.free()
	check(!FileAccess.get_file_as_string(_z01).get_slice("\n", 0).contains("uid="), "mod scene has no uid of its own")
	check(!Balance.entry_for_scene(_z01).is_empty(), "mod room balance entry registered")
	var _stamp:int = FileAccess.get_modified_time(_n02)
	mods.ensure_baked(_info, baker)
	check(FileAccess.get_modified_time(_n02) == _stamp, "unchanged rooms aren't rebaked")
	var _transition:Node = get_node_or_null(^"/root/Transition")
	check(_transition != null && _transition.call(&"resolve", "res://game/scenes/room_N02.tscn") == _n02, "Transition resolves through the mod")
	mods.delete_layout(_info, "Z01")
	check(mods.scene_for("Z01") == "res://game/scenes/room_Z01.tscn", "deleted mod room no longer resolves")
	check(Balance.entry_for_scene(_z01).is_empty(), "deleted room's balance entry dropped")
	mods.deactivate(baker)
	check(mods.resolve("res://game/scenes/room_N02.tscn") == "res://game/scenes/room_N02.tscn", "deactivated: built-in again")
	check(baker.layouts["N02"].display_name != "Modded N02", "deactivated: baker back to built-in layouts")

func _check_hostile(baker:GameLayoutBaker)->void:
	var _codec:LayoutCodec = LayoutCodec.new()
	check(_codec.from_dict({"key": "../x"}, baker.catalog) == null, "bad key refused")
	check(_codec.from_dict([1, 2], baker.catalog) == null, "non-dict refused")
	var _layout:RoomLayoutResource = _codec.from_dict({
		"key": "H1", "display_name": "a\"\nscript = 1",
		"floor": [[0, 0, 1, 0, 3], [9999, 0, 1, 0, 3], [1, {"x": 1}, 1, 0, 3]],
		"sections": [{"waves": [{"count": "3", "enemies": ["zom\"bie"], "evil": 1}], "hack": 2}],
		"entities": [
			{"item": "evil_thing", "cell": [0, 0]},
			{"item": "door", "cell": [0, 0], "props": {"tag": "a\"\n[node name=\"X\"]", "room": "room_N01", "script": "x"}},
		],
	}, baker.catalog)
	check(_layout != null, "hostile layout still decodes")
	if _layout == null:
		return
	check(!_layout.display_name.contains("\"") && !_layout.display_name.contains("\n"), "name cleaned")
	check(_layout.floor.size() == 2 && !_layout.floor.has(Vector2i(9999, 0)), "out of bounds cell dropped")
	check(_layout.entities.size() == 1, "unknown item dropped")
	var _tag:String = _layout.entities[0].props.get("tag", "") if !_layout.entities.is_empty() else ""
	check(!_tag.contains("\"") && !_tag.contains("\n") && !_tag.contains("["), "tag cleaned (%s)" % _tag)
	check(_layout.entities.is_empty() || !_layout.entities[0].props.has("script"), "unknown prop dropped")
	check(_layout.sections[0].waves[0].count == 3 && !_layout.sections[0].has("hack") && !_layout.sections[0].waves[0].has("evil"), "section keys cleaned")
	check(!_codec.warnings.is_empty(), "warnings reported")

func _wipe(dir:String)->void:
	if !DirAccess.dir_exists_absolute(dir):
		return
	for _sub:String in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(_sub))
	for _file:String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(_file))
	DirAccess.remove_absolute(dir)
