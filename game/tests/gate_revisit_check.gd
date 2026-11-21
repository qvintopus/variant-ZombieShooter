## Re-entering a cleared room: its exit gates stay open (room_N01). Leaving mid-fight
## (admin room switch) doesn't count as clearing it; a save with the room cleared but
## not its sections opens the gates anyway.
##   Godot --headless --path . res://game/tests/gate_revisit_check.tscn
extends Node

const TD:String = "res://addons/top_down/"

var failures:int = 0
var checks:int = 0

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	var _state:RoomStateResource = load(TD + "resources/global_resources/room_state_resource.tres")
	_state.reset_resource()
	var _room:Node = (load("res://game/scenes/room_N01.tscn") as PackedScene).instantiate()
	add_child(_room)
	await _frames(10)
	(_room.get_node("EnemyManager/Section1") as ArenaSection).try_start()
	await _frames(5)
	remove_child(_room)
	_room.free()
	await _frames(3)
	check(!_state.is_cleared(&"room_N01"), "leaving mid-fight doesn't clear the room")
	_state.reset_resource()
	_state.mark_cleared(&"room_N01")
	await _check_gates("room cleared, sections missing")
	_state.reset_resource()
	_state.mark_cleared(&"room_N01")
	_state.mark_section_cleared(&"room_N01", 0)
	await _check_gates("room and section cleared")
	print("gate_revisit_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _check_gates(label:String)->void:
	var _room:Node = (load("res://game/scenes/room_N01.tscn") as PackedScene).instantiate()
	add_child(_room)
	await _frames(20)
	var _section:ArenaSection = _room.get_node("EnemyManager/Section1")
	check(_section.is_cleared, "%s: section restored cleared" % label)
	for _wall:Node in _room.find_children("*", "BlockWall", true, false):
		for _block:Node in _wall.find_children("*", "ArenaDoorBlock", true, false):
			var _b:ArenaDoorBlock = _block
			check(!_b.is_raised(), "%s: %s lowered" % [label, _wall.name])
	remove_child(_room)
	_room.free()
	await _frames(3)

func _frames(count:int)->void:
	for i:int in count:
		await get_tree().physics_frame
