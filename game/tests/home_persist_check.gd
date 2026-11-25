## Home base state survives a crash: every change is on disk right away (no
## clean exit), saves are swapped in atomically with a backup, loot lying in the
## room is kept, a piston write rippling out is saved step by step, and the
## quit portal / meta workbench are in the room.
## Saves go to temp resource names, the user's own save files stay untouched.
##   Godot --headless --path . res://game/tests/home_persist_check.tscn
extends Node

const TD:String = "res://addons/top_down/"
const HOME:String = "res://game/scenes/room_H00.tscn"

var failures:int = 0
var checks:int = 0

var _home:HomeBaseResource
var _inventory:ItemCollectionResource
var _database:ItemCollectionResource
var _player_reference:ReferenceNodeResource
var _room:Node
var _saved_name:String

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	(load(TD + "resources/global_resources/action_resource.tres") as ActionResource).reset_resource()
	_home = load("res://game/resources/home_base_resource.tres")
	_inventory = load(TD + "resources/ItemCollectionResource/weapon_inventory.tres")
	_database = load(TD + "resources/ItemCollectionResource/weapon_database.tres")
	_player_reference = load(TD + "resources/ReferenceNodeResources/player_reference.tres")
	_saved_name = _home.resource_name
	_home.resource_name = _saved_name + "_persist_test"
	_home.delete_resource()
	_home.reset_resource()

	_check_backup()

	_home.reset_resource()
	_home.stash_inventory = PackedStringArray(["Gun"])
	await _load_room(HOME)
	if _player_reference.node == null:
		check(false, "home: player spawned")
		_finish()
		return

	# a dropped weapon is on disk without leaving the room
	var _manager:WeaponManager = _player_reference.node.get_node("WeaponManager")
	_manager.drop_weapon()
	await _frames(3)
	check(_disk_dropped().has("Gun"), "crash: dropped gun already saved")
	check(_disk().stash_inventory.is_empty(), "crash: gun no longer in the saved stash")

	# loot lying around is saved and comes back
	var _base:HomeBase = _room.get_node("HomeBase")
	var _spot:Vector2 = _room.get_node("WaterGunSpot").global_position
	LootItems.spawn("meat", 1, _spot + Vector2(8, 0))
	await _frames(3)
	check(_base.loot_pickups().size() == 1, "loot: meat pickup found")
	var _saved_loot:Array = _disk().dropped_loot
	check(_saved_loot.size() == 1 && _saved_loot[0].get("id") == "meat", "crash: loot already saved")
	_room.queue_free()
	_room = null
	await _frames(3)
	check(_disk().dropped_loot.size() == 1, "leave: loot kept")
	_home.dropped_loot = [{"id": "slime", "pos": _spot + Vector2(-8, 0)}]
	_home.save_resource()
	_home.load_resource(true)
	await _load_room(HOME)
	_base = _room.get_node("HomeBase")
	var _ids:Array = _base.loot_pickups().map(func(e:Dictionary)->String: return e.id)
	check(_ids.has("slime"), "reload: saved loot lies in the room again")

	# a write rippling out is saved as it goes
	var _grid:PistonGrid = _room.get_node("WallLayer_Ysorted/PistonGrid")
	_grid.clear_selection()
	_grid.set_selected(PistonGrid.Axis.ROW, 0, true)
	for _c:int in _grid.size:
		_grid.set_selected(PistonGrid.Axis.COL, _c, true)
	_grid.set_data_value(true)
	_grid.ripple_delay = 0.2
	_grid.write()
	await get_tree().create_timer(0.5).timeout
	check(_grid.writing, "ripple: still writing")
	var _raised:int = 0
	var _disk_pistons:PackedByteArray = _disk().pistons
	for _b:int in _disk_pistons:
		_raised += _b
	check(_raised > 0 && _raised < _grid.size, "crash: part of a rippling write already saved (%d)" % _raised)
	_grid.ripple_delay = 0.0

	# exits built into the room
	check(_first_of(_room, "QuitPortal") is QuitPortal, "room: quit portal")
	var _bench:MetaWorkbench = _first_of(_room, "MetaWorkbench") as MetaWorkbench
	check(_bench != null, "room: meta workbench")
	if _bench != null:
		_bench.open_upgrades()
		await _frames(3)
		var _screen:Node = get_tree().root.find_child("MetaUpgrades", true, false)
		check(_screen != null && get_tree().paused, "workbench: meta tree open over paused room")
		if _screen != null:
			_screen._back()
			await _frames(3)
		check(!get_tree().paused && get_tree().root.find_child("MetaUpgrades", true, false) == null, "workbench: closed, room runs again")
		check(is_instance_valid(_room) && _room.is_inside_tree(), "workbench: still in the home base")
	_finish()

## A broken save file falls back to the previous one
func _check_backup()->void:
	_home.gate = 1
	_home.save_resource()
	_home.gate = 2
	_home.save_resource()
	check(FileAccess.file_exists(_home._side_path("bak")), "backup: previous save kept")
	check(!FileAccess.file_exists(_home._side_path("tmp")), "backup: no temp file left")
	var _file:FileAccess = FileAccess.open(_home.get_save_file_path(), FileAccess.WRITE)
	_file.store_string("[gd_resource type=\"Resource\" scr")
	_file.close()
	_home.load_resource(true)
	check(_home.gate == 1, "backup: broken save loads the backup")
	DirAccess.remove_absolute(_home.get_save_file_path())
	_home.load_resource(true)
	check(_home.gate == 1, "backup: missing save loads the backup")

func _first_of(node:Node, class_id:String)->Node:
	for _child:Node in node.get_children():
		var _script:Script = _child.get_script()
		if _script != null && _script.get_global_name() == class_id:
			return _child
		var _found:Node = _first_of(_child, class_id)
		if _found != null:
			return _found
	return null

func _disk()->HomeBaseResource:
	var _data:HomeBaseResource = ResourceLoader.load(_home.get_save_file_path(), "", ResourceLoader.CACHE_MODE_IGNORE)
	return _data if _data != null else HomeBaseResource.new()

func _disk_dropped()->PackedStringArray:
	var _names:PackedStringArray = []
	for _entry:Dictionary in _disk().dropped:
		_names.append(_entry.get("item", ""))
	return _names

func _load_room(path:String)->void:
	if _room != null:
		_room.queue_free()
		await _frames(3)
	_room = (load(path) as PackedScene).instantiate()
	add_child(_room)
	await _frames(10)

func _finish()->void:
	get_tree().paused = false
	if _room != null:
		_room.queue_free()
		await _frames(3)
	_home.delete_resource()
	_home.resource_name = _saved_name
	print("home_persist_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _frames(count:int)->void:
	for i:int in count:
		await get_tree().process_frame
