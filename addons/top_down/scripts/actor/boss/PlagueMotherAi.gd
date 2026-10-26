## Stationary boss AI: no jumping, attacks on a timer.
## Most cycles fire an aimed acid spit, every summon_every cycles summon acid slimes.
class_name PlagueMotherAi
extends Node

@export var player_reference:ReferenceNodeResource

@export var actor_damage:ActorDamage

@export var volley:BigJellyShootSlime

@export var summon:BossSummon

@export var wait_time:float = 2.5

@export var summon_every:int = 3

var cycle_count:int
var is_running:bool

func _ready()->void:
	actor_damage.actor_died.connect(owner.queue_free)
	player_reference.listen(self, _on_player_changed)

func _on_player_changed()->void:
	if player_reference.node == null || is_running:
		return
	is_running = true
	_cycle.call_deferred()

func _cycle()->void:
	if player_reference.node == null:
		is_running = false
		return

	cycle_count += 1
	var _target:Vector2 = player_reference.node.global_position
	if cycle_count % summon_every == 0:
		summon.shoot(_target)
	else:
		volley.shoot(_target)

	var _tween:Tween = create_tween()
	_tween.tween_callback(_cycle).set_delay(wait_time)
