## Ground warning drawn during a boss attack windup.
## CIRCLE marks an area around the node, LINE marks a path (vector) from the node.
## Outline shows the full size, fill grows until the attack happens.
class_name BossTelegraph
extends Node2D

enum Shape {CIRCLE, LINE}

@export var shape:Shape

## CIRCLE radius
@export var radius:float = 40.0

## LINE width
@export var width:float = 16.0

@export var color:Color = Color(1.0, 0.25, 0.15, 0.3)

@export var axis_multiplication:Vector2Resource

## LINE path in global space
var vector:Vector2

var progress:float:
	set(value):
		progress = value
		queue_redraw()

var tween:Tween

func _ready()->void:
	hide()

func show_telegraph(time:float)->void:
	if tween != null:
		tween.kill()
	progress = 0.0
	show()
	tween = create_tween()
	tween.tween_property(self, "progress", 1.0, time)

func hide_telegraph()->void:
	if tween != null:
		tween.kill()
	hide()

func _draw()->void:
	var _outline:Color = Color(color, minf(color.a * 2.0, 1.0))
	if shape == Shape.CIRCLE:
		var _squash:Vector2 = Vector2.ONE
		if axis_multiplication != null:
			_squash = Vector2(1.0, axis_multiplication.value.y / axis_multiplication.value.x)
		draw_set_transform(Vector2.ZERO, 0.0, _squash)
		draw_circle(Vector2.ZERO, radius * progress, color)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, _outline, 1.0)
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var _side:Vector2 = vector.normalized().orthogonal() * width * 0.5
	var _end:Vector2 = vector * progress
	draw_colored_polygon(PackedVector2Array([_side, _end + _side, _end - _side, -_side]), color)
	draw_polyline(PackedVector2Array([_side, vector + _side, vector - _side, -_side, _side]), _outline, 1.0)
