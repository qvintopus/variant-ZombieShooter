## Plays the boss animations: walk while jumping, attack on landing, and a swing for each attack.
## Every animation returns to idle when it finishes; looping animations never finish.
class_name BossAnimator
extends Node

@export var animation_player:AnimationPlayer

@export var jump_move:JumpMove

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
	if primary_shot != null:
		primary_shot.shot.connect(_play.bind(primary_animation))
	if secondary_shot != null:
		secondary_shot.shot.connect(_play.bind(secondary_animation))
	_play(&"idle")

func _play(animation_name:StringName)->void:
	if animation_player.has_animation(animation_name):
		animation_player.play(animation_name)

func _on_animation_finished(_animation_name:StringName)->void:
	_play(&"idle")
