## Map creator keeps the room paused: Edit mode or an open editor panel (also in Play
## mode) stops the room, and it stays stopped through a scene fade ending, the debug
## pause key and any key press. Play mode with panels closed runs the room again.
##   Godot --headless --path . res://game/tests/map_creator_pause_check.tscn
extends Node

const CREATOR:String = "res://addons/map_creator/scenes/map_creator.tscn"
const SETTINGS:String = "res://addons/map_creator/resources/settings/map_creator_settings.tres"
const KEY:String = "N01"

var failures:int = 0
var checks:int = 0

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _frames(count:int)->void:
	for _i:int in count:
		await get_tree().process_frame

func _press(keycode:Key)->void:
	for _down:bool in [true, false]:
		var _event:InputEventKey = InputEventKey.new()
		_event.keycode = keycode
		_event.physical_keycode = keycode
		_event.pressed = _down
		Input.parse_input_event(_event)
		await _frames(2)

func _ready()->void:
	(load("res://addons/top_down/resources/global_resources/action_resource.tres") as ActionResource).reset_resource()
	var _settings:MapCreatorSettings = (load(SETTINGS) as MapCreatorSettings).duplicate()
	_settings.not_saved = true
	_settings.auto_clean = false
	# no "copy this original?" prompt (Enter would copy the room)
	_settings.originals_ok[KEY] = true
	var _room:Node2D = (load("res://game/scenes/room_%s.tscn" % KEY) as PackedScene).instantiate()
	add_child(_room)
	var _creator:MapCreator = (load(CREATOR) as PackedScene).instantiate()
	_creator.settings = _settings
	_room.add_child(_creator)
	await _frames(4)
	var _stopped:Callable = func ()->bool: return _room.process_mode == Node.PROCESS_MODE_DISABLED
	check(!_stopped.call(), "Play mode runs the room")

	_creator.set_editing(true)
	await _frames(2)
	check(_stopped.call(), "Edit mode stops the room")
	var _fade:BoolResource = (_room.get_node("TransitionProcessingComponent") as ProcessingComponent).bool_resource
	_fade.value = true
	await _frames(2)
	_fade.value = false
	await _frames(2)
	check(_stopped.call(), "a scene fade ending keeps it stopped while editing")
	var _keys:Array[Key] = [KEY_SPACE, KEY_P, KEY_P, KEY_ESCAPE, KEY_ENTER]
	for _code:int in range(KEY_A, KEY_Z + 1):
		if _code != KEY_P:
			_keys.append(_code as Key)
	var _ran:Array[String] = []
	for _code:Key in _keys:
		await _press(_code)
		if !_stopped.call() || !_creator.editing:
			_ran.append(OS.get_keycode_string(_code))
			_creator.set_editing(true)
			await _frames(2)
	check(_ran.is_empty(), "no key runs the room while editing (ran: %s)" % [_ran])

	# the letter keys opened panels (browser, graph, help...): they pause Play mode too
	for _panel:Control in _creator.pause_panels:
		_panel.visible = false
	_creator.set_editing(false)
	await _frames(2)
	check(!_stopped.call() && !_creator.editing_flag.value, "back to Play runs it")
	var _graph:Control = _room.get_node("MapCreator/UI/Root/CampaignGraph")
	check(_creator.pause_panels.has(_graph), "the campaign graph is a pause panel")
	_graph.call(&"open")
	await _frames(2)
	check(_stopped.call(), "a panel open in Play mode stops the room")
	await _press(KEY_SPACE)
	check(_stopped.call(), "Space keeps it stopped under the panel")
	_graph.call(&"close")
	await _frames(2)
	check(!_stopped.call(), "closing the panel runs it again")
	_room.queue_free()
	await _frames(2)
	print("map_creator_pause_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
