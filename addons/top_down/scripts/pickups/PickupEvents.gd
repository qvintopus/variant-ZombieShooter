## Global bus for things the local player picks up (abilities, juice, texts).
class_name PickupEvents
extends Resource

## The local player took a pickup. `sound`: its collect sound (a listener with
## `sound_owner` set plays it, else the pickup does). `label`: display name override.
signal collected(id:StringName, amount:int, pos:Vector2, sound:SoundResource, label:String)

## A health pickup was touched at full health.
signal heal_wasted(amount:float)

## Set by the node that plays collect sounds itself (PickupJuice).
var sound_owner:Object

func has_sound_owner()->bool:
	return sound_owner != null && is_instance_valid(sound_owner)

func emit_collected(id:StringName, amount:int, pos:Vector2, sound:SoundResource, label:String = "")->void:
	if sound != null && !has_sound_owner():
		sound.play_managed()
	collected.emit(id, amount, pos, sound, label)

## True when something (an ability) wants full-health pickups taken.
func wants_wasted_heals()->bool:
	return !heal_wasted.get_connections().is_empty()
