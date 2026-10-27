## Slows the actor while "slow" BoolResource keeps getting set (slime puddle).
## TrapTransmission with repeat_while_inside sets it every physics frame while inside.
## Actors without "slow" resource are not affected.
class_name SlowEffect
extends Node

@export var resource_node:ResourceNode

## Multiplier for max speed while slowed
@export var slow_multiplier:float = 0.5

## Seconds the slow stays after the last pulse (after leaving the puddle)
@export var linger_time:float = 0.1

var slow_bool:BoolResource
var movement_resource:ActorStatsResource
var remaining_time:float

func _ready()->void:
	slow_bool = resource_node.get_resource("slow")
	movement_resource = resource_node.get_resource("movement")
	if slow_bool == null || movement_resource == null:
		set_physics_process(false)
		return
	slow_bool.changed_true.connect(_on_pulse)
	set_physics_process(true)

	# in case used with PoolNode
	request_ready()
	tree_exiting.connect(_on_tree_exiting, CONNECT_ONE_SHOT)

func _on_pulse()->void:
	# reset so next pulse triggers changed_true again
	slow_bool.set_value(false)
	if remaining_time <= 0.0:
		movement_resource.set_speed_multiplier(&"slow", slow_multiplier)
	remaining_time = linger_time

func _physics_process(delta:float)->void:
	if remaining_time <= 0.0:
		return
	remaining_time -= delta
	if remaining_time <= 0.0:
		movement_resource.set_speed_multiplier(&"slow", 1.0)

func _on_tree_exiting()->void:
	remaining_time = 0.0
	movement_resource.set_speed_multiplier(&"slow", 1.0)
	slow_bool.changed_true.disconnect(_on_pulse)
