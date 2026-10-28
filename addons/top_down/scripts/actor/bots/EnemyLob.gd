## Lobs a projectile at the target's position when it is in range, with a cooldown.
## Projectile uses lerp movement (destination), like BigJellyShootSlime.
class_name EnemyLob
extends Node

@export var target_finder:TargetFinder

## Shoot on its own from target_update; off when an attack controller calls shoot() (BossLob)
@export var auto_fire:bool = true

@export var origin_node:Node2D

@export var projectile_instance:InstanceResource

@export var shoot_range:float = 96.0

@export var cooldown:float = 2.5

## Delay before the first shot after spawning
@export var start_delay:float = 1.0

## Degrees added to the aim, one projectile per angle (fan)
@export var angles:Array[float] = [0.0]

## When above 0, projectiles land this far from origin in the target's direction (rings around the shooter)
@export var fixed_distance:float = 0.0

## Enemies spawned where projectiles land count as this enemy's children (SpawnOnLand reads it)
@export var active_enemy:ActiveEnemy

@export var axis_multiplication:Vector2Resource

@export var shoot_sound:SoundResource

var next_shot_time:float

func _enter_tree()->void:
	next_shot_time = _time() + start_delay

func _ready()->void:
	if auto_fire:
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

## max_count limits projectiles to the first angles, list the center ones first
func shoot(target_position:Vector2, max_count:int = -1)->void:
	var _origin:Vector2 = origin_node.global_position
	var _offset:Vector2 = target_position - _origin
	if fixed_distance > 0.0:
		var _direction:Vector2 = _offset.normalized() if _offset.length_squared() > 0.01 else Vector2.RIGHT
		_offset = _direction * fixed_distance
	var _branch:ActiveEnemyResource = active_enemy.enemy_resource if active_enemy != null else null

	var _count:int = angles.size() if max_count < 0 else mini(max_count, angles.size())
	for i:int in _count:
		var _degree:float = angles[i]
		var _rotated:Vector2 = _offset.rotated(deg_to_rad(_degree))
		if fixed_distance > 0.0 && axis_multiplication != null:
			# keep rings round in the faked top down perspective
			_rotated *= axis_multiplication.value
		var _destination:Vector2 = _origin + _rotated
		var _config_callback:Callable = func (inst:Projectile2D)->void:
			inst.global_position = _origin
			inst.destination = _destination
			inst.direction = _rotated.normalized()
			inst.set_meta(&"enemy_branch", _branch)
		projectile_instance.instance(_config_callback)

	if shoot_sound != null:
		shoot_sound.play_managed()
