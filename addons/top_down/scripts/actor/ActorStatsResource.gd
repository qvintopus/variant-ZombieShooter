class_name ActorStatsResource
extends SaveableResource

@export var acceleration:float
@export var max_speed:float

## Speed multipliers from effects, keyed by source (e.g. "stuck", "slow")
var speed_multipliers:Dictionary

## Value 1.0 removes the multiplier
func set_speed_multiplier(key:StringName, value:float)->void:
	if value == 1.0:
		speed_multipliers.erase(key)
		return
	speed_multipliers[key] = value

## max_speed with all multipliers applied
func get_max_speed()->float:
	var _speed:float = max_speed
	for _value:float in speed_multipliers.values():
		_speed *= _value
	return _speed
