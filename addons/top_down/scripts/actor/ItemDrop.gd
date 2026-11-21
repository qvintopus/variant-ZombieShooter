class_name ItemDrop
extends Node

@export var resource_node:ResourceNode
@export var root_node:Node2D
@export var drop_instance_resources:Array[InstanceResource]
@export var drop_chance:float = 0.1
## Seconds before the drop appears (boss death burst)
@export var delay:float = 0.0

func _ready()->void:
	var _health_resource:HealthResource = resource_node.get_resource("health")
	assert(_health_resource != null)
	_health_resource.dead.connect(_on_death)
	
	# in case used with PoolNode
	request_ready()
	tree_exiting.connect(_health_resource.dead.disconnect.bind(_on_death), CONNECT_ONE_SHOT)

func _on_death()->void:
	if drop_instance_resources.is_empty():
		return
	if randf() > drop_chance:
		return
	
	var _at:Vector2 = root_node.global_position
	var _config_callback:Callable = func (inst:Node2D)->void:
		inst.global_position = _at
	
	var _drop_instance_resource:InstanceResource = drop_instance_resources.pick_random()
	if delay > 0.0 && is_inside_tree():
		get_tree().create_timer(delay, false).timeout.connect(_drop_instance_resource.instance.bind(_config_callback))
	else:
		_drop_instance_resource.instance(_config_callback)
