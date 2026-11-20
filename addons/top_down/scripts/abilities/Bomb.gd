## Dropped bomb: tossed a little, fuse burns faster and glows white, then
## explodes (area damage + push, explosion, sparks, shake, flash).
## visual_only: a teammate's bomb replayed here (no damage).
class_name Bomb
extends Node2D

@export var sprite:Sprite2D
@export var pool_node:PoolNode
@export var visual_only:bool

@export_group("Fuse")
@export_range(0.1, 5.0, 0.01) var fuse_time:float = 1.2
## Last part of the fuse spent white-hot
@export_range(0.0, 2.0, 0.01) var hot_time:float = 0.4
@export var idle_texture:Texture2D
@export var idle_frames:int = 4
@export var hot_texture:Texture2D
@export var hot_frames:int = 2
## Spark animation speed at fuse start / end (frames per second)
@export var fps_start:float = 8.0
@export var fps_end:float = 30.0
## Pulse scale at the end of the fuse
@export var throb_scale:float = 1.25
@export var tick_sound:SoundResource
## Seconds between ticks at start / end
@export var tick_interval_start:float = 0.35
@export var tick_interval_end:float = 0.08
@export var tick_pitch_start:float = 0.9
@export var tick_pitch_end:float = 1.6

@export_group("Toss")
@export var toss_time:float = 0.25
@export var toss_height:float = 8.0

@export_group("Blast")
@export var damage_cast:ShapeCastTransmitter2D
@export var damage_channel:DataChannelTransmitter
@export var axis_multiplication:Vector2Resource
@export var kickback_radius:float = 32.0
@export var kickback_max:float = 200.0
@export var kickback_min:float = 80.0
@export var explosion_vfx:InstanceResource
@export var explosion_scale:float = 2.0
@export var blast_burst:InstanceResource
@export var camera_shake:CameraShakeResource
## Screen white flash (CommandNodeResource with an AnimationPlayer)
@export var screen_flash:ReferenceNodeResource
@export var screen_flash_animation:StringName = &"white_flash"
@export var explode_sound:SoundResource

## Set by the effect: who gets the damage reports
var report_callback:Callable

var _age:float
var _tick_left:float
var _exploded:bool
var _toss_from:Vector2
var _toss_to:Vector2
var _material:ShaderMaterial

## Call in the InstanceResource config callback.
func setup(from:Vector2, to:Vector2, only_visual:bool, report:Callable = Callable())->void:
	_toss_from = from
	_toss_to = to
	visual_only = only_visual
	report_callback = report
	global_position = from

func _ready()->void:
	_age = 0.0
	_tick_left = 0.0
	_exploded = false
	if sprite != null:
		_material = sprite.material as ShaderMaterial
		sprite.texture = idle_texture
		sprite.hframes = maxi(idle_frames, 1)
		sprite.frame = 0
		sprite.scale = Vector2.ONE
		sprite.position.y = 0.0
	if _material != null:
		_material.set_shader_parameter(&"blend", 0.0)
	if damage_channel != null:
		if !damage_channel.update_requested.is_connected(_update_push):
			damage_channel.update_requested.connect(_update_push)
	var _toss:Tween = create_tween()
	_toss.tween_method(_toss_step, 0.0, 1.0, toss_time)
	set_process(true)
	request_ready()

func _toss_step(t:float)->void:
	global_position = _toss_from.lerp(_toss_to, t)
	if sprite != null:
		sprite.position.y = -toss_height * 4.0 * t * (1.0 - t)

func _process(delta:float)->void:
	if _exploded:
		return
	_age += delta
	var _t:float = clampf(_age / fuse_time, 0.0, 1.0)
	var _hot:bool = _age >= fuse_time - hot_time
	if sprite != null:
		var _fps:float = lerpf(fps_start, fps_end, _t)
		if _hot && hot_texture != null:
			if sprite.texture != hot_texture:
				sprite.texture = hot_texture
				sprite.hframes = maxi(hot_frames, 1)
			sprite.frame = int(_age * _fps) % maxi(hot_frames, 1)
			var _pulse:float = 0.5 + 0.5 * sin(_age * TAU * 6.0)
			sprite.scale = Vector2.ONE * lerpf(1.0, throb_scale, _pulse)
		else:
			sprite.frame = int(_age * _fps) % maxi(idle_frames, 1)
		if _material != null:
			_material.set_shader_parameter(&"blend", clampf((_t - 0.6) / 0.4, 0.0, 1.0) * 0.6)
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = lerpf(tick_interval_start, tick_interval_end, _t)
		if tick_sound != null:
			tick_sound.play_pitched(lerpf(tick_pitch_start, tick_pitch_end, _t))
	if _age >= fuse_time:
		explode()

func explode()->void:
	if _exploded:
		return
	_exploded = true
	var _pos:Vector2 = global_position
	if !visual_only && damage_cast != null && damage_channel != null:
		var _data:DamageDataResource = damage_channel.transmission_resource as DamageDataResource
		if _data != null:
			_data.report_callback = report_callback
			_data.hit_list = []
		damage_cast.check_transmission()
	if explosion_vfx != null:
		var _scale:float = explosion_scale
		explosion_vfx.instance(func (n:Node2D)->void:
			n.global_position = _pos
			n.scale = Vector2.ONE * _scale)
	if blast_burst != null:
		blast_burst.instance(func (n:Node2D)->void: n.global_position = _pos)
	if camera_shake != null:
		camera_shake.play()
	if screen_flash != null && screen_flash.node != null && screen_flash.node.has_method(&"play"):
		screen_flash.node.play(screen_flash_animation)
	if explode_sound != null:
		explode_sound.play_managed()
	if pool_node != null:
		pool_node.pool_return()
	else:
		queue_free()

## Closer is pushed harder (like BossSlam)
func _update_push(damage_data:DamageDataResource, receiver:AreaReceiver2D)->void:
	var _comp:Vector2 = Vector2.ONE / axis_multiplication.value if axis_multiplication != null else Vector2.ONE
	var _distance:Vector2 = receiver.global_position - global_position
	var _len:float = (_distance * _comp).length()
	var _t:float = minf(_len / maxf(kickback_radius, 0.001), 1.0)
	damage_data.kickback_strength = lerpf(kickback_max, kickback_min, _t)
	damage_data.direction = _distance.normalized() if _len > 2.0 else Vector2.DOWN
