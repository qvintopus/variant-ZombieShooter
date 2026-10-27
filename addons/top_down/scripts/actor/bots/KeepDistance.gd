## Ranged bots: stop when closer than stop_distance, back off when closer than back_off_distance.
## Must be connected to target_update after TargetDirection, so it overrides the chase axis.
class_name KeepDistance
extends Node

@export var target_finder:TargetFinder

@export var bot_input:BotInput

@export var stop_distance:float = 56.0

@export var back_off_distance:float = 32.0

func _ready()->void:
	target_finder.target_update.connect(_on_target_update)

func _on_target_update()->void:
	if target_finder.target_count < 1:
		return
	var _away:Vector2 = bot_input.global_position - target_finder.closest.global_position
	var _distance:float = _away.length()
	if _distance < back_off_distance:
		bot_input.input_resource.set_axis((_away * bot_input.axis_compensation).normalized())
		return
	if _distance < stop_distance:
		bot_input.input_resource.set_axis(Vector2.ZERO)
