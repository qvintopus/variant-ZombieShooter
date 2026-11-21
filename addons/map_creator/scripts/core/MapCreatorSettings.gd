## Player-side map creator settings (Options > Gameplay > Admin tools). Saved.
class_name MapCreatorSettings
extends SaveableResource

signal changed_settings
signal recent_changed

## Shows the admin topbar in rooms (solo / co-op host only).
@export var admin_enabled:bool = false
## Room keys, most recent first.
@export var recent_rooms:PackedStringArray = []
@export var recent_max:int = 5
## Runs Clean Visuals after every paint stroke.
@export var auto_clean:bool = true
@export var show_grid:bool = true
## Set by a room switch from Edit mode: the next room's editor starts editing. Not saved.
var resume_editing:bool

func set_admin_enabled(value:bool)->void:
	admin_enabled = value
	changed_settings.emit()

func set_auto_clean(value:bool)->void:
	auto_clean = value
	changed_settings.emit()

func set_show_grid(value:bool)->void:
	show_grid = value
	changed_settings.emit()

## Moves a room key to the front of the recent list.
func visit(key:String)->void:
	if key.is_empty():
		return
	var _list:PackedStringArray = [key]
	for _key:String in recent_rooms:
		if _key != key && _list.size() < recent_max:
			_list.append(_key)
	if _list == recent_rooms:
		return
	recent_rooms = _list
	recent_changed.emit()
	save_resource()

func prepare_save()->Resource:
	return self.duplicate()

func prepare_load(data:Resource)->void:
	if data == null:
		return
	admin_enabled = data.get(&"admin_enabled")
	recent_rooms = data.get(&"recent_rooms")
	auto_clean = data.get(&"auto_clean")
	show_grid = data.get(&"show_grid")
	changed_settings.emit()

func reset_resource()->void:
	admin_enabled = false
	recent_rooms = []
	auto_clean = true
	show_grid = true
	changed_settings.emit()
