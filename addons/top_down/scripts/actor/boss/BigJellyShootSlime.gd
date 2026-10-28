class_name BigJellyShootSlime
extends Node

@export var projectile_instance:InstanceResource

@export var origin_node:Node2D

@export var active_enemy:ActiveEnemy

@export var axis_multiply:Vector2Resource

@export var spawn_radius:float = 32.0

@export var shoot_sound:SoundResource

@export var child_limit:int = 8

## Easy difficulty uses easy_child_limit instead
@export var difficulty_resource:DifficultyResource

@export var easy_child_limit:int = 4

func _ready() -> void:
	BigJellySlimeSpawner.active_enemy_branch = active_enemy.enemy_resource

func get_child_limit()->int:
	if difficulty_resource != null && difficulty_resource.is_easy():
		return easy_child_limit
	return child_limit

## return bool if shooting is performed
func shoot(target_position:Vector2)->bool:
	# TODO: limit spawning too many
	var _child_count:int = active_enemy.enemy_resource.children.size()
	if _child_count > get_child_limit():
		return false
	
	var _direction:Vector2 = (target_position - origin_node.global_position).normalized()
	var _pos:Vector2 = origin_node.global_position + (spawn_radius * _direction * axis_multiply.value)
	
	var _config_callback:Callable = func (inst:Projectile2D)->void:
		inst.global_position = _pos
		inst.destination = target_position
		# WARNING: probability of boss dying while projectile is active
	
	projectile_instance.instance(_config_callback)

	shoot_sound.play_managed()
	return true
