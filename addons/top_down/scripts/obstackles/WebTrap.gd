## A web that sits on a tile. The player who steps on it is stuck (ZoneTransmission),
## and a shot that kills it removes it.
class_name WebTrap
extends Node2D

@export var resource_node:ResourceNode

func _ready()->void:
	var _health_resource:HealthResource = resource_node.get_resource("health")
	assert(_health_resource != null)
	_health_resource.dead.connect(queue_free)
