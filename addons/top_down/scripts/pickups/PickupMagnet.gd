## Magnetized pickup movement: pulled with momentum toward players in range,
## glides and slows when they get away, so a player can drag (kite) items around.
## Every player pulls (teammate copies too, for looks); only the local player
## collects (CollectingPoint).
@tool
class_name PickupMagnet
extends Node2D

signal reached_local_player

@export var enabled:bool = true
@export var preset:MagnetPreset:
	set(value):
		preset = value
		queue_redraw()
@export var moved_node:Node2D
@export var player_reference:ReferenceNodeResource
## Isometric squash of distances (Vector2(1, 0.5))
@export var axis_multiplication:Vector2Resource
## Teammate copies pull too
@export var remote_group:StringName = &"remote_player"

@export_group("Editor")
@export var show_radius_in_editor:bool = true

var velocity:Vector2
var attracted:bool
var active:bool

func _ready()->void:
	set_physics_process(false)
	if Engine.is_editor_hint():
		return
	request_ready()

## Called by CollectingPoint once the spawn scatter is done.
func start()->void:
	velocity = Vector2.ZERO
	attracted = false
	active = enabled && preset != null
	set_physics_process(active)

func stop()->void:
	active = false
	set_physics_process(false)

func _axis()->Vector2:
	return axis_multiplication.value if axis_multiplication != null else Vector2.ONE

## World offset -> flat space
func _flat(offset:Vector2)->Vector2:
	var _a:Vector2 = _axis()
	return Vector2(offset.x / maxf(_a.x, 0.001), offset.y / maxf(_a.y, 0.001))

func _nearest_target()->Node2D:
	var _best:Node2D = null
	var _best_d:float = INF
	var _candidates:Array = get_tree().get_nodes_in_group(remote_group)
	if player_reference != null && is_instance_valid(player_reference.node):
		_candidates.append(player_reference.node)
	for _node:Node in _candidates:
		var _body:Node2D = _node as Node2D
		if _body == null || !_body.is_inside_tree():
			continue
		var _d:float = _flat(_body.global_position - moved_node.global_position).length_squared()
		if _d < _best_d:
			_best_d = _d
			_best = _body
	return _best

func _physics_process(delta:float)->void:
	if Engine.is_editor_hint() || !active:
		return
	var _target:Node2D = _nearest_target()
	var _to:Vector2 = Vector2.ZERO
	var _dist:float = INF
	if _target != null:
		_to = _flat(_target.global_position - moved_node.global_position)
		_dist = _to.length()
	if attracted:
		attracted = _dist < preset.release_radius
	else:
		attracted = _dist < preset.radius
	if attracted && _dist > 0.001:
		var _dir:Vector2 = _to / _dist
		var _pull:Vector2 = (_dir + _dir.orthogonal() * preset.swirl).normalized()
		velocity += _pull * preset.acceleration * delta
		velocity = velocity.limit_length(preset.max_speed)
	else:
		velocity *= exp(-preset.drag * delta)
	var _a:Vector2 = _axis()
	moved_node.global_position += Vector2(velocity.x * _a.x, velocity.y * _a.y) * delta
	if _target != null && player_reference != null && _target == player_reference.node && _dist <= preset.collect_radius:
		stop()
		reached_local_player.emit()

func _draw()->void:
	if !Engine.is_editor_hint() || !show_radius_in_editor || preset == null:
		return
	var _a:Vector2 = Vector2(1.0, 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, _a)
	draw_arc(Vector2.ZERO, preset.radius, 0.0, TAU, 48, Color(0.3, 1.0, 0.5, 0.6), 1.0)
	draw_arc(Vector2.ZERO, preset.release_radius, 0.0, TAU, 48, Color(1.0, 0.6, 0.2, 0.4), 1.0)
	draw_arc(Vector2.ZERO, preset.collect_radius, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.8), 1.0)
