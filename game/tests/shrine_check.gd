## Healing shrines + camera punch, headless on room_N10 (1-use shrine in the side vault).
##   Godot --headless --path . res://game/tests/shrine_check.tscn
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
	var _actions:ActionResource = load(TD + "resources/global_resources/action_resource.tres")
	_actions.reset_resource()
	var _state:RoomStateResource = load(TD + "resources/global_resources/room_state_resource.tres")
	_state.reset_resource()

	var _room:Node = (load("res://game/scenes/room_N10.tscn") as PackedScene).instantiate()
	add_child(_room)
	await _frames(10)
	var _player:Node2D = (load(TD + "resources/ReferenceNodeResources/player_reference.tres") as ReferenceNodeResource).node
	check(_player != null, "player spawned")
	var _shrine:Shrine = _room.get_node_or_null("WallLayer_Ysorted/Shrine1")
	check(_shrine != null, "room_N10 has Shrine1")
	if _player == null || _shrine == null:
		_finish()
		return
	var _health:HealthResource = (_player.get_node("ResourceNode") as ResourceNode).get_resource("health")
	_health.hp = _health.max_hp
	var _healed:Array[float] = []
	_shrine.healed.connect(func (amount:float)->void: _healed.append(amount))

	# Shown as tier 1 with one use left
	check(_shrine.max_uses == 1 && _shrine.uses_left() == 1, "1-use shrine starts with 1 use")
	check(_shrine.sprite.frame == 1, "frame: tier 1, 1 left (got %d)" % _shrine.sprite.frame)

	# Refused at full health, no use taken
	await _stand_at(_player, _shrine)
	check(_shrine.prompt_label.visible, "shrine prompt shows in range")
	check(_shrine.prompt_label.text.contains("Full health"), "prompt says full health (got %s)" % _shrine.prompt_label.text)
	await _press_interact()
	check(_shrine.uses_left() == 1 && _healed.is_empty(), "refused at full health")

	# Hurt -> full heal, use spent
	_health.add_hp(-3.0)
	var _hurt:float = _health.hp
	await _press_interact()
	check(_health.is_full(), "healed to full")
	check(_healed.size() == 1 && is_equal_approx(_healed[0], _health.max_hp - _hurt), "healed the missing hp")
	check(_shrine.uses_left() == 0 && _state.shrine_used_count(_shrine.shrine_key()) == 1, "use counted in room state")
	check(_shrine.sprite.frame == 0, "spent frame")
	check(_shrine._prompt_text() == "Spent", "prompt says spent")
	_health.add_hp(-3.0)
	await _press_interact()
	check(!_health.is_full() && _healed.size() == 1, "spent shrine refuses")

	# More uses: tier 3 shows 3 - used
	_shrine.max_uses = 3
	check(_shrine.uses_left() == 2 && _shrine.sprite.frame == 2 * Shrine.FRAMES_PER_TIER + 2, "3-use shrine: 2 left, tier 3 frame")
	await _press_interact()
	check(_health.is_full() && _shrine.uses_left() == 1, "3-use shrine healed again")
	_shrine.max_uses = 1

	# Save / resume keeps the count; a new run clears it
	var _save:RoomProgressComponent = RoomProgressComponent.new()
	_save.capture()
	var _key:String = _shrine.shrine_key()
	_state.reset_resource()
	check(_state.shrine_used_count(_key) == 0, "new run clears shrine uses")
	_save.apply()
	check(_state.shrine_used_count(_key) == 2, "save/resume restores shrine uses (got %d)" % _state.shrine_used_count(_key))

	# Re-entering the room: still spent
	_room.queue_free()
	await _frames(4)
	_room = (load("res://game/scenes/room_N10.tscn") as PackedScene).instantiate()
	add_child(_room)
	await _frames(10)
	_shrine = _room.get_node("WallLayer_Ysorted/Shrine1")
	check(_shrine.uses_left() == 0 && _shrine.sprite.frame == 0, "spent after re-entering the room")

	# Camera punch: zooms + tilts, then back where it was
	var _punch:CameraPunch = _room.get_node_or_null("CameraPunch")
	check(_punch != null, "room has CameraPunch")
	if _punch != null:
		var _camera:Camera2D = _punch._find_camera()
		check(_camera != null && !_camera.ignore_rotation, "camera found, rotation enabled")
		var _zoom:Vector2 = _camera.zoom
		_punch.play(_punch.chest)
		await get_tree().create_timer(_punch.chest.in_time + 0.05).timeout
		check(_camera.zoom.x > _zoom.x * 1.05 && absf(_camera.rotation) > 0.01, "punch zoomed in and tilted")
		_punch.play(_punch.jackpot)
		var _total:float = _punch.jackpot.in_time + _punch.jackpot.hold_time + _punch.jackpot.out_time
		await get_tree().create_timer(_total + 0.1).timeout
		check(_camera.zoom.is_equal_approx(_zoom) && is_zero_approx(_camera.rotation), "retriggered punch returns to base zoom/rotation")
		check(_punch.played == 2, "punch count")
	_state.reset_resource()
	_finish()

func _finish()->void:
	print("shrine_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _frames(count:int)->void:
	for i:int in count:
		await get_tree().physics_frame

func _stand_at(player:Node2D, target:Node2D)->void:
	player.global_position = target.global_position + Vector2(0, 12)
	await _frames(8)

func _press_interact()->void:
	var _event:InputEventAction = InputEventAction.new()
	_event.action = &"interact"
	_event.pressed = true
	Input.parse_input_event(_event)
	await _frames(2)
	_event = InputEventAction.new()
	_event.action = &"interact"
	_event.pressed = false
	Input.parse_input_event(_event)
	await _frames(20)
