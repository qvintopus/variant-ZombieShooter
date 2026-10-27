## Puddle: stays for lifetime seconds, then fades out and is removed.
class_name PuddleTrap
extends Node2D

@export var data_transmitter:DataChannelTransmitter

@export var lifetime:float = 60.0

@export var fade_time:float = 3.0

func _ready()->void:
	var _tween:Tween = create_tween()
	_tween.tween_interval(lifetime)
	_tween.tween_property(self, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(data_transmitter.set_enabled.bind(false))
	_tween.tween_callback(queue_free)
