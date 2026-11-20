## Boss death: a copy of the boss sprite shakes while light cracks open inside
## it (inner_light.gdshader) and rays spread out, then it blows up in light.
## Spawned by BossDeathFx with setup_from_sprite().
@tool
class_name BossDeathBurst
extends Node2D

@export var body:Sprite2D
@export var pool_node:PoolNode

@export_group("Charge")
@export_range(0.1, 5.0, 0.01) var charge_time:float = 1.4
## Shake amplitude in pixels at the end of the charge
@export var shake_max:float = 3.0
@export var hum_sound:SoundResource
@export var hum_interval:float = 0.18
@export var hum_pitch_start:float = 0.6
@export var hum_pitch_end:float = 1.8

@export_group("Rays")
@export var ray_count:int = 7
@export var ray_length:float = 70.0
@export var ray_width:float = 5.0
@export var ray_color:Color = Color(1.0, 0.95, 0.7, 0.85)
## Rays spin this many turns over the charge
@export var ray_spin:float = 0.15
## Where light comes from, relative to the burst (boss chest)
@export var ray_origin:Vector2 = Vector2(0.0, -22.0)
## Isometric squash for rays
@export var ray_squash:Vector2 = Vector2(1.0, 0.7)

@export_group("Blast")
@export var explosion_vfx:InstanceResource
@export var explosion_count:int = 3
@export var explosion_spread:float = 14.0
@export var explosion_stagger:float = 0.08
@export var explosion_scale:float = 2.0
@export var blast_burst:InstanceResource
@export var camera_shake:CameraShakeResource
@export var screen_flash:ReferenceNodeResource
@export var screen_flash_animation:StringName = &"white_flash"
@export var blast_sound:SoundResource
## Seconds the light lingers after the blast
@export_range(0.0, 3.0, 0.01) var afterglow_time:float = 0.6

@export_group("Editor")
@export_range(0.0, 1.0, 0.01) var preview:float = 0.0:
	set(value):
		preview = value
		_set_progress(value)
		queue_redraw()

var _age:float
var _hum_left:float
var _blasted:bool
var _base_offset:Vector2
var _material:ShaderMaterial

## Copy the look of the dying boss (call in the InstanceResource config callback).
func setup_from_sprite(source:Sprite2D, world_position:Vector2)->void:
	global_position = world_position
	if source == null || body == null:
		return
	body.texture = source.texture
	body.hframes = source.hframes
	body.vframes = source.vframes
	body.frame = source.frame
	body.centered = source.centered
	body.offset = source.offset
	body.flip_h = source.flip_h
	body.position = source.global_position - world_position
	body.scale = source.global_scale
	body.modulate = Color.WHITE
	_base_offset = body.position
	if _material != null && source.texture != null:
		var _size:Vector2 = source.texture.get_size() / Vector2(maxi(source.hframes, 1), maxi(source.vframes, 1))
		_material.set_shader_parameter(&"texel_snap", _size * Vector2(maxi(source.hframes, 1), maxi(source.vframes, 1)))

func _enter_tree()->void:
	if body != null:
		_material = body.material as ShaderMaterial

func _ready()->void:
	if Engine.is_editor_hint():
		return
	_age = 0.0
	_hum_left = 0.0
	_blasted = false
	if body != null:
		body.visible = true
	_set_progress(0.0)
	set_process(true)
	request_ready()

func _set_progress(value:float)->void:
	if body == null:
		return
	var _m:ShaderMaterial = body.material as ShaderMaterial
	if _m != null:
		_m.set_shader_parameter(&"progress", value)

func _process(delta:float)->void:
	if Engine.is_editor_hint():
		return
	_age += delta
	queue_redraw()
	if !_blasted:
		var _t:float = clampf(_age / charge_time, 0.0, 1.0)
		_set_progress(_t * 0.85)
		if body != null:
			body.position = _base_offset + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_max * _t
		_hum_left -= delta
		if _hum_left <= 0.0 && hum_sound != null:
			_hum_left = hum_interval
			hum_sound.play_pitched(lerpf(hum_pitch_start, hum_pitch_end, _t))
		if _age >= charge_time:
			_blast()
		return
	var _after:float = _age - charge_time
	_set_progress(0.85 + 0.15 * clampf(_after / maxf(afterglow_time * 0.5, 0.01), 0.0, 1.0))
	if _after >= afterglow_time:
		set_process(false)
		if pool_node != null:
			pool_node.pool_return()
		else:
			queue_free()

func _blast()->void:
	_blasted = true
	var _at:Vector2 = global_position + ray_origin
	if explosion_vfx != null:
		for i:int in explosion_count:
			var _offset:Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * explosion_spread
			var _scale:float = explosion_scale
			var _spawn:Callable = func ()->void:
				explosion_vfx.instance(func (n:Node2D)->void:
					n.global_position = _at + _offset
					n.scale = Vector2.ONE * _scale)
			if i == 0:
				_spawn.call()
			else:
				get_tree().create_timer(explosion_stagger * i, false).timeout.connect(_spawn)
	if blast_burst != null:
		blast_burst.instance(func (n:Node2D)->void: n.global_position = _at)
	if camera_shake != null:
		camera_shake.play()
	if screen_flash != null && screen_flash.node != null && screen_flash.node.has_method(&"play"):
		screen_flash.node.play(screen_flash_animation)
	if blast_sound != null:
		blast_sound.play_managed()

func _ray_t()->float:
	if Engine.is_editor_hint():
		return preview
	if !_blasted:
		return clampf(_age / charge_time, 0.0, 1.0)
	return 1.0 - clampf((_age - charge_time) / maxf(afterglow_time, 0.01), 0.0, 1.0)

func _draw()->void:
	var _t:float = _ray_t()
	if _t <= 0.0 || ray_count <= 0:
		return
	var _len:float = ray_length * (_t * _t if !_blasted else 1.0 + (1.0 - _t))
	var _spin:float = TAU * ray_spin * _t
	var _color:Color = ray_color
	_color.a *= _t
	for i:int in ray_count:
		var _a:float = TAU * float(i) / ray_count + _spin
		var _dir:Vector2 = Vector2(cos(_a), sin(_a)) * ray_squash
		var _side:Vector2 = _dir.orthogonal().normalized() * ray_width * 0.5 * _t
		var _p0:Vector2 = ray_origin
		var _tip:Vector2 = ray_origin + _dir * _len
		draw_colored_polygon(PackedVector2Array([_p0 + _side, _p0 - _side, _tip]), _color)
	draw_circle(ray_origin, 6.0 * _t, Color(_color.r, _color.g, _color.b, _color.a * 0.8))
