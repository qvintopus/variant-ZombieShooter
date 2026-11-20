## Pooled burst around a player: spark particles + expanding rings (wave / room clear).
@tool
class_name ClearBurst
extends Node2D

@export var sparks:Array[GPUParticles2D]
@export var pool_node:PoolNode

@export_group("Rings")
@export var ring_count:int = 1
@export var ring_delay:float = 0.1
@export var ring_radius:float = 48.0
@export var ring_width:float = 2.0
@export_range(0.05, 3.0, 0.01) var ring_time:float = 0.45
@export var ring_color:Color = Color(1.0, 0.92, 0.55, 0.9)
## Isometric squash
@export var ring_squash:Vector2 = Vector2(1.0, 0.5)

@export_group("Life")
## Seconds before returning to the pool
@export var life_time:float = 1.2

@export_group("Editor")
## Scrub the ring in the editor (0..1)
@export_range(0.0, 1.0, 0.01) var preview_t:float = 0.5:
	set(value):
		preview_t = value
		queue_redraw()

var _t:float = -1.0
var _life:float

func _ready()->void:
	if Engine.is_editor_hint():
		return
	_t = 0.0
	_life = 0.0
	for _p:GPUParticles2D in sparks:
		if _p != null:
			_p.restart()
			_p.emitting = true
	set_process(true)
	request_ready()

func _process(delta:float)->void:
	if Engine.is_editor_hint():
		return
	_t += delta
	_life += delta
	queue_redraw()
	if _life >= life_time:
		set_process(false)
		if pool_node != null:
			pool_node.pool_return()
		else:
			queue_free()

func _draw()->void:
	if Engine.is_editor_hint():
		_draw_ring(preview_t)
		return
	if _t < 0.0:
		return
	for i:int in ring_count:
		var _local:float = (_t - i * ring_delay) / ring_time
		if _local >= 0.0 && _local <= 1.0:
			_draw_ring(_local)

func _draw_ring(t:float)->void:
	var _ease:float = 1.0 - pow(1.0 - t, 3.0)
	var _color:Color = ring_color
	_color.a *= 1.0 - t
	draw_set_transform(Vector2.ZERO, 0.0, ring_squash)
	draw_arc(Vector2.ZERO, maxf(ring_radius * _ease, 0.5), 0.0, TAU, 48, _color, ring_width / maxf(ring_squash.y, 0.01) * (1.0 - t * 0.5))
