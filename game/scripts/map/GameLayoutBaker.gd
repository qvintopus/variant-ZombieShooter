## Zombie Shooter's room baker: LayoutBaker plus FreshStart / HomeBase, the starting
## weapon, RoomController, the HUD overlay, campaign checks and the balance.json
## "rooms" entries (enemy ids resolve through balance.json too).
class_name GameLayoutBaker
extends LayoutBaker

const TD:String = "res://addons/top_down/"

@export_file("*.json") var balance_path:String = "res://game/balance/balance.json"
## balance.json free_distance of every written section.
@export var free_distance:int = 116

var _balance:Dictionary
## Room key -> balance.json "rooms" entry, written by write_balance().
var _entries:Dictionary = {}

func bake(layout:RoomLayoutResource, target_dir:String = "")->Dictionary:
	var _ctx:Dictionary = super.bake(layout, target_dir)
	if layout.writes_balance && !_ctx.is_empty():
		var _entry:Dictionary = _balance_entry(_ctx.path, layout, _ctx.spawns)
		if !_entry.is_empty():
			_entries[layout.key] = _entry
	return _ctx

## Rules a map can't show: boss fights last, campaign boss rooms get their portal and
## victory exit, and every portal arrives at a portal of the room it leads to.
func _validate(layout:RoomLayoutResource)->void:
	var _key:String = layout.key
	var _portals:Array[LayoutEntity] = layout.entities_of(&"portal")
	if layout.boss_section > 0:
		if layout.boss_section != layout.sections.size():
			problem("%s: the boss section must be the last one" % _key)
		if layout.writes_balance && (!layout.has_item(&"victory") || _portals.is_empty()):
			problem("%s: a boss room needs a portal and a victory exit" % _key)
	if layout.side_room > 0 && layout.side_room != layout.sections.size():
		problem("%s: the side room must be the last section" % _key)
	for _portal:LayoutEntity in _portals:
		var _room:String = _portal.props.get("room", "")
		var _target:RoomLayoutResource = layouts.get(_room.trim_prefix("room_"), null)
		var _tags:Array = []
		if _target != null:
			for _other:LayoutEntity in _target.entities_of(&"portal"):
				_tags.append(_other.props.get("tag", ""))
		if !_tags.has(_portal.props.get("connect_tag", "")):
			problem("%s: portal at %s arrives at '%s', which %s doesn't have" % [_key, _portal.cell, _portal.props.get("connect_tag", ""), _room], _portal.cell)

func _bake_extras(out:SceneText, layout:RoomLayoutResource, ctx:Dictionary)->void:
	if layout.start:
		var _run:PackedStringArray = _run_resources(out)
		out.node("FreshStart", ".", {
			"script": out.ext("Script", "res://game/scripts/FreshStart.gd"),
			"player_reference": out.ext("Resource", TD + "resources/ReferenceNodeResources/player_reference.tres"),
			"scene_transition_resource": out.ext("Resource", TD + "resources/global_resources/scene_transition_resource.tres"),
			"campaign_resource": out.ext("Resource", "res://game/resources/campaign_resource.tres"),
			"run_resources": "Array[Resource]([%s])" % ", ".join(_run),
		}, "", "Node")
	if layout.home:
		_write_home_base(out)
	var _weapon_spots:PackedStringArray = ctx.weapon_spots
	if !_weapon_spots.is_empty():
		if !layout.start:
			problem("%s: starting weapons only work in a start room" % layout.key)
		var _spot_paths:PackedStringArray = []
		for _i:int in _weapon_spots.size():
			_spot_paths.append("NodePath(\"WeaponSpot%d\")" % (_i + 1))
		out.node("StartingWeapon", ".", {
			"script": out.ext("Script", TD + "scripts/arena/StartingWeaponSpawner.gd"),
			"exit_nodes": "[%s]" % ", ".join(ctx.door_names),
			"position_nodes": "[%s]" % ", ".join(_spot_paths),
			"weapon_database": out.ext("Resource", TD + "resources/ItemCollectionResource/weapon_database.tres"),
			"weapon_pickup_instance_resource": out.ext("Resource", TD + "resources/InstanceResources/pickups/item_pickup_instance_resource.tres"),
			"scene_transition_resource": out.ext("Resource", TD + "resources/global_resources/scene_transition_resource.tres"),
		}, "", "Node2D")
		for _i:int in _weapon_spots.size():
			out.node("WeaponSpot%d" % (_i + 1), "StartingWeapon", {"position": _weapon_spots[_i]}, "", "Marker2D")
	out.node("RoomController", ".", {
		"script": out.ext("Script", "res://game/scripts/RoomController.gd"),
		"room_id": "&\"room_%s\"" % layout.key,
		"room_state_resource": out.ext("Resource", TD + "resources/global_resources/room_state_resource.tres"),
		"room_cleared_resource": out.ext("Resource", "res://game/resources/room_cleared_resource.tres"),
		"fight_mode_resource": out.ext("Resource", TD + "resources/arena_resources/fight_mode_resource.tres"),
		"remaining_wave_count_resource": out.ext("Resource", TD + "resources/arena_resources/remaining_wave_count_resource.tres"),
		"arena_entry": "NodePath(\"../ArenaEntry\")",
	}, "", "Node")
	out.node("GameHudOverlay", ".", {}, out.ext("PackedScene", "res://game/scenes/game_hud_overlay.tscn"))

