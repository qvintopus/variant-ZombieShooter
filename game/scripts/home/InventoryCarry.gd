## What the player holds between runs: the run-scoped currencies (coins, meat,
## slime; InventoryItemDef.run_scoped) and where their stacks sat. Captured on an
## extract (VictoryScreen) and while in the home base (HomeBase.save_state), put
## back after the run-state reset in the home base and at a run start
## (FreshStart, which uses it up: a lost run loses it). With the stash lever on
## (meta upgrade) a run start first moves the auto_stash items into the chest.
## Weapons keep their own way home (HomeBaseResource.stash_inventory).
class_name InventoryCarry
extends RefCounted

## Meta stat that builds the stash lever next to the home chest
const LEVER_STAT:String = "stash_lever"

static func capture(home:HomeBaseResource, grid:InventoryGridResource)->void:
	if home == null || grid == null || grid.database == null:
		return
	var _carried:Dictionary = {}
	for _def:InventoryItemDef in grid.database.currencies():
		if _def.run_scoped && _def.counter != null && _def.counter.value > 0:
			_carried[String(_def.id)] = _def.counter.value
	home.carried = _carried
	var _layout:PackedStringArray = grid.save_layout()
	for _i:int in _layout.size():
		if _layout[_i].begins_with(InventoryGridResource.WEAPON_PREFIX):
			_layout[_i] = ""
	home.carried_layout = _layout


## Gives the carried amounts back (the counters were just reset) and lays the
## stacks out as they were.
static func apply(home:HomeBaseResource, grid:InventoryGridResource)->void:
	if home == null || grid == null || grid.database == null:
		return
	for _id:Variant in home.carried:
		var _def:InventoryItemDef = grid.database.def(StringName(_id))
		var _amount:int = int(home.carried[_id])
		if _def != null && _def.run_scoped && _def.counter != null && _amount > 0:
			_def.counter.refund(_amount)
	grid.load_layout(home.carried_layout, null)

static func has_any(home:HomeBaseResource)->bool:
	return home != null && !home.carried.is_empty()

static func lever_built(meta:MetaUpgradeResource)->bool:
	return meta != null && meta.stat(LEVER_STAT) > 0.0

static func lever_on(home:HomeBaseResource, meta:MetaUpgradeResource)->bool:
	return home != null && home.auto_stash && lever_built(meta)

## Moves the carried auto_stash items into the chest (as much as fits, the rest
## stays carried). Returns how much moved.
static func auto_stash(home:HomeBaseResource, chest:InventoryGridResource, weapon_database:ItemCollectionResource)->int:
	if home == null || chest == null || chest.database == null:
		return 0
	chest.load_layout(home.chest, weapon_database)
	var _moved:int = 0
	for _id:Variant in home.carried.keys():
		var _def:InventoryItemDef = chest.database.def(StringName(_id))
		if _def == null || !_def.auto_stash:
			continue
		var _put:int = chest.add_amount(_def.id, int(home.carried[_id]))
		_moved += _put
		var _left:int = int(home.carried[_id]) - _put
		if _left > 0:
			home.carried[_id] = _left
		else:
			home.carried.erase(_id)
	home.chest = chest.save_layout()
	return _moved
