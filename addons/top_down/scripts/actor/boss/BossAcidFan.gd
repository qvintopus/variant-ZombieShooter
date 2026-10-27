## Secondary boss attack: a fan of acid spits.
## By default the fan is aimed around the target direction. With aim_at_target every spit lands
## on the target position, spread a little sideways so the three do not stack.
class_name BossAcidFan
extends BigJellyShootSlime

@export var spit_count:int = 3

## Angle between neighbouring spits, in radians
@export var fan_angle:float = 0.3

@export var aim_at_target:bool = false

## Distance between neighbouring spits when aiming at the target, in pixels
@export var target_spread:float = 10.0

## return bool if shooting is performed
func shoot(target_position:Vector2)->bool:
	var _origin:Vector2 = origin_node.global_position
	var _direction:Vector2 = (target_position - _origin).normalized()
	var _side:Vector2 = _direction.orthogonal()
	for i:int in spit_count:
		var _index:float = i - (spit_count - 1) / 2.0
		var _spit_direction:Vector2 = _direction.rotated(fan_angle * _index)
		var _pos:Vector2 = _origin + (spawn_radius * _spit_direction * axis_multiply.value)
		var _destination:Vector2 = _origin + _spit_direction * 256.0
		if aim_at_target:
			_destination = target_position + _side * target_spread * _index

		var _config_callback:Callable = func (inst:Projectile2D)->void:
			inst.global_position = _pos
			inst.destination = _destination

		projectile_instance.instance(_config_callback)

	shoot_sound.play_managed()
	shot.emit()
	return true
