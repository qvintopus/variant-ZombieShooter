## Holds the actor in place while "stuck" BoolResource is true (spider web).
## Dash breaks free, but only moves escape_distance.
class_name StuckEffect
extends Node

@export var resource_node:ResourceNode

@export var dash_ability:DashAbility

## Seconds held in place
@export var stuck_time:float = 2.0

## Pixels the escape dash moves the actor
@export var escape_distance:float = 12.0

## Acceleration while stuck, high value stops movement instantly
@export var stuck_acceleration:float = 10000.0

var stuck_bool:BoolResource
var dash_bool:BoolResource
var movement_resource:ActorStatsResource
var push_resource:PushResource
var input_resource:InputResource

var default_acceleration:float
var release_tween:Tween

func _ready()->void:
	stuck_bool = resource_node.get_resource("stuck")
	assert(stuck_bool != null)
	dash_bool = resource_node.get_resource("dash")
	assert(dash_bool != null)
	movement_resource = resource_node.get_resource("movement")
	assert(movement_resource != null)
	push_resource = resource_node.get_resource("push")
	assert(push_resource != null)
	input_resource = resource_node.get_resource("input")
	assert(input_resource != null)

	stuck_bool.changed_true.connect(_on_stuck)
	stuck_bool.changed_false.connect(_on_released)
	dash_bool.changed_true.connect(_on_dash)

	# in case used with PoolNode
	request_ready()
	tree_exiting.connect(_on_tree_exiting, CONNECT_ONE_SHOT)

func _on_stuck()->void:
	default_acceleration = movement_resource.acceleration
	movement_resource.set_speed_multiplier(&"stuck", 0.0)
	movement_resource.acceleration = stuck_acceleration
	_release_after(stuck_time)

## DashAbility adds its impulse before setting dash true.
## Replace it with an impulse that slides escape_distance and stops.
func _on_dash()->void:
	if !stuck_bool.value:
		return
	var _escape_speed:float = sqrt(2.0 * default_acceleration * escape_distance)
	push_resource.add_impulse(input_resource.axis * (_escape_speed - dash_ability.impulse_strength))
	movement_resource.acceleration = default_acceleration
	_release_after(_escape_speed / default_acceleration)

func _release_after(time:float)->void:
	if release_tween != null:
		release_tween.kill()
	release_tween = create_tween()
	release_tween.tween_callback(stuck_bool.set_value.bind(false)).set_delay(time)

## Also called when something else sets stuck to false (web got shot)
func _on_released()->void:
	if release_tween != null:
		release_tween.kill()
		release_tween = null
	movement_resource.set_speed_multiplier(&"stuck", 1.0)
	movement_resource.acceleration = default_acceleration

func _on_tree_exiting()->void:
	stuck_bool.set_value(false)
	stuck_bool.changed_true.disconnect(_on_stuck)
	stuck_bool.changed_false.disconnect(_on_released)
	dash_bool.changed_true.disconnect(_on_dash)
