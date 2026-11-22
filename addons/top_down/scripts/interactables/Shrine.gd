## Healing shrine: each use brings the player back to full health, up to
## `max_uses` times a run. Refused at full health, so no use is wasted.
## Co-op: one shared pool of uses, counted by the host (NetShrines).
## Sprite strip: hframes = uses left (0 = spent ... 3), vframes = tier (max_uses).
class_name Shrine
extends Interactable

signal healed(amount:float)

@export_range(1, 3) var max_uses:int = 1:
	set(value):
		max_uses = clampi(value, 1, 3)
		_refresh()
## Off: heal `heal_amount` instead of up to full
@export var heal_full:bool = true
@export var heal_amount:float = 10.0
@export var room_state_resource:RoomStateResource
@export var pickup_events:PickupEvents
@export var sprite:Sprite2D
@export var preset:ShrinePreset
@export var sound_heal:SoundResource

const FRAMES_PER_TIER:int = 4

var _time:float
var _fx_tween:Tween

func _ready()->void:
	super._ready()
	if room_state_resource != null && !room_state_resource.shrine_changed.is_connected(_on_shrine_changed):
		room_state_resource.shrine_changed.connect(_on_shrine_changed)
	_refresh()
	if Net.is_guest():
		Net.shrines.request_sync(shrine_key())

## "<room scene>:<node name>", unique per shrine for the run.
func shrine_key()->String:
	var _room:Node = owner if owner != null else get_parent()
	return "%s:%s" % [_room.scene_file_path, name]

func uses_left()->int:
	var _used:int = room_state_resource.shrine_used_count(shrine_key()) if room_state_resource != null else 0
	return maxi(max_uses - _used, 0)

func _on_shrine_changed(key:String)->void:
	if key == shrine_key():
		_refresh()

func _refresh()->void:
	if sprite == null || !is_inside_tree():
		return
	sprite.frame = (max_uses - 1) * FRAMES_PER_TIER + uses_left()
	if uses_left() == 0 && preset != null:
		sprite.self_modulate = preset.spent_color

func _process(delta:float)->void:
	super._process(delta)
	if preset == null || sprite == null || uses_left() == 0 || (_fx_tween != null && _fx_tween.is_running()):
		return
	_time += delta
	var _t:float = (sin(_time * TAU * preset.pulse_speed) + 1.0) * 0.5
	sprite.self_modulate = Color.WHITE.lerp(preset.glow_color * (1.0 + preset.pulse_amount), _t * preset.pulse_amount * 2.0)

func _health()->HealthResource:
	var _player:Node = player_reference.node if player_reference != null else null
	if _player == null || !is_instance_valid(_player):
		return null
	var _resources:ResourceNode = _player.get_node_or_null("ResourceNode") as ResourceNode
	return _resources.get_resource("health") as HealthResource if _resources != null else null

func _is_down()->bool:
	var _player:Node = player_reference.node if player_reference != null else null
	if _player == null:
		return false
	for _child:Node in _player.get_children():
		if _child is Downed && (_child as Downed).is_down:
			return true
	return false

func _can_use()->bool:
	var _health:HealthResource = _health()
	return uses_left() > 0 && _health != null && !_health.is_dead && !_is_down() && !_health.is_full()

func _use()->void:
	if Net.is_guest():
		busy = true
		Net.shrines.request_use(shrine_key(), max_uses, _on_granted)
		return
	room_state_resource.set_shrine_used(shrine_key(), room_state_resource.shrine_used_count(shrine_key()) + 1)
	Net.shrines.broadcast(shrine_key())
	_heal()

func _on_granted(granted:bool)->void:
	busy = false
	if granted:
		_heal()
	else:
		deny()

func _heal()->void:
	var _health:HealthResource = _health()
	if _health == null || _health.is_dead:
		return
	var _amount:float = _health.max_hp - _health.hp if heal_full else heal_amount
	_amount = minf(_amount, _health.max_hp - _health.hp)
	_health.add_hp(_amount)
	var _player:Node2D = player_reference.node as Node2D
	if pickup_events != null && _player != null:
		pickup_events.emit_collected(&"health", int(round(_amount)), _player.global_position, sound_heal)
	elif sound_heal != null:
		sound_heal.play_managed()
	_play_fx()
	healed.emit(_amount)

func _play_fx()->void:
	if preset == null || sprite == null:
		return
	if _fx_tween != null:
		_fx_tween.kill()
	sprite.self_modulate = preset.flash_color
	sprite.scale = preset.punch_scale
	_fx_tween = create_tween().set_parallel(true)
	var _end:Color = preset.spent_color if uses_left() == 0 else Color.WHITE
	_fx_tween.tween_property(sprite, ^"self_modulate", _end, preset.flash_time)
	_fx_tween.tween_property(sprite, ^"scale", Vector2.ONE, preset.punch_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _prompt_text()->String:
	var _left:int = uses_left()
	if _left == 0:
		return "Spent"
	if busy:
		return "..."
	var _health:HealthResource = _health()
	if _health != null && _health.is_full():
		return "Full health (%d/%d)" % [_left, max_uses]
	return "Pray (%d/%d)" % [_left, max_uses]
