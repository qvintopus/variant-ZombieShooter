## Boss death look and timing: spawns BossDeathBurst from the boss sprite,
## hit-stop, and holds loot / "room cleared" until the light bursts.
## ActorDamage calls on_death(); guests' copies get it from NetEntities._play_death.
class_name BossDeathFx
extends Node

@export var enabled:bool = true
@export var sprite:Sprite2D
@export var burst_instance:InstanceResource

@export_group("Timing")
## Loot drops after this many seconds (when the light bursts)
@export var drop_delay:float = 1.4
## "Room cleared" banner / blessing wait this long
@export var banner_delay:float = 2.0

@export_group("Hit stop")
@export_range(0.0, 1.0, 0.01) var hit_stop_scale:float = 0.25
@export_range(0.0, 1.0, 0.01) var hit_stop_time:float = 0.12

## Called on the killing hit (before the boss leaves the tree).
func on_death()->void:
	if !enabled:
		return
	play_burst((owner as Node2D).global_position)
	hold_room_clear(get_tree() if is_inside_tree() else null)
	_hit_stop()

## The look only (also used for guests' copies).
func play_burst(at:Vector2)->void:
	if burst_instance == null:
		return
	var _sprite:Sprite2D = sprite
	burst_instance.instance(func (n:Node2D)->void: (n as BossDeathBurst).setup_from_sprite(_sprite, at))

## Room-cleared feedback (banner, blessing) waits for the burst.
func hold_room_clear(tree:SceneTree)->void:
	if banner_delay <= 0.0 || tree == null:
		return
	for _node:Node in tree.get_nodes_in_group(&"room_clear_listeners"):
		if &"pending_delay" in _node:
			_node.pending_delay = maxf(_node.pending_delay, banner_delay)

func _hit_stop()->void:
	if hit_stop_time <= 0.0 || hit_stop_scale >= 1.0 || !is_inside_tree() || DisplayServer.get_name() == "headless":
		return
	Engine.time_scale = hit_stop_scale
	get_tree().create_timer(hit_stop_time, true, false, true).timeout.connect(func ()->void: Engine.time_scale = 1.0)
