## Falling into a hole: the body sinks and shrinks into it, then pops back up
## on the last safe tile, pushed a little away from the hole. HoleRecovery
## calls fall() and applies the damage when it lands. Teammate copies replay
## the sink/pop look (PlayerFx "fall").
class_name HoleFall
extends Node

signal landed
## The body reached its smallest size at the bottom of the hole
signal bottomed

enum HitMoment {
	## When the body is smallest, at the bottom of the hole
	SMALLEST,
	## When it's back up on safe ground
	LANDED,
}

@export var enabled:bool = true
@export var preset:FallFxPreset
## When fall(on_hit) calls on_hit (HoleRecovery applies the hole damage there)
@export var hit_moment:HitMoment = HitMoment.SMALLEST
@export var resource_node:ResourceNode
@export var safe_tile_tracker:SafeTileTracker
@export var player_input:PlayerInput
## Moved / scaled while falling
@export var visual_node:Node2D
## Tinted dark while falling
@export var tint_node:CanvasItem
@export var shadow_node:Node2D
@export var land_dust:InstanceResource
@export var fall_sound:SoundResource
@export var land_sound:SoundResource

var fx_kind:StringName = &"fall"
var falling:bool

var _remote:bool
var _tween:Tween
var _shadow_scale:Vector2 = Vector2.ONE
var _input:InputResource
var _damage:DamageResource
var _health:HealthResource

func _ready()->void:
	_remote = PlayerFx.is_remote(self)
	if shadow_node != null:
		_shadow_scale = shadow_node.scale
	if resource_node != null:
		_input = resource_node.get_resource("input")
		_damage = resource_node.get_resource("damage")
		_health = resource_node.get_resource("health")
	tree_exiting.connect(_reset, CONNECT_ONE_SHOT)
	request_ready()

func _body()->Node2D:
	return owner as Node2D

## Starts the fall; `on_hit` runs at hit_moment (smallest size or landed).
func fall(on_hit:Callable = Callable())->void:
	if falling || preset == null:
		return
	falling = true
	var _entry:Vector2 = _body().global_position
	var _safe:Vector2 = safe_tile_tracker.safe_position() if safe_tile_tracker != null else _entry
	var _away:Vector2 = (_safe - _entry).normalized() if _safe.distance_squared_to(_entry) > 0.01 else Vector2.ZERO
	var _land:Vector2 = _safe + _away * preset.land_push
	_lock(true)
	PlayerFx.send(fx_kind, [_entry, _land])
	_play(-_away, func ()->void:
		if hit_moment == HitMoment.SMALLEST && on_hit.is_valid():
			on_hit.call()
		bottomed.emit()
	, func ()->void:
		_body().global_position = _land
		if safe_tile_tracker != null:
			safe_tile_tracker.reset_to(_land)
	, func ()->void:
		_lock(false)
		falling = false
		if hit_moment == HitMoment.LANDED && on_hit.is_valid():
			on_hit.call()
		landed.emit()
	)

## Teammate copy: [entry:Vector2, land:Vector2], look only (position comes from updates).
func play_remote_fx(args:Array)->void:
	if args.size() != 2 || typeof(args[0]) != TYPE_VECTOR2 || typeof(args[1]) != TYPE_VECTOR2:
		return
	var _entry:Vector2 = args[0]
	var _land:Vector2 = args[1]
	if !_entry.is_finite() || !_land.is_finite():
		return
	_play((_entry - _land).normalized(), Callable(), Callable(), Callable())

func _lock(value:bool)->void:
	if _remote:
		return
	if player_input != null:
		player_input.set_enabled(!value)
	if _input != null && value:
		_input.set_axis(Vector2.ZERO)
		_input.set_action(false)
		_input.set_action_2(false)
	if _damage != null:
		_damage.fall_immune = value

## Sink toward `into` (direction into the hole), hidden, teleport, pop up.
## at_smallest: end of the sink; at_bottom: teleport moment; at_end: popped up.
func _play(into:Vector2, at_smallest:Callable, at_bottom:Callable, at_end:Callable)->void:
	if _tween != null:
		_tween.kill()
	_reset_look()
	if fall_sound != null:
		fall_sound.play_managed()
	var _p:FallFxPreset = preset
	var _sink_to:Vector2 = into * _p.slide_into_hole + Vector2(0.0, _p.sink_drop)
	_tween = create_tween()
	_tween.set_parallel(true)
	if visual_node != null:
		_tween.tween_property(visual_node, ^"position", _sink_to, _p.sink_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_property(visual_node, ^"scale", Vector2.ONE * _p.sink_scale, _p.sink_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_property(visual_node, ^"rotation", TAU * _p.sink_spin, _p.sink_time)
	if tint_node != null:
		_tween.tween_property(tint_node, ^"self_modulate", _p.sink_color, _p.sink_time)
	if shadow_node != null:
		_tween.tween_property(shadow_node, ^"scale", Vector2.ZERO, _p.sink_time * 0.8)
	_tween.set_parallel(false)
	_tween.tween_callback(func ()->void:
		if visual_node != null:
			visual_node.visible = false
		if at_smallest.is_valid():
			at_smallest.call()
	)
	_tween.tween_interval(_p.hidden_time)
	_tween.tween_callback(func ()->void:
		if at_bottom.is_valid():
			at_bottom.call()
		if visual_node != null:
			visual_node.position = Vector2.ZERO
			visual_node.rotation = 0.0
			visual_node.scale = Vector2.ONE * _p.pop_start_scale
			visual_node.visible = true
		if tint_node != null:
			tint_node.self_modulate = Color.WHITE
		if land_dust != null:
			var _at:Vector2 = _body().global_position
			land_dust.instance(func (n:Node2D)->void: n.global_position = _at)
		if land_sound != null:
			land_sound.play_managed()
	)
	if visual_node != null:
		_tween.tween_property(visual_node, ^"scale", Vector2.ONE * _p.pop_overshoot, _p.pop_time * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_property(visual_node, ^"scale", Vector2.ONE, _p.pop_time * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if shadow_node != null:
		_tween.parallel().tween_property(shadow_node, ^"scale", _shadow_scale, _p.pop_time)
	_tween.tween_callback(func ()->void:
		if at_end.is_valid():
			at_end.call()
	)

func _reset_look()->void:
	if visual_node != null:
		visual_node.position = Vector2.ZERO
		visual_node.rotation = 0.0
		visual_node.scale = Vector2.ONE
		visual_node.visible = true
	if tint_node != null:
		tint_node.self_modulate = Color.WHITE
	if shadow_node != null:
		shadow_node.scale = _shadow_scale

func _reset()->void:
	if _tween != null:
		_tween.kill()
	_reset_look()
	if falling:
		_lock(false)
	falling = false
