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

## Optional stair that is hidden until the room is cleared, used to move on after a fight.
@export var exit_stair: Node

## The room's sections. When set, the room only counts as cleared if every section
## was really cleared: freeing the room mid-fight (game over, leaving by stair) also
## zeroes the wave counts, which would otherwise look like a clear.
@export var arena_aggregator: ArenaSectionAggregator

## Tracks whether a real fight has started, so the initial count==0 isn't
## mistaken for "cleared".
var _was_fighting: bool = false

func _ready() -> void:
	assert(room_state_resource != null)
	assert(room_cleared_resource != null)
	assert(fight_mode_resource != null)
	assert(remaining_wave_count_resource != null)
	assert(!String(room_id).is_empty())

	room_state_resource.set_current(room_id)

	if room_state_resource.is_cleared(room_id):
		# Already done: never spawn waves again, show cleared state immediately.
		if is_instance_valid(arena_entry):
			arena_entry.queue_free()
		room_cleared_resource.set_value(true)
		_show_exit_stair()
		return

	# Fresh room: the exit waits for the fight, then hide any lingering cleared text.
	_hide_exit_stair()
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
	if arena_aggregator != null and !_all_sections_cleared():
		return
	# All waves defeated.
	room_state_resource.mark_cleared(room_id)
	room_cleared_resource.set_value(true)
	_show_exit_stair()

## Sections without waves are never started, so they do not count.
func _all_sections_cleared() -> bool:
	for _section:ArenaSection in arena_aggregator.sections:
		if _section == null or _section.waves.is_empty():
			continue
		if !_section.is_cleared:
			return false
	return true

## Hidden exit stairs appear once the fight is won.
func _show_exit_stair() -> void:
	if exit_stair == null:
		return
	exit_stair.visible = true
	exit_stair.monitoring = true

func _hide_exit_stair() -> void:
	if exit_stair == null:
		return
	exit_stair.visible = false
	exit_stair.monitoring = false
