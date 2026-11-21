## Map creator room management (RoomManager) in a test baker (user://) and a test mod:
## new, duplicate, rename (links rewritten, balance entry moved), delete, importing the
## hand-made scenes as layouts (the import bakes the same floor), shifting a room, and the
## mod rules (built-in rooms keep their key, deleting a mod copy brings the built-in back).
##   Godot --headless --path . res://game/tests/room_manage_check.tscn
extends Node

const BAKER:String = "res://game/resources/map_creator/layout_baker.tres"
const CREATOR:String = "res://addons/map_creator/scenes/map_creator.tscn"
const OUT:String = "user://room_manage_check/"
const HAND_MADE:Array[String] = ["A01", "A02", "B01", "1", "3", "start"]

var failures:int = 0
var checks:int = 0

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _frames(count:int)->void:
	for _i:int in count:
		await get_tree().process_frame

func _ready()->void:
	(load("res://addons/top_down/resources/global_resources/action_resource.tres") as ActionResource).reset_resource()
	_wipe(OUT)
	var _baker:GameLayoutBaker = _test_baker()
	_baker.quiet = true
	var _creator:MapCreator = _open("N01", _baker)
	await _frames(2)
	_check_project(_creator, _baker)
	_check_original(_creator)
	_check_import(_creator, _baker)
	_check_shift(_creator)
	_check_mod(_creator, _baker)
	_creator.mod_state.deactivate(_baker)
	_creator.room.queue_free()
	await _frames(2)
	print("room_manage_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_baker()->GameLayoutBaker:
	var _source:GameLayoutBaker = load(BAKER)
	var _baker:GameLayoutBaker = _source.duplicate()
	_baker.catalog = _source.catalog
	_baker.layouts_dir = OUT + "layouts/"
	_baker.write_dir = OUT + "scenes/"
	_baker.balance_path = OUT + "balance.json"
	_baker.maps_path = OUT + "maps.json"
	for _dir:String in [_baker.layouts_dir, _baker.write_dir]:
		DirAccess.make_dir_recursive_absolute(_dir)
	for _file:String in DirAccess.get_files_at("res://game/rooms/layouts/"):
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/rooms/layouts/" + _file), ProjectSettings.globalize_path(_baker.layouts_dir + _file))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/balance/balance.json"), ProjectSettings.globalize_path(_baker.balance_path))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/balance/maps.json"), ProjectSettings.globalize_path(_baker.maps_path))
	_baker.load_layouts()
	return _baker

func _open(key:String, baker:LayoutBaker)->MapCreator:
	var _room:Node2D = (load("res://game/scenes/room_%s.tscn" % key) as PackedScene).instantiate()
	var _creator:MapCreator = (load(CREATOR) as PackedScene).instantiate()
	_creator.baker = baker
	_creator.settings = MapCreatorSettings.new()
	_creator.settings.not_saved = true
	_creator.settings.auto_clean = false
	_creator.room = _room
	add_child(_room)
	_room.add_child(_creator)
	return _creator

func _check_project(creator:MapCreator, baker:GameLayoutBaker)->void:
	var _rooms:RoomManager = creator.rooms
	check(!_rooms.new_room("bad key!"), "bad keys refused")
	check(!_rooms.new_room("N02"), "existing keys refused")
	check(_rooms.new_room("T01", "Test room"), "new room")
	check(FileAccess.file_exists(baker.layout_path("T01")) && FileAccess.file_exists(baker.written_path("T01")), "new room: layout + scene written")
	var _t01:RoomLayoutResource = baker.layouts.get("T01", null)
	check(_t01 != null && _t01.floor.size() == RoomManager.NEW_SIZE * RoomManager.NEW_SIZE && _t01.has_item(&"player_spawn"), "new room: floor square + player spawn")
	check(_rooms.duplicate_room("N02", "T02"), "duplicate")
	check(baker.layouts.get("T02") != null && baker.layouts.T02.entities.size() == baker.layouts.N02.entities.size(), "duplicate copies the entities")
	check(baker.layouts.T02.display_name.ends_with(" copy"), "duplicate is named a copy")
	# rename a linked room: every door/portal to it follows
	var _links:int = _rooms.links_to("N02").size()
	check(_links > 0, "N02 is linked from other rooms (%d)" % _links)
	check(_rooms.rename_room("N02", "N02R"), "rename")
	check(!baker.layouts.has("N02") && baker.layouts.has("N02R"), "rename moves the layout")
	check(_rooms.links_to("N02").is_empty() && _rooms.links_to("N02R").size() == _links, "rename rewrites every link")
	check(!FileAccess.file_exists(baker.layout_path("N02")) && !FileAccess.file_exists(baker.written_path("N02")), "rename removes the old files")
	var _balance:String = FileAccess.get_file_as_string(baker.maps_path)
	check(_balance.contains("\"room_N02R\"") && !_balance.contains("\"room_N02\""), "rename moves the maps.json entry")
	check(JSON.parse_string(_balance) is Dictionary, "maps.json stays valid JSON")
	check(!_rooms.delete_room("N01"), "the open room can't be deleted")
	check(_rooms.delete_room("T01") && !baker.layouts.has("T01") && !FileAccess.file_exists(baker.layout_path("T01")), "delete")

