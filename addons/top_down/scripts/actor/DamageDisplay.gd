## Floating damage numbers above the actor. Respects Options > Gameplay settings.
class_name DamageDisplay
extends Node

@export var resource_node:ResourceNode
@export var damage_points_instance_resource:InstanceResource
@export var settings:DamageNumbersSettings

## Player (or teammate copy): uses the "player" color and the player toggle.
@export var is_player:bool

## Hits within this many seconds add up in one number
@export_range(0.0, 2.0, 0.01) var merge_interval:float = 0.3

## Where the number appears relative to the actor
@export var offset:Vector2 = Vector2(0.0, -8.0)

var last_time:float
var last_points:FloatingText
var last_critical:bool
var total_points:float

func _ready()->void:
	var _damage_resource:DamageResource = resource_node.get_resource("damage")
	assert(_damage_resource != null)
	_damage_resource.received_damage_points.connect(_on_damage_points)
	
	# in case used with PoolNode
	request_ready()

func _shown()->bool:
	if settings == null:
		return true
	return settings.show_player if is_player else settings.show_enemy

func _color(is_critical:bool)->Color:
	var _colors:DamageNumberColors = settings.colors() if settings != null else DamageNumberColors.new()
	if is_player:
		return _colors.player
	return _colors.critical if is_critical else _colors.enemy

func _font_size()->int:
	return settings.font_size() if settings != null else 8

func _on_damage_points(points:float, is_critical:bool)->void:
	if !_shown():
		return
	var _time:float = Time.get_ticks_msec() * 0.001
	if last_critical == is_critical && is_instance_valid(last_points) && last_points.is_inside_tree() && _time < last_time + merge_interval:
		last_time = _time
		total_points += points
		last_points.bump(str(roundi(total_points)), _color(is_critical), _font_size(), is_critical)
		return
	
	last_time = _time
	total_points = points
	last_critical = is_critical
	var _config_callback:Callable = func (inst:Node2D)->void:
		inst.global_position = owner.global_position + offset
		(inst as FloatingText).setup(str(roundi(total_points)), _color(is_critical), _font_size(), is_critical)
	
	last_points = damage_points_instance_resource.instance(_config_callback)
