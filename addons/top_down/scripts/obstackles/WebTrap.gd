## Spider web: catches once, disappears when the caught actor is free or when shot.
class_name WebTrap
extends Node2D

@export var data_transmitter:DataChannelTransmitter

## Receives damage from player projectiles
@export var damage_receiver:DataChannelReceiver

@export var fade_time:float = 0.2

## When above 0, removed after this time even if nothing got caught (thrown webs)
@export var lifetime:float = 0.0

## "stuck" BoolResource of the caught actor
var effect_resource:BoolResource
var is_removed:bool

func _ready()->void:
	data_transmitter.update_requested.connect(_on_update_requested)
	damage_receiver.transmission_received.connect(_on_damaged)
	if lifetime > 0.0:
		create_tween().tween_callback(remove).set_delay(lifetime)

func _on_update_requested(transmission_resource:TransmissionResource, _receiver:AreaReceiver2D)->void:
	if !(transmission_resource is TrapTransmission):
		return
	# Catch only once
	data_transmitter.set_enabled(false)
	effect_resource = transmission_resource.effect_resource
	effect_resource.changed_false.connect(remove, CONNECT_ONE_SHOT)

func _on_damaged(_transmission_resource:TransmissionResource)->void:
	remove()

func remove()->void:
	if is_removed:
		return
	is_removed = true
	data_transmitter.set_enabled(false)
	damage_receiver.set_enabled(false)
	# Shot while holding someone - let go
	if effect_resource != null && effect_resource.value:
		effect_resource.set_value(false)

	var _tween:Tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(queue_free)
