## What an ability does when used. Override activate(); return false when it
## couldn't happen (then no cooldown/charge is spent).
class_name AbilityEffect
extends Resource

func activate(_slot:AbilitySlot)->bool:
	return true

## Teammate copy: replay the look of a use. `args` from activate's fx_args().
func play_remote(_slot:AbilitySlot, _args:Array)->void:
	pass
