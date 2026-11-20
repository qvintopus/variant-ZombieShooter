## Pooled popup text: pops in, arcs up and down, fades. Damage numbers and
## pickup texts. Spawn through an InstanceResource, call setup() in the config callback.
class_name FloatingText
extends Node2D

@export var label:Label
@export var pool_node:PoolNode
@export var style:FloatingTextStyle

var _start:Vector2
var _drift:float
var _critical:bool
var _move_tween:Tween
var _pop_tween:Tween
var _shake_left:float

## Call before the node enters the tree (InstanceResource config callback).
func setup(text:String, color:Color, font_size:int, critical:bool = false)->void:
	_critical = critical
	label.text = text
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_constant_override(&"outline_size", style.outline_size)
	label.add_theme_color_override(&"font_outline_color", style.outline_color)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)

## Update shown text of a live popup (merged hits) and pop it again.
func bump(text:String, color:Color, font_size:int, critical:bool = false)->void:
	setup(text, color, font_size, critical)
	if is_inside_tree():
		_pop()

func _ready()->void:
	_start = global_position + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * style.spread
	_drift = randf_range(-1.0, 1.0) * style.drift
	modulate.a = 1.0
	if _move_tween != null:
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_method(_move, 0.0, 1.0, style.duration)
	_move_tween.finished.connect(pool_node.pool_return)
	_pop()

func _pop()->void:
	var _base:float = style.critical_scale if _critical else 1.0
	if _pop_tween != null:
		_pop_tween.kill()
	scale = Vector2.ONE * style.start_scale * _base
	_pop_tween = create_tween()
	_pop_tween.tween_property(self, ^"scale", Vector2.ONE * style.pop_scale * _base, style.pop_time * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(self, ^"scale", Vector2.ONE * _base, style.pop_time * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shake_left = style.critical_shake_time if _critical else 0.0

## Arc through the top (rise) and down by `fall`: y = -a*t + b*t^2.
func _move(t:float)->void:
	var _r:float = sqrt(maxf(style.rise, 0.0))
	var _f:float = sqrt(maxf(style.fall, 0.0))
	var _a:float = 2.0 * _r * (_r + _f)
	var _b:float = (_r + _f) * (_r + _f)
	var _offset:Vector2 = Vector2(_drift * t, -_a * t + _b * t * t)
	if _shake_left > 0.0:
		_shake_left -= get_process_delta_time()
		_offset += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * style.critical_shake
	global_position = _start + _offset
	var _fade_from:float = 1.0 - style.fade_portion
	modulate.a = 1.0 if t < _fade_from else clampf(1.0 - (t - _fade_from) / maxf(style.fade_portion, 0.001), 0.0, 1.0)
