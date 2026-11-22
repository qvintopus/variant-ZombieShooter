## Sits in the room template: adds the map creator to the room while Admin tools are on
## (Options > Gameplay), for solo games and the co-op host only (not guests, not a
## dedicated server). Toggling the setting in the pause menu adds/removes it live.
class_name MapCreatorHook
extends Node

@export var settings:MapCreatorSettings
## Loaded only when Admin tools are on, so a normal game never loads the editor.
@export_file("*.tscn") var creator_scene_path:String = "res://addons/map_creator/scenes/map_creator.tscn"

var _creator:Node

func _ready()->void:
	if settings == null || creator_scene_path.is_empty():
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
		_creator = (load(creator_scene_path) as PackedScene).instantiate()
		get_parent().add_child(_creator)
	elif !_want && is_instance_valid(_creator):
		_creator.queue_free()
		_creator = null
