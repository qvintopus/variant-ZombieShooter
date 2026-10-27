## Ticks ZoneEffectResource on the actor: stuck and slow change movement speed,
## poison deals damage every second.
class_name ZoneEffectNode
extends Node

@export var resource_node:ResourceNode

## Multiplies movement speed, read by MoverTopDown2D
var speed_resource:FloatResource

var zone_resource:ZoneEffectResource

var health_resource:HealthResource

var _poison_tick:float

func _ready()->void:
	speed_resource = resource_node.get_resource("speed_scale")
	zone_resource = resource_node.get_resource("zone")
	health_resource = resource_node.get_resource("health")
	assert(speed_resource != null)
	assert(zone_resource != null)
	assert(health_resource != null)

func _process(delta:float)->void:
	zone_resource.stuck_time = max(zone_resource.stuck_time - delta, 0.0)
	zone_resource.slow_time = max(zone_resource.slow_time - delta, 0.0)
	zone_resource.poison_time = max(zone_resource.poison_time - delta, 0.0)

	var _speed:float = 1.0
	if zone_resource.stuck_time > 0.0:
		_speed = 0.0
	elif zone_resource.slow_time > 0.0:
		_speed = zone_resource.slow_factor
	if speed_resource.value != _speed:
		speed_resource.set_value(_speed)

	if zone_resource.poison_time <= 0.0:
		_poison_tick = 0.0
		return
	_poison_tick -= delta
	if _poison_tick <= 0.0:
		_poison_tick += 1.0
		if !health_resource.is_dead:
			health_resource.add_hp(-zone_resource.poison_damage)
