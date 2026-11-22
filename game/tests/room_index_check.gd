## Map creator rooms: the room index covers every layout and hand-made room scene and
## finds rooms by key, name, enemy, contraption, tag and flag; the info panel describes a
## room; the recent list keeps the last 5; the browser lists matches; switching rooms asks
## twice with unsaved edits, refuses unknown rooms and goes through the scene transition
## to the PlayerSpawner (no door has the switch tag).
##   Godot --headless --path . res://game/tests/room_index_check.tscn
extends Node

const BAKER:String = "res://game/resources/map_creator/layout_baker.tres"
const CREATOR:String = "res://addons/map_creator/scenes/map_creator.tscn"

var failures:int = 0
var checks:int = 0

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	(load("res://addons/top_down/resources/global_resources/action_resource.tres") as ActionResource).reset_resource()
	var _baker:GameLayoutBaker = load(BAKER)
	var _index:RoomIndex = RoomIndex.new()
	_index.build(_baker, _baker.catalog)
	check(_index.entries.size() >= 32, "every room is indexed (%d)" % _index.entries.size())
	check(_index.entries.has("1") && _index.entries["1"].layout == null, "hand-made room scenes are indexed too")
	check(_index.search("").size() == _index.entries.size(), "an empty search lists every room")
	check(_index.search("N02")[0] == "N02", "search by key puts that room first (%s)" % [_index.search("N02")])
	check(_index.search("sun court").has("N02"), "search by name")
	check(_index.search("broodmother").has("N23"), "search by boss name")
	check(_index.search("zombie_crawler").size() > 3, "search by enemy id")
	var _slots:Array[String] = _index.search("slot")
	var _with_slot:int = 0
	for _layout:RoomLayoutResource in _baker.layouts.values():
		if _layout.has_item(&"slot_machine"):
			_with_slot += 1
	check(_slots.size() >= _with_slot && _with_slot > 0, "search by contraption (%d of %d)" % [_slots.size(), _with_slot])
	check(_index.search("home chest").has("H00"), "search by several words")
	check(_index.search("new_game boss").has("N12"), "search by campaign + flag")
	check(_index.search("nothing_like_this_anywhere").is_empty(), "no match, no rooms")
	var _info:String = _index.describe("N02", _baker.catalog)
	check(_info.contains("Sun Court") && _info.contains("Section 1") && _info.contains("room_N01"), "the info panel describes the room")

	var _settings:MapCreatorSettings = MapCreatorSettings.new()
	_settings.not_saved = true
	for _key:String in ["A", "B", "C", "D", "E", "F", "B"]:
		_settings.visit(_key)
	check(_settings.recent_rooms == PackedStringArray(["B", "F", "E", "D", "C"]), "recent keeps the last 5, newest first (%s)" % _settings.recent_rooms)

	# browser + switching on a live room
	var _room:Node2D = (load("res://game/scenes/room_N02.tscn") as PackedScene).instantiate()
	var _creator:MapCreator = (load(CREATOR) as PackedScene).instantiate()
	_creator.settings = _settings
	_creator.room = _room
	var _transition:SceneTransitionResource = SceneTransitionResource.new()
	_transition.player_reference = ReferenceNodeResource.new()
	var _player:Node2D = Node2D.new()
	_transition.player_reference.node = _player
	_creator.scene_transition_resource = _transition
	_creator.player_reference = _transition.player_reference
	add_child(_room)
	_room.add_child(_creator)
	for _i:int in 3:
		await get_tree().process_frame
	check(_settings.recent_rooms[0] == "N02", "entering a room puts it first in recent")
	var _browser:RoomBrowser = _creator.get_node("UI/Root/RoomBrowser")
	_creator.set_editing(true)
	_creator.browse_requested.emit()
	check(_browser.visible, "Rooms opens the browser")
	check(_browser.selected_key() == "N02", "the current room is selected")
	_browser._search.text = "N23 broodmother"
	_browser.refresh()
	check(_browser.selected_key() == "N23", "typing filters the list (%s)" % _browser.selected_key())
	check(_browser._info.text.contains("N23"), "the info panel follows the selection")

	check(!_creator.switch_room("ZZZ"), "an unknown room is refused")
	_creator.dirty = true
	check(!_creator.switch_room("N23"), "unsaved edits: the first switch only warns")
	check(_creator.switch_room("N23"), "the second switch goes")
	check(_transition.next_scene_path == _baker.scene_path("N23") && _transition.entry_tag == _creator.switch_entry_tag, "the switch uses the scene transition")
	check(_settings.resume_editing && !_creator.editing, "the next room's editor resumes Edit mode")
	_player.free()
	_room.queue_free()
	await get_tree().process_frame
	print("room_index_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
