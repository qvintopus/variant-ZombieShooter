## An ability's rules: how it's limited (cooldown or charges) and what refills it.
## The effect (what it does) is a separate AbilityEffect resource.
class_name AbilityResource
extends Resource

enum ChargeMode {
	## Usable again after cooldown_time
	COOLDOWN,
	## Uses charges; refills add charges
	CONSUMABLE,
}

## Events that refill the ability (flags)
enum Refill {
	DAMAGE_DEALT = 1,
	KILL = 2,
	HEALTH_AT_FULL = 4,
	COIN_PICKUP = 8,
}

@export var id:StringName
@export var display_name:String
@export var icon:Texture2D
@export var effect:AbilityEffect

@export_group("Limit")
@export var charge_mode:ChargeMode = ChargeMode.COOLDOWN
## COOLDOWN: seconds between uses. CONSUMABLE: minimum seconds between uses.
@export var cooldown_time:float = 6.0
## CONSUMABLE: charge cap
@export var max_charges:int = 3
## CONSUMABLE: charges at the start of a run
@export var start_charges:int = 3

@export_group("Refill")
@export_flags("Damage dealt:1", "Kill:2", "Health at full:4", "Coin pickup:8") var refill_triggers:int = 0
## COOLDOWN: seconds taken off the cooldown (-1 = reset it fully).
## CONSUMABLE: charges added.
@export var refill_amount:float = -1.0
## Seconds a trigger can't refill again (damage ticks come fast)
@export var refill_cooldown:float = 0.0
