## Sits in the room template: adds the map creator to the room while Admin tools are on
## (Options > Gameplay), for solo games and the co-op host only (not guests, not a
## dedicated server). Toggling the setting in the pause menu adds/removes it live.
class_name MapCreatorHook
extends Node

@export var settings:MapCreatorSettings
@export var creator_scene:PackedScene

var _creator:Node

func _ready()->void:
	if settings == null || creator_scene == null:
		return
	settings.changed_settings.connect(_sync)
	_sync.call_deferred()

func allowed()->bool:
	var _net:Node = get_node_or_null(^"/root/Net")
	if _net == null:
		return true
	return _net.call(&"is_authority") && !_net.call(&"is_server")

func _sync()->void:
	var _want:bool = settings.admin_enabled && allowed()
	if _want && !is_instance_valid(_creator):
		_creator = creator_scene.instantiate()
		get_parent().add_child(_creator)
	elif !_want && is_instance_valid(_creator):
		_creator.queue_free()
		_creator = null
