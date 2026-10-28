## Lob attack through an EnemyLob (auto_fire off), aimed where the target is when the windup ends.
## Projectile shadows show where they land, so moving after the throw dodges them.
class_name BossLob
extends BossAttack

@export var lob:EnemyLob

@export var volleys:int = 1

@export var volley_delay:float = 0.3

## Next volleys aim this many degrees further, sweeping (0 aims each volley at the target again)
@export var volley_rotation:float = 0.0

## When projectiles spawn enemies (lob.active_enemy), not available while this many children are alive
@export var child_limit:int = -1

func is_available(time:float, distance:float, health_ratio:float)->bool:
	if _free_child_slots() == 0:
		return false
	return super.is_available(time, distance, health_ratio)

## -1 when not limited
func _free_child_slots()->int:
	if child_limit < 0 || lob.active_enemy == null || lob.active_enemy.enemy_resource == null:
		return -1
	return maxi(0, child_limit - lob.active_enemy.enemy_resource.children.size())

func perform()->void:
	var _rotation:float = 0.0
	for i:int in volleys:
		if !running || !has_target():
			return
		var _origin:Vector2 = lob.origin_node.global_position
		var _aim:Vector2 = _origin + (target.global_position - _origin).rotated(deg_to_rad(_rotation))
		lob.shoot(_aim, _free_child_slots())
		_rotation += volley_rotation
		if i < volleys - 1:
			await get_tree().create_timer(volley_delay, false, true).timeout
