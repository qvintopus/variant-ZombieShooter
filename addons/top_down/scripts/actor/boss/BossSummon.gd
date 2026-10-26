## Replaces the slime shot of a boss: summons enemies around the boss instead.
## Extends BigJellyShootSlime so BigJellyAi can use it unchanged.
class_name BossSummon
extends BigJellyShootSlime

## Spawned around the boss on each summon
@export var summon_instance_resource:InstanceResource

@export var summon_count:int = 2

@export var summon_radius:float = 40.0

## return bool if summoning is performed
func shoot(_target_position:Vector2)->bool:
	var _branch:ActiveEnemyResource = active_enemy.enemy_resource
	if _branch.children.size() > child_limit:
		return false

	var _origin:Vector2 = origin_node.global_position
	for i:int in summon_count:
		var _offset:Vector2 = Vector2.RIGHT.rotated(TAU * i / summon_count) * summon_radius
		var _config_callback:Callable = func (inst:Node2D)->void:
			inst.global_position = _origin + _offset
			ActiveEnemy.insert_child(inst, _branch)
		summon_instance_resource.instance(_config_callback)

	shoot_sound.play_managed()
	return true
