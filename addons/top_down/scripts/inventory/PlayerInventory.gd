## The local player's inventory grid: sizes it from meta upgrades, keeps currency
## stacks in step with their counters, says whether a pickup still fits and puts
## weapons beyond the quick slots into the backpack. Local only (RemotePlayer
## strips it): each machine checks its own player's pickups.
class_name PlayerInventory
extends Node

const GROUP:StringName = &"player_inventory"

signal rejected(id:StringName)

@export var enabled:bool = true
@export var grid:InventoryGridResource
@export var resource_node:ResourceNode
## Permanent upgrades (inventory_width / inventory_height stats)
@export var meta_upgrade_resource:MetaUpgradeResource
@export var width_stat:StringName = &"inventory_width"
@export var height_stat:StringName = &"inventory_height"
## Dropped weapons lie here as pickups
@export var item_pickup_instance_resource:InstanceResource

@export_group("Full feedback")
@export var text_instance:InstanceResource
@export var settings:DamageNumbersSettings
@export var full_text:String = "Full"
@export var full_color:Color = Color(1.0, 0.45, 0.35)
@export var text_offset:Vector2 = Vector2(0.0, -20.0)
## Seconds between "Full" texts
@export_range(0.1, 10.0, 0.1) var full_text_interval:float = 1.5

var _bound:Array[ScoreResource] = []
var _next_full_text:float

func _ready()->void:
	if !enabled || grid == null:
		return
	add_to_group(GROUP)
	var _w:int = 0
	var _h:int = 0
	if meta_upgrade_resource != null:
		_w = int(meta_upgrade_resource.stat(width_stat))
		_h = int(meta_upgrade_resource.stat(height_stat))
	grid.set_extra(_w, _h)
	_bind_counters()
	grid.relayout()
	tree_exiting.connect(_unbind, CONNECT_ONE_SHOT)
	request_ready()

func _bind_counters()->void:
	if grid.database == null:
		return
	for _def:InventoryItemDef in grid.database.currencies():
		if _def.counter != null && !_def.counter.updated.is_connected(_on_counter):
			_def.counter.updated.connect(_on_counter)
			_bound.append(_def.counter)

func _unbind()->void:
	for _counter:ScoreResource in _bound:
		if _counter.updated.is_connected(_on_counter):
			_counter.updated.disconnect(_on_counter)
	_bound.clear()

func _on_counter()->void:
	grid.relayout()

## The local player's inventory, or null (then everything fits).
static func local(tree:SceneTree)->PlayerInventory:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as PlayerInventory

## Room for a pickup on this machine's player?
static func accepts(tree:SceneTree, id:StringName, amount:int = 1)->bool:
	var _inv:PlayerInventory = local(tree)
	return _inv == null || _inv.can_accept(id, amount)

func can_accept(id:StringName, amount:int = 1)->bool:
	return grid == null || grid.can_accept(id, amount)

## A pickup that didn't fit: throttled "Full" over the player.
func reject(id:StringName)->void:
	rejected.emit(id)
	var _t:float = Time.get_ticks_msec() * 0.001
	if _t < _next_full_text || text_instance == null:
		return
	_next_full_text = _t + full_text_interval
	var _body:Node2D = owner as Node2D
	if _body == null:
		return
	var _size:int = settings.font_size() if settings != null else 8
	var _text:String = full_text
	var _color:Color = full_color
	text_instance.instance(func (inst:Node2D)->void:
		inst.global_position = _body.global_position + text_offset
		(inst as FloatingText).setup(_text, _color, _size))

## Weapon into the backpack; false when no cell is free.
func stash_weapon(item:ItemResource)->bool:
	return grid != null && grid.put_weapon(item)

## Drops a backpack weapon on the floor at the player's feet.
func drop_weapon(cell:int)->void:
	var _item:ItemResource = grid.take_weapon(cell) if grid != null else null
	if _item == null:
		return
	spawn_dropped(_item)

func spawn_dropped(item:ItemResource)->void:
	var _body:Node2D = owner as Node2D
	if item_pickup_instance_resource == null || _body == null:
		return
	var _at:Vector2 = _body.global_position
	item_pickup_instance_resource.instance(func (inst:ItemPickup)->void:
		inst.item_resource = item
		inst.global_position = _at
		# co-op: a guest's drop goes to the host, who owns what lies on the floor
		inst.set_meta(&"player_drop", true))
