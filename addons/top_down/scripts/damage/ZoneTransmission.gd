## Transmission for zones (webs, puddles). Applies timed effects to the actor inside.
## Set only the effects a zone needs, leave the rest at zero.
class_name ZoneTransmission
extends TransmissionResource

## Seconds the actor is stuck in place
@export var stuck_time:float

## Seconds of slowed movement, refreshed while the actor stays in the zone
@export var slow_time:float

## Movement speed factor used while slowed
@export_range(0.0, 1.0) var slow_factor:float = 1.0

## Seconds of poison, refreshed while the actor stays in the zone
@export var poison_time:float

## Damage taken every second while poisoned
@export var poison_damage:float

func process(resource_node:ResourceNode)->void:
	var _zone:ZoneEffectResource = resource_node.get_resource("zone")
	if _zone == null:
		failed()
		return
	_zone.apply(stuck_time, slow_time, slow_factor, poison_time, poison_damage)
	success()
