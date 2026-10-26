class_name ProximityShoot
extends Node

@export var target_finder:TargetFinder
@export var bot_input:BotInput
@export var projectile_instance:InstanceResource
@export var shoot_sound:SoundResource

## Fires only while the closest target is within this distance
@export var shoot_range:float = 112.0
@export var shoot_cooldown:float = 2.0
## Projectile starts this far from the enemy, towards the target
@export var spawn_distance:float = 8.0

var next_shoot_time:float

func _ready()->void:
	target_finder.target_update.connect(_on_target_update)

func _on_target_update()->void:
	if target_finder.target_count < 1:
		return
	var _target:Node2D = target_finder.closest
	if _target == null:
		return
	var _to_target:Vector2 = _target.global_position - bot_input.global_position
	if _to_target.length() > shoot_range:
		return
	var _now:float = Time.get_ticks_msec() * 0.001
	if _now < next_shoot_time:
		return
	next_shoot_time = _now + shoot_cooldown
	_shoot(_target.global_position)

func _shoot(target_position:Vector2)->void:
	var _direction:Vector2 = (target_position - bot_input.global_position).normalized()
	var _pos:Vector2 = bot_input.global_position + spawn_distance * _direction

	var _config_callback:Callable = func (inst:Projectile2D)->void:
		inst.global_position = _pos
		inst.destination = target_position

	projectile_instance.instance(_config_callback)
	if shoot_sound != null:
		shoot_sound.play_managed()
