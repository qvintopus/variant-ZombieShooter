## Ground slam around the boss: damage and push away everything in a radius, like BigJellyJumpDamage landing.
class_name BossSlam
extends BossAttack

@export var damage_transmitter:ShapeCastTransmitter2D

## Push without damage, also moves other enemies away
@export var push_transmitter:ShapeCastTransmitter2D

@export var push_channel_transmitter:DataChannelTransmitter

@export var axis_multiplication:Vector2Resource

@export var kickback_radius:float = 48.0

@export var kickback_max:float = 160.0

@export var kickback_min:float = 60.0

@export var vfx:InstanceResource

@export var sound:SoundResource

@export var camera_shake:CameraShakeResource

var axis_compensation:Vector2

func _ready()->void:
	axis_compensation = Vector2.ONE / axis_multiplication.value
	if !push_channel_transmitter.update_requested.is_connected(_update_push):
		push_channel_transmitter.update_requested.connect(_update_push)

func perform()->void:
	damage_transmitter.check_transmission()
	push_transmitter.check_transmission()
	var _pos:Vector2 = damage_transmitter.global_position
	if vfx != null:
		vfx.instance(func (inst:Node2D)->void: inst.global_position = _pos)
	if sound != null:
		sound.play_managed()
	if camera_shake != null:
		camera_shake.play()

## Closer is pushed harder
func _update_push(damage_data:DamageDataResource, receiver:AreaReceiver2D)->void:
	var _distance:Vector2 = receiver.global_position - push_transmitter.global_position
	var _distance_length:float = (_distance * axis_compensation).length()
	var _t:float = minf(_distance_length / kickback_radius, 1.0)
	damage_data.kickback_strength = lerpf(kickback_max, kickback_min, _t)
	damage_data.direction = _distance.normalized() if _distance_length > 2.0 else Vector2.DOWN
