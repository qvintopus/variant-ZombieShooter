## Pickup feedback on the player: white blink that grows with a pickup streak,
## collect sounds rising in pitch, "+N item" texts. Teammate copies replay the
## blink and texts (PlayerFx "pickup").
class_name PickupJuice
extends Node

@export var enabled:bool = true
@export var pickup_events:PickupEvents
## Sprite with the color_flash shader (uses its extra_blend channel)
@export var sprite:Sprite2D
## Squashed on each pickup
@export var squash_node:Node2D

@export_group("Streak")
## Pickups closer than this keep the streak going
@export_range(0.05, 3.0, 0.01) var streak_window:float = 0.7

@export_group("Blink")
@export_range(0.0, 1.0, 0.01) var blink_base:float = 0.2
@export_range(0.0, 0.5, 0.005) var blink_per_item:float = 0.06
@export_range(0.0, 1.0, 0.01) var blink_max:float = 0.75
@export_range(0.01, 1.0, 0.01) var blink_time:float = 0.12
@export var squash_scale:Vector2 = Vector2(1.12, 0.9)
@export_range(0.01, 1.0, 0.01) var squash_time:float = 0.1

@export_group("Sound")
@export var pitch_base:float = 1.0
@export var pitch_step:float = 0.04
@export var pitch_max:float = 1.8

@export_group("Text")
@export var text_instance:InstanceResource
## Font size comes from the damage number size setting
@export var settings:DamageNumbersSettings
@export var text_offset:Vector2 = Vector2(0.0, -18.0)
## Same item within this time adds into one text
@export_range(0.0, 3.0, 0.01) var text_merge_time:float = 0.6
## Text per item id; %d = amount (or %s = label for "weapon")
@export var item_texts:Dictionary = {
	&"coin": "+%d G", &"meat": "+%d Meat", &"slime": "+%d Slime",
	&"boss_crystal": "+%d Crystal", &"health": "+%d HP", &"health_full": "Full HP",
	&"weapon": "%s",
}
## Text color per item id; "health" uses the heal color of the settings preset
@export var item_colors:Dictionary = {
	&"coin": Color(1.0, 0.85, 0.3), &"meat": Color(1.0, 0.55, 0.55),
	&"slime": Color(0.55, 1.0, 0.6), &"boss_crystal": Color(1.0, 0.55, 0.95),
	&"weapon": Color(0.6, 0.8, 1.0), &"health_full": Color(0.7, 1.0, 0.7),
}

@export_group("Co-op")
## Seconds between replays sent to teammates
@export var send_interval:float = 0.08

var fx_kind:StringName = &"pickup"

var streak:int
var _last_time:float = -INF
var _blink_tween:Tween
var _squash_tween:Tween
var _texts:Dictionary = {}
var _send_left:float
var _remote:bool
var _material:ShaderMaterial

func _ready()->void:
	_remote = PlayerFx.is_remote(self)
	if sprite != null:
		_material = sprite.material as ShaderMaterial
	if !_remote && enabled && pickup_events != null:
		pickup_events.collected.connect(_on_collected)
		pickup_events.sound_owner = self
	tree_exiting.connect(_on_tree_exiting, CONNECT_ONE_SHOT)
	request_ready()

func _on_tree_exiting()->void:
	if pickup_events == null:
		return
	if pickup_events.collected.is_connected(_on_collected):
		pickup_events.collected.disconnect(_on_collected)
	if pickup_events.sound_owner == self:
		pickup_events.sound_owner = null

func _now()->float:
	return Time.get_ticks_msec() * 0.001

func _on_collected(id:StringName, amount:int, _pos:Vector2, sound:SoundResource, label:String)->void:
	var _t:float = _now()
	streak = streak + 1 if _t - _last_time < streak_window else 1
	_last_time = _t
	if sound != null:
		sound.play_pitched(minf(pitch_base + (streak - 1) * pitch_step, pitch_max))
	_play(streak, id, amount, label)
	if _t >= _send_left:
		_send_left = _t + send_interval
		PlayerFx.send(fx_kind, [streak, String(id), amount, label])

## Teammate copy: replay a pickup [streak, id, amount, label].
func play_remote_fx(args:Array)->void:
	if args.size() != 4 || typeof(args[0]) != TYPE_INT || typeof(args[1]) != TYPE_STRING || typeof(args[2]) != TYPE_INT || typeof(args[3]) != TYPE_STRING:
		return
	_play(clampi(args[0], 1, 999), StringName(args[1]), clampi(args[2], 0, 9999), (args[3] as String).left(32))

func _play(count:int, id:StringName, amount:int, label:String)->void:
	_blink(minf(blink_base + (count - 1) * blink_per_item, blink_max))
	_text(id, amount, label)

func _blink(intensity:float)->void:
	if _material != null:
		if _blink_tween != null:
			_blink_tween.kill()
		_material.set_shader_parameter(&"extra_blend", intensity)
		_blink_tween = create_tween()
		_blink_tween.tween_method(func (v:float)->void: _material.set_shader_parameter(&"extra_blend", v), intensity, 0.0, blink_time)
	if squash_node != null:
		if _squash_tween != null:
			_squash_tween.kill()
		squash_node.scale = squash_scale
		_squash_tween = create_tween()
		_squash_tween.tween_property(squash_node, ^"scale", Vector2.ONE, squash_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _color(id:StringName)->Color:
	if id == &"health" && settings != null:
		return settings.colors().heal
	return item_colors.get(id, Color.WHITE)

func _format(id:StringName, amount:int, label:String)->String:
	var _fmt:String = item_texts.get(id, "+%d " + String(id))
	if _fmt.contains("%s"):
		return _fmt % label
	if _fmt.contains("%d"):
		return _fmt % amount
	return _fmt

func _text(id:StringName, amount:int, label:String)->void:
	if text_instance == null:
		return
	var _body:Node2D = owner as Node2D
	if _body == null:
		return
	var _size:int = settings.font_size() if settings != null else 8
	var _t:float = _now()
	var _entry:Dictionary = _texts.get(id, {})
	var _live:FloatingText = _entry.get("node") as FloatingText if is_instance_valid(_entry.get("node")) else null
	if id != &"weapon" && _live != null && _live.is_inside_tree() && _t - float(_entry.get("time", -INF)) < text_merge_time:
		_entry["amount"] = int(_entry["amount"]) + amount
		_entry["time"] = _t
		_live.bump(_format(id, _entry["amount"], label), _color(id), _size)
		return
	var _text_value:String = _format(id, amount, label)
	var _config:Callable = func (inst:Node2D)->void:
		inst.global_position = _body.global_position + text_offset
		(inst as FloatingText).setup(_text_value, _color(id), _size)
	_texts[id] = {"node": text_instance.instance(_config), "amount": amount, "time": _t}
