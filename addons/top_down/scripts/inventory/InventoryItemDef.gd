## What an item is in the inventory grid: its icon, how much fits in one cell.
## Add a .tres per new collectible and list it in the InventoryDatabase.
class_name InventoryItemDef
extends Resource

enum Kind { CURRENCY, WEAPON }

## Loot id (LootItems / PickupEvents), e.g. "meat"
@export var id:StringName
@export var display_name:String
@export var icon:Texture2D
@export var kind:Kind = Kind.CURRENCY
## Amount one cell holds; 0 = no limit (always one cell)
@export_range(0, 99999, 1) var stack_size:int = 999
## Counter holding the amount (currencies)
@export var counter:ScoreResource
## Lower = placed first
@export var sort_order:int
## Keeps its cell even at 0 (coins)
@export var show_when_zero:bool
## Run-scoped counter (reset on a run start): the amount is carried home and into
## the next run (InventoryCarry). Off for meta counters that persist anyway.
@export var run_scoped:bool = true
## Moved into the home chest at a run start while the stash lever is on
@export var auto_stash:bool

func is_infinite()->bool:
	return stack_size <= 0

func amount()->int:
	return counter.value if counter != null else 0

## Cells needed for an amount
func stacks_for(value:int)->int:
	if value <= 0:
		return 1 if show_when_zero else 0
	if is_infinite():
		return 1
	return ceili(float(value) / float(stack_size))