## Run-scoped resources FreshStart and HomeBase reset.
func _run_resources(out:SceneText)->PackedStringArray:
	var _run:PackedStringArray = []
	for _resource:String in ["global_resources/score_resource.tres", "global_resources/meat_resource.tres",
			"global_resources/slime_resource.tres", "global_resources/weapon_upgrade_resource.tres",
			"ItemCollectionResource/weapon_inventory.tres", "global_resources/inventory_grid.tres",
			"global_resources/room_state_resource.tres"]:
		_run.append(out.ext("Resource", TD + "resources/" + _resource))
	return _run

func _write_home_base(out:SceneText)->void:
	out.node("HomeBase", ".", {
		"script": out.ext("Script", "res://game/scripts/home/HomeBase.gd"),
		"player_reference": out.ext("Resource", TD + "resources/ReferenceNodeResources/player_reference.tres"),
		"scene_transition_resource": out.ext("Resource", TD + "resources/global_resources/scene_transition_resource.tres"),
		"run_resources": "Array[Resource]([%s])" % ", ".join(_run_resources(out)),
		"home_base_resource": out.ext("Resource", "res://game/resources/home_base_resource.tres"),
		"weapon_inventory": out.ext("Resource", TD + "resources/ItemCollectionResource/weapon_inventory.tres"),
		"weapon_database": out.ext("Resource", TD + "resources/ItemCollectionResource/weapon_database.tres"),
		"item_pickup_instance_resource": out.ext("Resource", TD + "resources/InstanceResources/pickups/item_pickup_instance_resource.tres"),
		"water_gun_spot": "NodePath(\"../WaterGunSpot\")",
		"piston_grid": "NodePath(\"../WallLayer_Ysorted/PistonGrid\")",
	}, "", "Node")

func _enemy_instance_path(id:String)->String:
	var _data:Dictionary = balance()
	for _category:String in ["enemies", "bosses"]:
		if _data[_category].has(id):
			return _data[_category][id].instance
	problem("unknown enemy id '%s'" % id)
	return ""

func balance()->Dictionary:
	if _balance.is_empty():
		var _parsed:Variant = JSON.parse_string(FileAccess.get_file_as_string(balance_path)) if FileAccess.file_exists(balance_path) else null
		_balance = _parsed if _parsed is Dictionary else {}
	return _balance

