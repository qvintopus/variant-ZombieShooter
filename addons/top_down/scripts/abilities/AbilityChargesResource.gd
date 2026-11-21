## Run state of the local player's abilities, kept across rooms (the player
## node is rebuilt per room). Charges are saved with the run (PlayerRunData);
## cooldowns only carry between rooms.
class_name AbilityChargesResource
extends Resource

## ability id (String) -> charges left
var charges:Dictionary = {}
## ability id (String) -> seconds of cooldown left
var cooldowns:Dictionary = {}

func reset()->void:
	charges.clear()
	cooldowns.clear()
