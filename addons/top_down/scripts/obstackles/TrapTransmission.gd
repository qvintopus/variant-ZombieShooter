## Template transmission for traps. Sent by a trap's AreaTransmitter2D when an
## AreaReceiver2D with a DataChannelReceiver named "trap" enters it (player).
## Sets the receiver's BoolResource named effect_name to true, a node on the
## receiver reacts to it (like HoleTransmission -> HoleTrigger).
class_name TrapTransmission
extends TransmissionResource

## Name of the BoolResource in receiver's ResourceNode, e.g. "stuck". Empty does nothing.
@export var effect_name:StringName

## Keep sending every physics frame while the receiver overlaps (puddles).
## Receiver's effect node gets changed_true each frame and resets the bool.
@export var repeat_while_inside:bool

## BoolResource that was set on the receiver.
## Trap can read it from DataChannelTransmitter.update_requested.
var effect_resource:BoolResource

## Receiver need to provide a reference to a ResourceNode
## Override this function with specific use.
## Should result with a state change
func process(resource_node:ResourceNode)->void:
	var _effect_bool:BoolResource = resource_node.get_resource(effect_name)
	if _effect_bool == null:
		failed()
		return
	_effect_bool.set_value(true)
	effect_resource = _effect_bool
	update_requested.emit()
	if repeat_while_inside:
		# DataChannelTransmitter sends again next physics frame if still overlapping
		try_again()
		return
	success()
