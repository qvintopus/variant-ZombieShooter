## Ground slam for a boss that walks like a regular enemy.
## Every cycle_time seconds it slams when the player is close, otherwise it summons.
## It never turns off its own hitbox, so it can be damaged the whole time.
class_name BossSlam
extends Node

## Emitted when the windup starts, so the animation can show the swing
signal slammed

@export var player_reference:ReferenceNodeResource

@export var character_body:CharacterBody2D

@export var damage_transmitter:ShapeCastTransmitter2D

@export var push_transmitter:ShapeCastTransmitter2D

@export var summon:BossSummon

## Player closer than this gets slammed, further away gets summons
@export var slam_range:float = 40.0

## Seconds between each action
@export var cycle_time:float = 2.5

## Seconds of windup before the slam hits
@export var windup_time:float = 0.35

var is_running:bool

func _ready()->void:
	player_reference.listen(self, _on_player_changed)

func _on_player_changed()->void:
	if player_reference.node == null || is_running:
		return
	is_running = true
	_cycle.call_deferred()

func _cycle()->void:
	if player_reference.node == null:
		is_running = false
		return

	var _target:Vector2 = player_reference.node.global_position
	if character_body.global_position.distance_to(_target) <= slam_range:
		_slam()
	else:
		summon.shoot(_target)

	var _tween:Tween = create_tween()
	_tween.tween_callback(_cycle).set_delay(cycle_time)

func _slam()->void:
	slammed.emit()
	var _tween:Tween = create_tween()
	_tween.tween_callback(_strike).set_delay(windup_time)

func _strike()->void:
	damage_transmitter.check_transmission()
	push_transmitter.check_transmission()
