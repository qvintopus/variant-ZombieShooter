extends Node

@export var button:Button

func _ready()->void:
	button.pressed.connect(pressed)

func pressed()->void:
	# the same way as closing the window (RunSession: save, and ask if a server still runs)
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
