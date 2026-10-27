## A puddle left on the ground. While an actor stands in it, the zone transmission is sent
## again every interval, so its effects keep refreshing. The puddle disappears after lifetime.
class_name Puddle
extends Node2D

## Area that actors must overlap to be affected
@export var area:Area2D

## Sends the zone transmission to the actors in the area
@export var data_transmitter:DataChannelTransmitter

## Seconds between each transmission while an actor stays in the puddle
@export var interval:float = 0.1

## Seconds before the puddle disappears
@export var lifetime:float = 6.0

var _time:float

func _ready()->void:
	create_tween().tween_callback(queue_free).set_delay(lifetime)

func _physics_process(delta:float)->void:
	_time -= delta
	if _time > 0.0:
		return
	_time = interval
	for _area:Area2D in area.get_overlapping_areas():
		if _area is AreaReceiver2D:
			data_transmitter.send(_area as AreaReceiver2D)
