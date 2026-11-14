## Asked when the game closes (window close, the title's Quit) while this PC still runs a
## dedicated server or has the virtual LAN up: stop them, keep them running, or don't quit.
## "Stop all" stops the server (it saves its run) and turns the tunnel off ("vlan_auto off":
## keys and guests kept, Start again brings it back; on Windows that asks for admin).
## Nothing running: the game just quits. Call request() where the game quits (window close, its
## Quit button); a headless server never asks.
class_name LanPartyQuitPrompt
extends Control

const LAYER_NAME:String = "QuitPromptLayer"

var _text:Label
var _buttons:HBoxContainer
var _server:bool
var _vlan:bool

## Quit now, or ask first. `quit` does the quitting (saves, then quits the tree).
static func request(quit:Callable)->void:
	if LanPartyServer.enabled() || DisplayServer.get_name() == "headless":
		quit.call()
		return
	var _server_up:bool = LanPartyServerProcess.alive()
	var _vlan_up:bool = !LanPartyAddresses.vlan_address().is_empty() && LanPartyVlan.supported()
	if !_server_up && !_vlan_up:
		quit.call()
		return
	var _tree:SceneTree = Engine.get_main_loop() as SceneTree
	if _tree.root.has_node(LAYER_NAME):
		return
	var _layer:CanvasLayer = CanvasLayer.new()
	_layer.layer = 6
	_layer.name = LAYER_NAME
	var _prompt:LanPartyQuitPrompt = LanPartyQuitPrompt.new()
	_prompt._server = _server_up
	_prompt._vlan = _vlan_up
	_prompt._quit = quit
	_layer.add_child(_prompt)
	_tree.root.add_child(_layer)

var _quit:Callable

func _ready()->void:
	theme = LanPartyStyle.theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var _dim:ColorRect = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.7)
	_dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_dim)
	var _center:CenterContainer = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_center)
	var _panel:PanelContainer = PanelContainer.new()
	_panel.theme_type_variation = &"DialogPanel"
	_panel.custom_minimum_size = Vector2(260, 0)
	_center.add_child(_panel)
	var _box:VBoxContainer = VBoxContainer.new()
	_box.add_theme_constant_override(&"separation", 8)
	_panel.add_child(_box)
	_box.add_child(LanPartyStyle.label("QUIT THE GAME?", &"TitleLabel"))
	var _running:PackedStringArray = []
	if _server:
		_running.append("the dedicated server")
	if _vlan:
		_running.append("the virtual LAN (%s)" % LanPartyAddresses.vlan_address())
	_text = LanPartyStyle.label("Still running on this PC: %s.\nFriends can keep playing while it runs." % " and ".join(_running), &"", true)
	_box.add_child(_text)
	_buttons = HBoxContainer.new()
	_box.add_child(_buttons)
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	var _stop:Button = LanPartyStyle.button("Stop all, quit", _stop_all, LanPartyStyle.PRIMARY)
	_buttons.add_child(LanPartyStyle.button("Cancel", close, LanPartyStyle.GHOST))
	_buttons.add_child(LanPartyStyle.button("Keep running, quit", func ()->void: _quit.call()))
	_buttons.add_child(_stop)
	_stop.grab_focus.call_deferred()

func close()->void:
	get_parent().queue_free()

func _input(event:InputEvent)->void:
	if !_buttons.visible:
		get_viewport().set_input_as_handled()
		return
	if event.is_action("ui_cancel") || event.is_action(&"pause"):
		get_viewport().set_input_as_handled()
		if event.is_released():
			close()

func _stop_all()->void:
	_buttons.visible = false
	var _problems:PackedStringArray = []
	if _server:
		_text.text = "Stopping the server..."
		if !await LanPartyServerProcess.stop():
			_problems.append("the server didn't stop")
	if _vlan:
		_text.text = "Turning the virtual LAN off..." + ("\nWindows asks for admin rights." if OS.get_name() == "Windows" else "")
		var _tool:LanPartyVlan = LanPartyVlan.new()
		if _tool.start(["off"]):
			var _done:Array = await _tool.finished
			if int(_done[0]) != 0:
				_problems.append("the virtual LAN: " + LanPartyVlan.exit_text(int(_done[0])))
	if _problems.is_empty():
		_quit.call()
		return
	_text.text = "Not everything stopped (%s). Quit anyway?" % ", ".join(_problems)
	_buttons.visible = true
	_buttons.get_child(0).queue_free()
