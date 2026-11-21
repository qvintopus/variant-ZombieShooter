## Zoom-in + slight tilt on loot moments: a loot chest opening, a slot machine
## paying out. Owns the camera's zoom and rotation (the shake owns its offset).
## Contraptions run per machine, so this only ever plays for the local player.
class_name CameraPunch
extends Node

@export var enabled:bool = true
@export var camera_reference:ReferenceNodeResource
## Loot chest opened (any drop)
@export var chest:CameraPunchPreset
## Slot machine paid out a weapon
@export var jackpot:CameraPunchPreset
## Slot machine paid out anything else (a bust plays nothing)
@export var spin:CameraPunchPreset

## Number of punches started, for tests.
var played:int
var last_preset:CameraPunchPreset

var _tween:Tween
var _camera:Camera2D
var _base_zoom:Vector2 = Vector2.ONE

func _ready()->void:
	_connect_contraptions.call_deferred()

func _connect_contraptions()->void:
	for _node:Node in get_tree().get_nodes_in_group(Interactable.ALL_GROUP):
		if _node is SlotMachine && !_node.paid_out.is_connected(_on_paid_out):
			_node.paid_out.connect(_on_paid_out.bind(_node))

func _on_paid_out(drop:String, _amount:int, _weapon:ItemResource, machine:SlotMachine)->void:
	if machine is LootBox:
		play(chest)
	elif drop == "weapon":
		play(jackpot)
	elif drop != "nothing":
		play(spin)

func play(preset:CameraPunchPreset)->void:
	if !enabled || preset == null || !preset.enabled:
		return
	var _target:Camera2D = _find_camera()
	if _target == null:
		return
	played += 1
	last_preset = preset
	if _tween != null && _tween.is_valid():
		_tween.kill()
	else:
		_base_zoom = _target.zoom
	_target.ignore_rotation = false
	var _tilt:float = deg_to_rad(preset.tilt_deg) * (1.0 if randf() < 0.5 else -1.0)
	_tween = create_tween()
	if preset.delay > 0.0:
		_tween.tween_interval(preset.delay)
	_tween.set_parallel(true)
	_tween.tween_property(_target, "zoom", _base_zoom * preset.zoom_mult, preset.in_time).set_trans(preset.in_trans).set_ease(preset.in_ease)
	_tween.tween_property(_target, "rotation", _tilt, preset.in_time).set_trans(preset.in_trans).set_ease(preset.in_ease)
	_tween.set_parallel(false)
	_tween.tween_interval(preset.hold_time)
	_tween.set_parallel(true)
	_tween.tween_property(_target, "zoom", _base_zoom, preset.out_time).set_trans(preset.out_trans).set_ease(preset.out_ease)
	_tween.tween_property(_target, "rotation", 0.0, preset.out_time).set_trans(preset.out_trans).set_ease(preset.out_ease)

## True while a punch is moving the camera.
func is_playing()->bool:
	return _tween != null && _tween.is_valid() && _tween.is_running()

func _find_camera()->Camera2D:
	if camera_reference != null && camera_reference.node != null && is_instance_valid(camera_reference.node):
		_camera = camera_reference.node as Camera2D
	if _camera == null || !is_instance_valid(_camera):
		_camera = get_viewport().get_camera_2d() if get_viewport() != null else null
	return _camera

func _exit_tree()->void:
	if _tween != null && _tween.is_valid():
		_tween.kill()
	if _camera != null && is_instance_valid(_camera):
		_camera.zoom = _base_zoom
		_camera.rotation = 0.0
