## Spawns enemies around the boss as its ActiveEnemy children (destroyed with the boss), up to child_limit alive.
class_name BossSummon
extends BossAttack

@export var instance_resource:InstanceResource

@export var active_enemy:ActiveEnemy

@export var origin_node:Node2D

@export var count:int = 2

## Alive children limit, counts every child branch of the boss
@export var child_limit:int = 4

## Easy difficulty uses easy_count and easy_child_limit instead
@export var difficulty_resource:DifficultyResource

@export var easy_count:int = 1

@export var easy_child_limit:int = 2

@export var spawn_radius:float = 28.0

@export var axis_multiplication:Vector2Resource

## Spawns are kept inside walls on this mask
@export_flags_2d_physics var wall_mask:int = 1

@export var spawn_vfx:InstanceResource

@export var sound:SoundResource

func is_available(time:float, distance:float, health_ratio:float)->bool:
	if active_enemy.enemy_resource == null:
		return false
	if active_enemy.enemy_resource.children.size() >= get_child_limit():
		return false
	return super.is_available(time, distance, health_ratio)

func _is_easy()->bool:
	return difficulty_resource != null && difficulty_resource.is_easy()

func get_count()->int:
	return easy_count if _is_easy() else count

func get_child_limit()->int:
	return easy_child_limit if _is_easy() else child_limit

func perform()->void:
	var _branch:ActiveEnemyResource = active_enemy.enemy_resource
	var _count:int = mini(get_count(), get_child_limit() - _branch.children.size())
	if _count < 1:
		return
	var _start_angle:float = randf() * TAU
	for i:int in _count:
		var _direction:Vector2 = Vector2.from_angle(_start_angle + TAU * i / _count) * axis_multiplication.value
		var _pos:Vector2 = _clear_position(origin_node.global_position, _direction * spawn_radius)
		if spawn_vfx != null:
			spawn_vfx.instance(func (inst:Node2D)->void: inst.global_position = _pos)
		var _config_callback:Callable = func (inst:Node2D)->void:
			inst.global_position = _pos
			ActiveEnemy.insert_child(inst, _branch)
		instance_resource.instance(_config_callback)
	if sound != null:
		sound.play_managed()

## Stop short of a wall between the boss and spawn position
func _clear_position(from:Vector2, offset:Vector2)->Vector2:
	var _query:PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, from + offset, wall_mask)
	var _result:Dictionary = origin_node.get_world_2d().direct_space_state.intersect_ray(_query)
	if _result.is_empty():
		return from + offset
	return _result.position - offset.normalized() * 8.0