## The balance.json "rooms" entry matching what was written into the scene.
func _balance_entry(path:String, layout:RoomLayoutResource, spawns:Dictionary)->Dictionary:
	if layout.sections.is_empty():
		return {}
	var _sections:Dictionary = {}
	for _i:int in layout.sections.size():
		var _spec:Dictionary = layout.sections[_i]
		var _waves:Array = []
		for _wave_spec:Dictionary in _spec.waves:
			var _wave:Dictionary = {"count": _wave_spec.count}
			if _wave_spec.get("is_boss", false):
				_wave.is_boss = true
				_wave.display_name = _wave_spec.display_name
			_wave.enemies = _wave_spec.enemies
			if _wave_spec.has("max_alive"):
				_wave.max_alive = _wave_spec.max_alive
			_waves.append(_wave)
		_sections["Section%d" % (_i + 1)] = {"spawn_density": _spec.get("spawn_density", 1), "free_distance": free_distance, "waves": _waves}
	var _points:Dictionary = {}
	var _names:Array = spawns.keys()
	_names.sort()
	for _name:String in _names:
		_points[_name] = {"max_simultaneous": spawns[_name].max_simultaneous}
	return {"scene": path, "sections": _sections, "spawn_points": _points, "loot_multiplier": 1.0}

## The balance "rooms" entries baked since the last write/take, keyed room_<key>
## (a mod keeps them next to its cached scenes instead of in balance.json).
func take_entries()->Dictionary:
	var _taken:Dictionary = {}
	for _key:String in _entries:
		_taken["room_" + _key] = _entries[_key]
	_entries.clear()
	return _taken

## Replaces (or appends) only the baked rooms' entries in balance.json, keeping the
## rest of the file as it is written.
func write_balance()->void:
	if _entries.is_empty():
		return
	var _lines:PackedStringArray = FileAccess.get_file_as_string(balance_path).split("\n")
	var _rooms_at:int = _lines.find("\t\"rooms\": {")
	if _rooms_at == -1:
		problem("balance.json has no \"rooms\" block")
		return
	for _key:String in _entries:
		var _start:int = _lines.find("\t\t\"room_%s\": {" % _key)
		if _start != -1:
			var _end:int = _start
			while _lines[_end] != "\t\t}" && _lines[_end] != "\t\t},":
				_end += 1
			for i:int in _end - _start + 1:
				_lines.remove_at(_start)
		var _close:int = _block_close(_lines, _rooms_at)
		_lines[_close - 1] = _lines[_close - 1].trim_suffix(",") + ","
		_lines.insert(_close, "\t\t\"room_%s\": %s" % [_key, JSON.stringify(_entries[_key], "\t", false).replace("\n", "\n\t\t")])
	var _last:int = _block_close(_lines, _rooms_at) - 1
	_lines[_last] = _lines[_last].trim_suffix(",")
	var _file:FileAccess = FileAccess.open(balance_path, FileAccess.WRITE)
	_file.store_string("\n".join(_lines))
	_file.close()
	_entries.clear()
	_balance = {}

## Drops room_<key>'s entry from balance.json (a deleted room).
func remove_balance(key:String)->void:
	_entries.erase(key)
	var _lines:PackedStringArray = FileAccess.get_file_as_string(balance_path).split("\n")
	var _start:int = _lines.find("\t\t\"room_%s\": {" % key)
	var _rooms_at:int = _lines.find("\t\"rooms\": {")
	if _start == -1 || _rooms_at == -1:
		return
	var _end:int = _start
	while _lines[_end] != "\t\t}" && _lines[_end] != "\t\t},":
		_end += 1
	for i:int in _end - _start + 1:
		_lines.remove_at(_start)
	var _last:int = _block_close(_lines, _rooms_at) - 1
	_lines[_last] = _lines[_last].trim_suffix(",")
	var _file:FileAccess = FileAccess.open(balance_path, FileAccess.WRITE)
	_file.store_string("\n".join(_lines))
	_file.close()
	_balance = {}

## Line of the "}" closing the top-level block that opens at `start`.
func _block_close(lines:PackedStringArray, start:int)->int:
	var _close:int = start + 1
	while lines[_close] != "\t}," && lines[_close] != "\t}":
		_close += 1
	return _close
