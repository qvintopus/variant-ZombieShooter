## Title menu and pause menu: "Co-op" opens the Co-op dialog (host, join, the virtual LAN,
## the dedicated server) at any time, like the home base Comms Terminal does. The label
## shows the player count while a session is open. The menu's other buttons can't take the
## focus while the dialog is open, and the Co-op button gets it back when it closes.
extends Node

@export var button:Button
@export var label:Label
## Buttons under this lose their focus while the dialog is open (the title's menus).
@export var menu_root:Control

var _dialog:CoopDialog
var _focus_modes:Dictionary = {}

func _ready()->void:
	button.pressed.connect(pressed)
	Net.state_changed.connect(_update_label)
	Net.roster_changed.connect(_update_label)
	_update_label()

func pressed()->void:
	if is_instance_valid(_dialog):
		return
	_dialog = CoopDialog.open_layer()
	_lock_menu(true)
	_dialog.tree_exited.connect(func ()->void:
		_dialog = null
		if is_inside_tree():
			_lock_menu(false)
			button.grab_focus.call_deferred(), CONNECT_ONE_SHOT)

func _exit_tree()->void:
	if is_instance_valid(_dialog):
		_dialog.close()

func _update_label()->void:
	if label != null:
		label.text = "Co-op (%d)" % RunSession.players.count() if Net.is_online() else "Co-op"

func _lock_menu(locked:bool)->void:
	if menu_root == null:
		return
	if locked:
		_focus_modes.clear()
		for _node:Node in menu_root.find_children("*", "BaseButton", true, false):
			var _control:Control = _node as Control
			_focus_modes[_control] = _control.focus_mode
			_control.focus_mode = Control.FOCUS_NONE
	else:
		for _control:Control in _focus_modes:
			if is_instance_valid(_control):
				_control.focus_mode = _focus_modes[_control]
		_focus_modes.clear()
