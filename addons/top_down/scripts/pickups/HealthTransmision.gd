class_name HealthTransmision
extends TransmissionResource

@export var value:float

## Tells abilities about it; a full-health touch is taken when one wants it.
@export var pickup_events:PickupEvents

func set_value(_value:float)->void:
	value = _value
	updated.emit()

## Receiver need to provide a reference to a ResourceNode
## Override this function with specific use.
## Should result with a state change
func process(resource_node:ResourceNode)->void:
	var _health_resource:HealthResource = resource_node.get_resource(transmission_name)
	if _health_resource.is_dead:
		failed()
		return
	var _pos:Vector2 = resource_node.owner.global_position if resource_node.owner is Node2D else Vector2.ZERO
	if _health_resource.is_full():
		if pickup_events == null || !pickup_events.wants_wasted_heals():
			failed()
			return
		pickup_events.heal_wasted.emit(value)
		pickup_events.emit_collected(&"health_full", 0, _pos, null)
		success()
		return
	_health_resource.add_hp(value)
	if pickup_events != null:
		pickup_events.emit_collected(&"health", int(value), _pos, null)
	success()
