## HUD for one ability slot of the local player: icon, cooldown pie, charges,
## key hint, pop + flash when it becomes ready or refills.
class_name AbilitySlotUI
extends Control

@export var player_reference:ReferenceNodeResource
@export var slot_index:int = 0
@export var icon:TextureRect
@export var pie:CooldownPie
@export var count_label:Label
@export var key_label:Label
@export var action_resource:ActionResource
## Hide when the slot is empty
@export var hide_when_empty:bool = true

@export_group("Feedback")
@export var ready_pop_scale:float = 1.3
@export_range(0.01, 1.0, 0.01) var ready_pop_time:float = 0.18
@export var ready_flash:Color = Color(2.0, 2.0, 2.0, 1.0)
@export var unusable_tint:Color = Color(0.55, 0.55, 0.6, 1.0)

var _slot:AbilitySlot
var _manager:AbilityManager
var _tween:Tween

func _ready()->void:
	pivot_offset = size * 0.5
	if player_reference != null:
		player_reference.listen(self, _on_player_changed)
	else:
		_refresh()

func _on_player_changed()->void:
	_bind(null)
	var _player:Node = player_reference.node if player_reference != null else null
	if _player == null || !is_instance_valid(_player):
		_refresh()
		return
	_manager = _player.get_node_or_null("AbilityManager") as AbilityManager
	if _manager == null:
		_refresh()
		return
	if !_manager.is_node_ready():
		await _manager.ready
	_bind(_manager.slot(slot_index))

func _bind(slot:AbilitySlot)->void:
	if _slot != null && is_instance_valid(_slot):
		if _slot.changed.is_connected(_refresh):
			_slot.changed.disconnect(_refresh)
			_slot.became_ready.disconnect(_pop)
			_slot.refilled.disconnect(_pop)
	_slot = slot
	if _slot != null:
		_slot.changed.connect(_refresh)
		_slot.became_ready.connect(_pop)
		_slot.refilled.connect(_pop)
	_refresh()

func _refresh()->void:
	var _has:bool = _slot != null && is_instance_valid(_slot) && _slot.ability != null
	visible = _has || !hide_when_empty
	if !_has:
		return
	if icon != null:
		icon.texture = _slot.ability.icon
		icon.modulate = Color.WHITE if _slot.can_use() else unusable_tint
	if pie != null:
		pie.value = _slot.cooldown_ratio()
	if count_label != null:
		count_label.visible = _slot.is_consumable()
		count_label.text = str(_slot.charges)
	if key_label != null && action_resource != null:
		var _event:InputEvent = action_resource.ability_1_kb
		key_label.text = _event.as_text().get_slice(" ", 0) if _event != null else ""

func _pop()->void:
	if _tween != null:
		_tween.kill()
	pivot_offset = size * 0.5
	scale = Vector2.ONE * ready_pop_scale
	modulate = ready_flash
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, ^"scale", Vector2.ONE, ready_pop_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"modulate", Color.WHITE, ready_pop_time)
