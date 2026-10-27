## Lobs a projectile at the target's position when it is in range, with a cooldown.
## Projectile uses lerp movement (destination), like BigJellyShootSlime.
class_name EnemyLob
extends Node

@export var target_finder:TargetFinder

@export var origin_node:Node2D

@export var projectile_instance:InstanceResource

@export var shoot_range:float = 96.0

@export var cooldown:float = 2.5

## Delay before the first shot after spawning
@export var start_delay:float = 1.0

## Degrees added to the aim, one projectile per angle (fan)
@export var angles:Array[float] = [0.0]

@export var shoot_sound:SoundResource

var next_shot_time:float

func _enter_tree()->void:
	next_shot_time = _time() + start_delay

func _ready()->void:
	target_finder.target_update.connect(_on_target_update)

func _time()->float:
	return Time.get_ticks_msec() * 0.001

func _on_target_update()->void:
	if target_finder.target_count < 1:
		return
	if _time() < next_shot_time:
		return
	var _target_position:Vector2 = target_finder.closest.global_position
	if origin_node.global_position.distance_to(_target_position) > shoot_range:
		return
	next_shot_time = _time() + cooldown
	shoot(_target_position)

func shoot(target_position:Vector2)->void:
	var _origin:Vector2 = origin_node.global_position
	var _offset:Vector2 = target_position - _origin

	for _degree:float in angles:
		var _destination:Vector2 = _origin + _offset.rotated(deg_to_rad(_degree))
		var _config_callback:Callable = func (inst:Projectile2D)->void:
			inst.global_position = _origin
			inst.destination = _destination
			inst.direction = _offset.normalized()
		projectile_instance.instance(_config_callback)

	if shoot_sound != null:
		shoot_sound.play_managed()
