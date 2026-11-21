## The player's abilities: AbilitySlot children, input, refill events.
## On a teammate copy it only replays uses (PlayerFx "ability").
class_name AbilityManager
extends Node

signal slots_changed

@export var enabled:bool = true
@export var resource_node:ResourceNode
@export var pickup_events:PickupEvents
## Keeps charges / cooldowns between rooms and in the run save
@export var store:AbilityChargesResource

var fx_kind:StringName = &"ability"
var slots:Array[AbilitySlot] = []
var _remote:bool
var _input:InputResource
var _damage:DamageResource

func _ready()->void:
	_remote = PlayerFx.is_remote(self)
	slots.clear()
	for _child:Node in get_children():
		if _child is AbilitySlot:
			var _slot:AbilitySlot = _child
			_slot.manager = self
			slots.append(_slot)
			if _slot.ability != null:
				_slot.reset_state()
				if !_remote:
					_restore(_slot)
					if !_slot.changed.is_connected(_remember):
						_slot.changed.connect(_remember.bind(_slot))
	set_physics_process(!_remote)
	if !_remote:
		_input = resource_node.get_resource("input")
		_damage = resource_node.get_resource("damage")
		if _input != null && !_input.ability_pressed.is_connected(_on_ability_pressed):
			_input.ability_pressed.connect(_on_ability_pressed)
		if _damage != null && !_damage.report_damage.is_connected(_on_damage_reported):
			_damage.report_damage.connect(_on_damage_reported)
		if pickup_events != null:
			if !pickup_events.collected.is_connected(_on_collected):
				pickup_events.collected.connect(_on_collected)
			if _wants(AbilityResource.Refill.HEALTH_AT_FULL) && !pickup_events.heal_wasted.is_connected(_on_heal_wasted):
				pickup_events.heal_wasted.connect(_on_heal_wasted)
	if !tree_exiting.is_connected(_disconnect):
		tree_exiting.connect(_disconnect, CONNECT_ONE_SHOT)
	slots_changed.emit()
	request_ready()

func _disconnect()->void:
	if _input != null && _input.ability_pressed.is_connected(_on_ability_pressed):
		_input.ability_pressed.disconnect(_on_ability_pressed)
	if _damage != null && _damage.report_damage.is_connected(_on_damage_reported):
		_damage.report_damage.disconnect(_on_damage_reported)
	if pickup_events != null:
		if pickup_events.collected.is_connected(_on_collected):
			pickup_events.collected.disconnect(_on_collected)
		if pickup_events.heal_wasted.is_connected(_on_heal_wasted):
			pickup_events.heal_wasted.disconnect(_on_heal_wasted)

func _restore(slot:AbilitySlot)->void:
	if store == null:
		return
	var _id:String = String(slot.ability.id)
	if slot.is_consumable() && store.charges.has(_id):
		slot.charges = clampi(int(store.charges[_id]), 0, slot.max_charges())
	if store.cooldowns.has(_id):
		slot.cooldown_left = clampf(float(store.cooldowns[_id]), 0.0, slot.cooldown_time())
	_remember(slot)

func _remember(slot:AbilitySlot)->void:
	if store == null:
		return
	var _id:String = String(slot.ability.id)
	if slot.is_consumable():
		store.charges[_id] = slot.charges
	store.cooldowns[_id] = slot.cooldown_left

func _wants(trigger:int)->bool:
	for _slot:AbilitySlot in slots:
		if _slot.ability != null && (_slot.ability.refill_triggers & trigger) != 0:
			return true
	return false

func slot(index:int)->AbilitySlot:
	for _slot:AbilitySlot in slots:
		if _slot.slot_index == index:
			return _slot
	return null

func _physics_process(delta:float)->void:
	for _slot:AbilitySlot in slots:
		_slot.tick(delta)

func _on_ability_pressed(index:int)->void:
	if !enabled:
		return
	var _slot:AbilitySlot = slot(index)
	if _slot != null:
		_slot.try_use()

func trigger(flag:int)->void:
	for _slot:AbilitySlot in slots:
		_slot.on_trigger(flag)

func _on_damage_reported(data:DamageDataResource)->void:
	# an ability's own damage doesn't refill abilities
	if data.source_tag == &"ability":
		return
	if data.total_damage > 0.0:
		trigger(AbilityResource.Refill.DAMAGE_DEALT)
	if data.is_kill:
		trigger(AbilityResource.Refill.KILL)

func _on_collected(id:StringName, _amount:int, _pos:Vector2, _sound:SoundResource, _label:String)->void:
	if id == &"coin":
		trigger(AbilityResource.Refill.COIN_PICKUP)

func _on_heal_wasted(_amount:float)->void:
	trigger(AbilityResource.Refill.HEALTH_AT_FULL)

## Charges of consumable abilities {id: charges} (run save).
func capture_charges()->Dictionary:
	var _data:Dictionary = {}
	for _slot:AbilitySlot in slots:
		if _slot.is_consumable() && _slot.ability.id != &"":
			_data[String(_slot.ability.id)] = _slot.charges
	return _data

func apply_charges(data:Dictionary)->void:
	for _slot:AbilitySlot in slots:
		if _slot.is_consumable() && data.has(String(_slot.ability.id)):
			_slot.charges = clampi(int(data[String(_slot.ability.id)]), 0, _slot.max_charges())
			_slot.changed.emit()

func send_slot_fx(index:int, args:Array)->void:
	PlayerFx.send(fx_kind, [index, args])

## Teammate copy: [slot_index:int, args:Array]
func play_remote_fx(args:Array)->void:
	if args.size() != 2 || typeof(args[0]) != TYPE_INT || typeof(args[1]) != TYPE_ARRAY:
		return
	var _slot:AbilitySlot = slot(args[0])
	if _slot != null && _slot.ability != null && _slot.ability.effect != null:
		_slot.ability.effect.play_remote(_slot, args[1])
