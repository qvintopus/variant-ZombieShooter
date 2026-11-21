## One equipped ability on the player (child of AbilityManager). Holds its
## cooldown / charges at run time. Overrides let a slot tweak the resource.
class_name AbilitySlot
extends Node

signal changed
signal activated
signal refilled
## Cooldown finished / became usable
signal became_ready

@export var ability:AbilityResource
## Input slot (0 = ability_1 action)
@export var slot_index:int = 0

@export_group("Overrides")
## >= 0 replaces the resource's cooldown_time
@export var cooldown_override:float = -1.0
## >= 0 replaces the resource's max_charges
@export var max_charges_override:int = -1
## Multiplies the cooldown (meta upgrades can set it)
@export var cooldown_multiplier:float = 1.0

var cooldown_left:float
var charges:int
var _refill_block:Dictionary = {}
var manager:AbilityManager

func cooldown_time()->float:
	if ability == null:
		return 0.0
	var _base:float = cooldown_override if cooldown_override >= 0.0 else ability.cooldown_time
	return maxf(_base * cooldown_multiplier, 0.0)

func max_charges()->int:
	if ability == null:
		return 0
	return max_charges_override if max_charges_override >= 0 else ability.max_charges

func is_consumable()->bool:
	return ability != null && ability.charge_mode == AbilityResource.ChargeMode.CONSUMABLE

func reset_state()->void:
	cooldown_left = 0.0
	charges = mini(ability.start_charges, max_charges()) if is_consumable() else 0
	changed.emit()

func can_use()->bool:
	if ability == null || ability.effect == null || cooldown_left > 0.0:
		return false
	return !is_consumable() || charges > 0

## 0 = ready, 1 = just used
func cooldown_ratio()->float:
	var _t:float = cooldown_time()
	return clampf(cooldown_left / _t, 0.0, 1.0) if _t > 0.0 else 0.0

func try_use()->bool:
	if !can_use():
		return false
	if !ability.effect.activate(self):
		return false
	cooldown_left = cooldown_time()
	if is_consumable():
		charges -= 1
	activated.emit()
	changed.emit()
	return true

func tick(delta:float)->void:
	if cooldown_left <= 0.0:
		return
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if cooldown_left <= 0.0:
		became_ready.emit()
	changed.emit()

## A refill event (AbilityResource.Refill flag) happened.
func on_trigger(trigger:int)->void:
	if ability == null || (ability.refill_triggers & trigger) == 0:
		return
	var _now:float = Time.get_ticks_msec() * 0.001
	if _now < float(_refill_block.get(trigger, -INF)):
		return
	_refill_block[trigger] = _now + ability.refill_cooldown
	refill(ability.refill_amount)

func refill(amount:float)->void:
	if is_consumable():
		var _before:int = charges
		charges = mini(charges + maxi(int(amount), 1), max_charges())
		if charges == _before:
			return
	else:
		if cooldown_left <= 0.0:
			return
		cooldown_left = 0.0 if amount < 0.0 else maxf(cooldown_left - amount, 0.0)
		if cooldown_left <= 0.0:
			became_ready.emit()
	refilled.emit()
	changed.emit()

## The player body using it
func body()->Node2D:
	return manager.owner as Node2D if manager != null else null

func resource_node()->ResourceNode:
	return manager.resource_node if manager != null else null

## Effects call it to have the teammate copies replay the use.
func send_fx(args:Array)->void:
	if manager != null:
		manager.send_slot_fx(slot_index, args)
