## Instances a scene where the projectile lands (web trap, acid puddle).
class_name SpawnOnLand
extends Node

@export var projectile:Projectile2D

@export var instance_resource:InstanceResource

func _ready()->void:
	projectile.prepare_exit_event.connect(_on_prepare_exit)

func _on_prepare_exit()->void:
	var _pos:Vector2 = projectile.global_position

	var _config_callback:Callable = func (inst:Node2D)->void:
		inst.global_position = _pos

	instance_resource.instance(_config_callback)
