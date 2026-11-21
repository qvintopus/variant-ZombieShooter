## Dark pie over an icon showing the remaining cooldown (1 = full).
@tool
class_name CooldownPie
extends Control

@export_range(0.0, 1.0, 0.01) var value:float = 0.0:
	set(v):
		value = v
		queue_redraw()
@export var color:Color = Color(0.0, 0.0, 0.0, 0.65)
@export var segments:int = 32

func _draw()->void:
	if value <= 0.0:
		return
	var _center:Vector2 = size * 0.5
	var _radius:float = size.length() * 0.5
	var _points:PackedVector2Array = [_center]
	var _start:float = -PI * 0.5
	var _end:float = _start + TAU * value
	for i:int in segments + 1:
		var _a:float = lerpf(_start, _end, float(i) / segments)
		var _p:Vector2 = _center + Vector2(cos(_a), sin(_a)) * _radius
		_points.append(Vector2(clampf(_p.x, 0.0, size.x), clampf(_p.y, 0.0, size.y)))
	draw_colored_polygon(_points, color)
