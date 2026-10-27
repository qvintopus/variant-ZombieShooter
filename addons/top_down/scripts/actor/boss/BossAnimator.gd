## Plays the boss animations: walk while moving, attack on a jump landing or a slam, and a swing for each shot.
## Every animation returns to idle when it finishes; looping animations never finish.
class_name BossAnimator
extends Node

@export var animation_player:AnimationPlayer

## Optional: jumping bosses walk during the jump and attack on landing
@export var jump_move:JumpMove

## Optional: walking bosses walk while the mover is moving
@export var mover:MoverTopDown2D

## Optional: plays attack when the boss slams the ground
@export var slam:BossSlam

@export var primary_shot:BigJellyShootSlime

@export var secondary_shot:BigJellyShootSlime

@export var jump_animation:StringName = &"walk"

@export var land_animation:StringName = &"attack"

@export var primary_animation:StringName = &"throw"

@export var secondary_animation:StringName = &"fan"

func _ready()->void:
	animation_player.animation_finished.connect(_on_animation_finished)
	if jump_move != null:
		jump_move.jump_started.connect(_play.bind(jump_animation))
		jump_move.jump_finished.connect(_play.bind(land_animation))
	if slam != null:
		slam.slammed.connect(_play.bind(land_animation))
	if primary_shot != null:
		primary_shot.shot.connect(_play.bind(primary_animation))
	if secondary_shot != null:
		secondary_shot.shot.connect(_play.bind(secondary_animation))
	_play(&"idle")

func _physics_process(_delta:float)->void:
	if mover == null:
		return
	# only idle and walk switch with movement, a swing or slam plays to the end first
	var _current:StringName = animation_player.current_animation
	if _current != &"idle" && _current != jump_animation:
		return
	var _target:StringName = jump_animation if mover.velocity.length() > 1.0 else &"idle"
	if _current != _target:
		_play(_target)

func _play(animation_name:StringName)->void:
	if animation_player.has_animation(animation_name):
		animation_player.play(animation_name)

func _on_animation_finished(_animation_name:StringName)->void:
	_play(&"idle")
