## Saved meta progress: which upgrade nodes are bought with boss crystals.
## The graph itself (costs, requires, effects) comes from MetaUpgrades / upgrades.json.
class_name MetaUpgradeResource
extends SaveableResource

signal updated

enum State {LOCKED, AVAILABLE, OWNED}

## Saved: bought node ids, every tree in one list. Tree roots are always owned and never listed.
@export var owned:PackedStringArray = []
## Saved: owned nodes switched off; their effects don't count, they still unlock their children.
@export var disabled:PackedStringArray = []

func is_owned(id:String)->bool:
	return MetaUpgrades.is_root(id) || owned.has(id)

## Owned and not switched off.
func is_enabled(id:String)->bool:
	return is_owned(id) && !disabled.has(id)

## Owned non-root node of a toggleable tree.
func can_toggle(id:String)->bool:
	return owned.has(id) && MetaUpgrades.is_toggleable(MetaUpgrades.tree_of(id))

## Switches an owned node off or on; false when it can't be toggled.
func toggle(id:String)->bool:
	if !can_toggle(id):
		return false
	if disabled.has(id):
		disabled.remove_at(disabled.find(id))
	else:
		disabled.append(id)
	save_resource()
	updated.emit()
	return true

## Owned toggleable nodes of one tree.
func toggleable_in(tree:String)->Array:
	return MetaUpgrades.nodes_in(tree).filter(can_toggle)

## True when any of them is on: "All off" then, else "All on".
func any_enabled_in(tree:String)->bool:
	return toggleable_in(tree).any(func (id:String)->bool: return !disabled.has(id))

## Switches every owned node of a toggleable tree on or off.
func set_tree_enabled(tree:String, on:bool)->void:
	for _id:String in toggleable_in(tree):
		var _at:int = disabled.find(_id)
		if on && _at >= 0:
			disabled.remove_at(_at)
		elif !on && _at < 0:
			disabled.append(_id)
	save_resource()
	updated.emit()

## OWNED, AVAILABLE once any required node is owned, otherwise LOCKED.
func state(id:String)->State:
	if is_owned(id):
		return State.OWNED
	for _required:String in MetaUpgrades.requires(id):
		if is_owned(_required):
			return State.AVAILABLE
	return State.LOCKED

func can_buy(id:String)->bool:
	return state(id) == State.AVAILABLE && LootItems.can_afford(MetaUpgrades.cost(id))

## Pays the node's cost and owns it; false and nothing changes when it can't.
func buy(id:String)->bool:
	if !can_buy(id) || !LootItems.pay(MetaUpgrades.cost(id)):
		return false
	owned.append(id)
	save_resource()
	updated.emit()
	return true

## Gives back everything spent, in every tree, and keeps only the roots.
func refund_all()->void:
	for _id:String in owned:
		for _entry:Dictionary in MetaUpgrades.cost(_id):
			var _counter:ScoreResource = LootItems.counter(_entry.get("item", ""))
			if _counter != null:
				_counter.refund(int(_entry.get("amount", 1)))
	owned = []
	disabled = []
	save_resource()
	updated.emit()

## Sum of a stat over every owned, switched-on node, in every tree.
func stat(key:String)->float:
	var _total:float = 0.0
	for _id:String in MetaUpgrades.nodes():
		if is_enabled(_id):
			_total += float(MetaUpgrades.effects(_id).get(key, 0.0))
	return _total

func reset_resource()->void:
	owned = []
	disabled = []
	updated.emit()

func prepare_save()->Resource:
	var _data:MetaUpgradeResource = MetaUpgradeResource.new()
	_data.owned = owned.duplicate()
	_data.disabled = disabled.duplicate()
	return _data

func prepare_load(data:Resource)->void:
	owned = data.owned.duplicate()
	disabled = data.disabled.duplicate() if "disabled" in data else PackedStringArray()
	updated.emit()
