## Bakes every room layout (game/rooms/layouts/room_*.tres, see RoomLayoutResource for
## the cells, entities and sections) into game/scenes/room_<key>.tscn through the shared
## GameLayoutBaker, and rewrites the campaign rooms' balance.json "rooms" entries.
## The in-game map creator saves layouts and bakes the same way; run this after editing
## a layout in the Godot inspector or after changing the baker/catalog.
##   Godot --headless --path . res://game/tools/build_rooms.tscn [-- N02 P10 ...]
extends Node

const BAKER:String = "res://game/resources/map_creator/layout_baker.tres"

func _ready()->void:
	var _baker:GameLayoutBaker = load(BAKER)
	_baker.problems = 0
	var _layouts:Dictionary = _baker.load_layouts()
	var _only:PackedStringArray = OS.get_cmdline_user_args()
	for _key:String in _layouts:
		if !_only.is_empty() && !_only.has(_key):
			continue
		_baker.bake(_layouts[_key])
	_baker.write_balance()
	print("build_rooms: done, %d problems" % _baker.problems)
	get_tree().quit(1 if _baker.problems > 0 else 0)
