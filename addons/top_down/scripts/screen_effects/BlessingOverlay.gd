## Full-screen "blessing bestowed" light for a cleared room (blessing.gdshader).
## play() fades in, holds, fades out; center follows a world node (the player).
@tool
class_name BlessingOverlay
extends CanvasLayer

signal finished

@export var rect:ColorRect
@export_range(0.01, 5.0, 0.01) var fade_in:float = 0.4
@export_range(0.0, 5.0, 0.01) var hold:float = 0.6
@export_range(0.01, 5.0, 0.01) var fade_out:float = 0.9
## Peak strength (shader progress)
@export_range(0.0, 1.0, 0.01) var peak:float = 1.0
@export var sound:SoundResource

@export_group("Editor")
## Scrub the effect in the editor
@export_range(0.0, 1.0, 0.01) var preview:float = 0.0:
	set(value):
		preview = value
		_set_progress(value)

var _follow:Node2D
var _tween:Tween

func _ready()->void:
	if rect != null:
		rect.visible = Engine.is_editor_hint() && preview > 0.0
	_set_progress(preview if Engine.is_editor_hint() else 0.0)

func _material()->ShaderMaterial:
	return rect.material as ShaderMaterial if rect != null else null

func _set_progress(value:float)->void:
	var _m:ShaderMaterial = _material()
	if _m != null:
		_m.set_shader_parameter(&"progress", value)
	if rect != null:
		rect.visible = value > 0.0

## Starts the blessing centered on `follow` (world node; screen center when null).
func play(follow:Node2D = null)->void:
	_follow = follow
	if sound != null:
		sound.play_managed()
	if _tween != null:
		_tween.kill()
	_update_center()
	_tween = create_tween()
	_tween.tween_method(_set_progress, 0.0, peak, fade_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(hold)
	_tween.tween_method(_set_progress, peak, 0.0, fade_out).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.finished.connect(finished.emit)

func _process(_delta:float)->void:
	if Engine.is_editor_hint():
		return
	if rect != null && rect.visible:
		_update_center()

func _update_center()->void:
	var _m:ShaderMaterial = _material()
	if _m == null:
		return
	var _size:Vector2 = get_viewport().get_visible_rect().size
	if _size.x <= 0.0 || _size.y <= 0.0:
		return
	_m.set_shader_parameter(&"aspect", _size.x / _size.y)
	var _uv:Vector2 = Vector2(0.5, 0.5)
	if _follow != null && is_instance_valid(_follow) && _follow.is_inside_tree():
		var _screen:Vector2 = _follow.get_global_transform_with_canvas().origin
		_uv = _screen / _size
	_m.set_shader_parameter(&"center", _uv)
