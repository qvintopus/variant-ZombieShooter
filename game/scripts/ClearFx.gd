## Wave cleared / room cleared feedback: a burst from every player in the room
## (teammate copies too: each machine sees the same waves) and, when the room
## is cleared, a "blessing" light over the screen.
class_name ClearFx
extends Node

@export var enabled:bool = true
@export var player_reference:ReferenceNodeResource
## Teammate copies (RemotePlayer puppets) burst too
@export var include_teammates:bool = true
@export var teammate_group:StringName = &"remote_player"
@export var burst_offset:Vector2 = Vector2(0.0, -6.0)

@export_group("Wave cleared")
@export var wave_burst:InstanceResource
@export var wave_shake:CameraShakeResource
@export var wave_sound:SoundResource

@export_group("Room cleared")
@export var room_burst:InstanceResource
@export var room_shake:CameraShakeResource
@export var blessing:BlessingOverlay
## Seconds after the clear before the room effects play
@export var room_delay:float = 0.0

## Extra delay a caller can ask for the next room clear (boss death effect).
var pending_delay:float

func _ready()->void:
	var _aggregator:ArenaSectionAggregator = get_tree().get_first_node_in_group(&"arena_aggregator")
	if _aggregator != null:
		_aggregator.wave_finished.connect(_on_wave_finished)

func _on_wave_finished(_wave_number:int, _waves_left:int, section_cleared:bool, _sections_left:int)->void:
	if !enabled:
		return
	if section_cleared:
		var _delay:float = room_delay + pending_delay
		pending_delay = 0.0
		if _delay > 0.0:
			get_tree().create_timer(_delay, false).timeout.connect(play_room_cleared)
		else:
			play_room_cleared()
	else:
		play_wave_cleared()

func _players()->Array[Node2D]:
	var _list:Array[Node2D] = []
	if player_reference != null && is_instance_valid(player_reference.node) && (player_reference.node as Node2D).is_inside_tree():
		_list.append(player_reference.node)
	if include_teammates:
		for _node:Node in get_tree().get_nodes_in_group(teammate_group):
			if _node is Node2D && _node.is_inside_tree():
				_list.append(_node)
	return _list

func _burst(resource:InstanceResource)->void:
	if resource == null:
		return
	for _player:Node2D in _players():
		var _at:Vector2 = _player.global_position + burst_offset
		resource.instance(func (n:Node2D)->void: n.global_position = _at)

func play_wave_cleared()->void:
	_burst(wave_burst)
	if wave_shake != null:
		wave_shake.play()
	if wave_sound != null:
		wave_sound.play_managed()

func play_room_cleared()->void:
	if !is_inside_tree():
		return
	_burst(room_burst)
	if room_shake != null:
		room_shake.play()
	if blessing != null:
		blessing.play(player_reference.node as Node2D if player_reference != null else null)
