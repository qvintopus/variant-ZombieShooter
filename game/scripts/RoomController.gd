## Per-room game logic for the mini-game.
## Lives in each room scene (under res://game/), NOT in the addons template.
## - Registers this room as the current room (for HUD/debug).
## - If the room was already cleared this session, removes the ArenaEntry so the
##   enemy waves never start again, and flags the room as cleared for the overlay.
## - Otherwise watches the wave system and marks the room cleared once all waves
##   are defeated.
class_name RoomController
extends Node

## Unique id of this room, e.g. &"room_1".
@export var room_id: StringName

## Shared progression state (same .tres across all rooms).
@export var room_state_resource: RoomStateResource

## Drives the overlay "Room cleared" text (shared BoolResource).
@export var room_cleared_resource: BoolResource

## Template's fight-mode flag (BoolResource) — true while a fight is running.
@export var fight_mode_resource: BoolResource

## Template's remaining-wave count (IntResource) — hits 0 when the room is cleared.
@export var remaining_wave_count_resource: IntResource

## The inherited ArenaEntry node (Area2D) that starts the fight on player enter.
@export var arena_entry: Node

## Tracks whether a real fight has started, so the initial count==0 isn't
## mistaken for "cleared".
var _was_fighting: bool = false
## The room's sections (null in rooms without one).
var _aggregator: ArenaSectionAggregator

func _ready() -> void:
	assert(room_state_resource != null)
	assert(room_cleared_resource != null)
	assert(fight_mode_resource != null)
	assert(remaining_wave_count_resource != null)
	assert(!String(room_id).is_empty())

	room_state_resource.set_current(room_id)
	var _found: Array[Node] = owner.find_children("*", "ArenaSectionAggregator", true, false) if owner != null else []
	_aggregator = _found[0] as ArenaSectionAggregator if !_found.is_empty() else null

	if room_state_resource.is_cleared(room_id):
		# A cleared room has every section cleared (older saves could lack them,
		# leaving gates shut): the aggregator's deferred restore opens them.
		if _aggregator != null:
			for _i: int in _aggregator.sections.size():
				room_state_resource.mark_section_cleared(room_id, _i)
		# Already done: never spawn waves again, show cleared state immediately.
		if is_instance_valid(arena_entry):
			arena_entry.queue_free()
		room_cleared_resource.set_value(true)
		return

	# Fresh room: hide any lingering cleared text, then watch for completion.
	room_cleared_resource.set_value(false)
	fight_mode_resource.changed_true.connect(_on_fight_started)
	remaining_wave_count_resource.updated.connect(_on_remaining_waves_changed)

func _on_fight_started() -> void:
	_was_fighting = true

func _on_remaining_waves_changed() -> void:
	if not _was_fighting:
		return
	# A section still fighting means the room is not done, even if a transient
	# recompute reports zero remaining waves.
	if fight_mode_resource.value:
		return
	if remaining_wave_count_resource.value > 0:
		return
	# Leaving mid-fight zeroes the counts too (aggregator _exit_tree): only real clears count.
	if !is_inside_tree() || (_aggregator != null && !_aggregator.all_cleared()):
		return
	# All waves defeated.
	room_state_resource.mark_cleared(room_id)
	room_cleared_resource.set_value(true)
