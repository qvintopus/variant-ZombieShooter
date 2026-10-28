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

## Easy difficulty uses easy_count and easy_child_limit instead (-1 keeps the normal value)
@export var difficulty_resource:DifficultyResource

## Projectiles per volley on easy, the first lob angles
@export var easy_count:int = -1

@export var easy_child_limit:int = -1

func is_available(time:float, distance:float, health_ratio:float)->bool:
	if _free_child_slots() == 0:
		return false
	return super.is_available(time, distance, health_ratio)

func _is_easy()->bool:
	return difficulty_resource != null && difficulty_resource.is_easy()

func get_child_limit()->int:
	return easy_child_limit if _is_easy() && easy_child_limit >= 0 else child_limit

## -1 when not limited
func get_count()->int:
	return easy_count if _is_easy() && easy_count >= 0 else -1

## -1 when not limited
func _free_child_slots()->int:
	var _limit:int = get_child_limit()
	if _limit < 0 || lob.active_enemy == null || lob.active_enemy.enemy_resource == null:
		return -1
	return maxi(0, _limit - lob.active_enemy.enemy_resource.children.size())

## Smallest of the free child slots and the easy count, -1 when neither limits
func _max_count()->int:
	var _slots:int = _free_child_slots()
	var _count:int = get_count()
	if _slots < 0:
		return _count
	if _count < 0:
		return _slots
	return mini(_slots, _count)

func perform()->void:
	var _rotation:float = 0.0
	for i:int in volleys:
		if !running || !has_target():
			return
		var _origin:Vector2 = lob.origin_node.global_position
		var _aim:Vector2 = _origin + (target.global_position - _origin).rotated(deg_to_rad(_rotation))
		lob.shoot(_aim, _max_count())
		_rotation += volley_rotation
		if i < volleys - 1:
			await get_tree().create_timer(volley_delay, false, true).timeout
