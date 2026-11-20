## Total damage immunity while the "dash" BoolResource is on (hits, acid and
## poison puddles, status ticks). Works with DamageResource.dash_immune, which
## DamageResource.is_blocked() and the DoT nodes check.
class_name DashImmunity
extends Node

@export var enabled:bool = true

@export var resource_node:ResourceNode

## Seconds the immunity lasts after the dash state ends (0 = exactly the dash).
@export_range(0.0, 1.0, 0.01) var grace_time:float = 0.0

## Also skip damage-over-time ticks (acid, poison, status DoT) while immune.
@export var block_damage_over_time:bool = true

var dash_bool:BoolResource
var damage_resource:DamageResource
var _grace_tween:Tween

func _ready()->void:
	dash_bool = resource_node.get_resource("dash")
	damage_resource = resource_node.get_resource("damage")
	assert(dash_bool != null && damage_resource != null)
	dash_bool.changed_true.connect(_on_dash_start)
	dash_bool.changed_false.connect(_on_dash_end)
	tree_exiting.connect(_on_tree_exiting, CONNECT_ONE_SHOT)
	# in case used with PoolNode
	request_ready()

func _on_dash_start()->void:
	if !enabled:
		return
	if _grace_tween != null:
		_grace_tween.kill()
	damage_resource.dash_immune = true
	damage_resource.dash_blocks_dot = block_damage_over_time

func _on_dash_end()->void:
	if _grace_tween != null:
		_grace_tween.kill()
	if grace_time <= 0.0:
		_clear()
		return
	_grace_tween = create_tween()
	_grace_tween.tween_callback(_clear).set_delay(grace_time)

func _clear()->void:
	damage_resource.dash_immune = false

func _on_tree_exiting()->void:
	_clear()
	dash_bool.changed_true.disconnect(_on_dash_start)
	dash_bool.changed_false.disconnect(_on_dash_end)