## Entering Edit on an original asks to copy it; "Edit original" stops the asking.
func _check_original(creator:MapCreator)->void:
	var _asked:Array = []
	var _on_choice:Callable = func (title:String, initial:String, answer:Callable, alt_label:String, alt_answer:Callable)->void:
		_asked.append([title, initial, answer, alt_label, alt_answer])
	creator.choice_requested.connect(_on_choice)
	check(creator.is_original(), "original: N01 is a built-in room")
	creator.set_editing(false)
	creator.set_editing(true)
	check(_asked.size() == 1 && _asked[0][1] == "N01_01" && _asked[0][3] == "Edit original", "original: Edit asks to copy (%s)" % [_asked])
	if _asked.size() == 1:
		(_asked[0][4] as Callable).call()
	creator.set_editing(false)
	creator.set_editing(true)
	check(_asked.size() == 1, "original: Edit original isn't asked again")
	check(creator.free_key("N01_") == "N01_01" && creator._duplicate("N01", "N01_01") && creator.free_key("N01_") == "N01_02", "original: copy made, next free key")
	var _copy:RoomLayoutResource = creator.baker.layouts.get("N01_01", null)
	check(_copy != null && _copy.user_made && !creator.baker.layouts["N01"].user_made, "original: copy is user_made, source isn't")
	check(_copy != null && LayoutCodec.new().from_dict(LayoutCodec.to_dict(_copy), creator.catalog).user_made, "original: user_made survives JSON")
	creator.dirty = true
	var _prompts:Array = []
	var _on_prompt:Callable = func (title:String, _i:String, _a:Callable)->void: _prompts.append(title)
	creator.prompt_requested.connect(_on_prompt)
	creator.ask_rename("N01")
	check(_prompts.is_empty(), "rename: unsaved room asks to save first")
	creator.dirty = false
	creator.ask_rename("N01")
	creator.ask_duplicate("N01", false)
	check(_prompts.size() == 2, "rename / copy prompts open")
	creator.prompt_requested.disconnect(_on_prompt)
	creator.choice_requested.disconnect(_on_choice)

func _check_import(creator:MapCreator, baker:GameLayoutBaker)->void:
	for _key:String in HAND_MADE:
		var _importer:RoomImporter = RoomImporter.new()
		var _layout:RoomLayoutResource = _importer.import_scene("res://game/scenes/room_%s.tscn" % _key, _key, baker)
		check(_layout != null && _layout.floor.size() > 0, "room_%s imports (%s)" % [_key, _importer.warnings])
		if _layout == null:
			continue
		check(_layout.has_item(&"player_spawn"), "room_%s import has the player spawn" % _key)
		# the import bakes the same floor, holes and walls
		baker.bake(_layout)
		var _baked:Node = (ResourceLoader.load(baker.written_path(_key), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		var _original:Node = (load("res://game/scenes/room_%s.tscn" % _key) as PackedScene).instantiate()
		for _path:String in ["Background/FloorLayer", "Background/ObstacleLayer", "WallLayer_Ysorted"]:
			var _a:Array = _original.get_node(_path).get_used_cells()
			var _b:Array = _baked.get_node(_path).get_used_cells()
			_a.sort()
			_b.sort()
			check(_a == _b, "room_%s import: %s cells match (%d vs %d)" % [_key, _path.get_file(), _a.size(), _b.size()])
		_baked.free()
		_original.free()
	baker.take_entries()
	for _key:String in HAND_MADE:
		baker.layouts.erase(_key)
	check(creator.rooms.import_room("A01") && baker.layouts.has("A01"), "Import adds the layout")
	check(FileAccess.file_exists("res://game/scenes/room_A01.tscn"), "the project's hand-made scene stays")

func _check_shift(creator:MapCreator)->void:
	var _cells:int = creator.layout.floor.size()
	var _spawn:Vector2i = creator.layout.entities_of(&"player_spawn")[0].cell
	var _cell:Vector2i = creator.layout.floor.keys()[0]
	creator.shift_room(Vector2i(2, -1))
	check(creator.layout.floor.size() == _cells && creator.layout.floor.has(_cell + Vector2i(2, -1)), "shift moves the floor")
	check(creator.layout.entities_of(&"player_spawn")[0].cell == _spawn + Vector2i(2, -1), "shift moves the entities")
	creator.undo()
	check(creator.layout.entities_of(&"player_spawn")[0].cell == _spawn, "shift is one undo step")

func _check_mod(creator:MapCreator, baker:GameLayoutBaker)->void:
	var _mods:MapModState = creator.mod_state
	_mods.mods_dir = OUT + "mods/"
	_mods.cache_dir = OUT + "cache/"
	check(creator.create_mod("Manage test", false), "test mod workspace")
	var _rooms:RoomManager = creator.rooms
	check(_rooms.duplicate_room("N10", "T05") && _rooms.in_mod("T05"), "duplicate into the mod")
	check(FileAccess.file_exists(_mods.cache_scene("manage_test", "T05")), "mod duplicate baked into the cache")
	check(!_rooms.rename_room("N10", "T07"), "built-in rooms keep their key in a mod")
	check(_rooms.rename_room("T05", "T06") && _rooms.in_mod("T06") && !_rooms.in_mod("T05"), "rename a mod room")
	check(!_rooms.delete_room("N10"), "nothing to delete of a built-in room")
	var _override:RoomLayoutResource = baker.layouts.N10.clone()
	_override.display_name = "Modded"
	check(_rooms.store(_override) && _rooms.in_mod("N10"), "override stored in the mod")
	check(_rooms.delete_room("N10") && !_rooms.in_mod("N10") && baker.layouts.N10.display_name != "Modded", "deleting the override brings the built-in back")
	check(_rooms.delete_room("T06") && !baker.layouts.has("T06"), "delete a mod room")

func _wipe(dir:String)->void:
	if !DirAccess.dir_exists_absolute(dir):
		return
	for _sub:String in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(_sub))
	for _file:String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(_file))
	DirAccess.remove_absolute(dir)
