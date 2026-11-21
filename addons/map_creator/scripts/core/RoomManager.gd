## Room management of the map creator's workspace (RoomBrowser buttons): new, duplicate,
## rename (rewriting every door / portal that links the old key), delete (an override in
## a mod falls back to the built-in room) and import of a hand-made scene as a layout.
## Every change is stored and baked right away in the workspace (mod or project files).
class_name RoomManager
extends RefCounted

## Floor cells of a new room (a square).
const NEW_SIZE:int = 12

var creator:MapCreator
## Last refusal / result, for the UI.
var last_message:String

func _init(owner:MapCreator)->void:
	creator = owner

func _baker()->LayoutBaker:
	return creator.baker

func _mods()->MapModState:
	return creator.mod_state if creator.mod_state != null && creator.mod_state.is_active() else null

func exists(key:String)->bool:
	return _baker().layouts.has(key) || ResourceLoader.exists(creator.scene_of(key)) || ResourceLoader.exists(_baker().scene_path(key))

## A built-in room (layout or hand-made scene) the workspace can't remove, only override.
func is_builtin(key:String)->bool:
	return ResourceLoader.exists(_baker().layout_path(key)) || ResourceLoader.exists(_baker().scene_path(key))

## The workspace mod has its own copy of `key`.
func in_mod(key:String)->bool:
	var _info:MapModInfo = _mods().active_mod() if _mods() != null else null
	return _info != null && _info.has_room(key)

## "room_X door at (x, y)" for every entity linking to `key` (doors, portals, waits_for).
func links_to(key:String)->PackedStringArray:
	var _found:PackedStringArray = []
	for _other:String in _baker().layouts:
		if _other == key:
			continue
		for _entity:LayoutEntity in _baker().layouts[_other].entities:
			if _links(_entity, key):
				_found.append("room_%s %s at %s" % [_other, _entity.item_id, _entity.cell])
	return _found

static func _links(entity:LayoutEntity, key:String)->bool:
	return String(entity.props.get("room", "")).trim_prefix("room_") == key || String(entity.props.get("waits_for", "")).trim_prefix("room_") == key

func _check_new_key(key:String)->bool:
	if !LayoutCodec.valid_key(key):
		return _refuse("Room keys are letters, digits and _ (max 32)")
	if exists(key):
		return _refuse("room_%s already exists" % key)
	if !creator.writable():
		return _refuse("Pick or create a mod first (workspace menu)")
	return true

func _refuse(text:String)->bool:
	last_message = text
	return false

## A NEW_SIZE square of the default floor with a player spawn; same campaign as `like`.
func new_room(key:String, display_name:String = "", like:RoomLayoutResource = null)->bool:
	if !_check_new_key(key):
		return false
	var _layout:RoomLayoutResource = RoomLayoutResource.new()
	_layout.key = key
	_layout.display_name = display_name if !display_name.is_empty() else "room_" + key
	_layout.writes_balance = false
	_layout.user_made = true
	if like != null:
		_layout.campaign = like.campaign
		_layout.look = like.look
	var _floor:MapCatalogItem = creator.catalog.first_of_kind(MapCatalogItem.Kind.FLOOR)
	for _y:int in NEW_SIZE:
		for _x:int in NEW_SIZE:
			_layout.floor[Vector2i(_x, _y)] = Vector3i(_floor.floor_source, _floor.floor_atlas.x, _floor.floor_atlas.y)
	_layout.entities.append(LayoutEntity.make(&"player_spawn", Vector2i(NEW_SIZE / 2, NEW_SIZE / 2)))
	return store(_layout)

func duplicate_room(from_key:String, key:String)->bool:
	if !_check_new_key(key):
		return false
	var _source:RoomLayoutResource = _baker().layouts.get(from_key, null)
	if _source == null:
		return _refuse("room_%s has no layout to copy (import it first)" % from_key)
	var _copy:RoomLayoutResource = _source.clone()
	_copy.key = key
	_copy.display_name = (_source.display_name if !_source.display_name.is_empty() else "room_" + from_key) + " copy"
	_copy.start = false
	_copy.home = false
	_copy.user_made = true
	return store(_copy)

## Renames a workspace room and rewrites the links to it (those rooms are stored too:
## in a mod, a built-in room that linked here becomes an override).
func rename_room(old_key:String, key:String)->bool:
	var _layout:RoomLayoutResource = _baker().layouts.get(old_key, null)
	if _layout == null:
		return _refuse("room_%s has no layout" % old_key)
	if _mods() != null && (is_builtin(old_key) || !in_mod(old_key)):
		return _refuse("Built-in rooms keep their key: duplicate it instead")
	if !_check_new_key(key):
		return false
	var _renamed:RoomLayoutResource = _layout.clone()
	_renamed.key = key
	var _changed:Array[RoomLayoutResource] = []
	for _other:String in _baker().layouts:
		if _other == old_key:
			continue
		var _copy:RoomLayoutResource = null
		for _entity:LayoutEntity in _baker().layouts[_other].entities:
			if _links(_entity, old_key):
				if _copy == null:
					_copy = _baker().layouts[_other].clone()
				break
		if _copy == null:
			continue
		for _entity:LayoutEntity in _copy.entities:
			if String(_entity.props.get("room", "")).trim_prefix("room_") == old_key:
				_entity.props.room = "room_" + key
			if String(_entity.props.get("waits_for", "")).trim_prefix("room_") == old_key:
				_entity.props.waits_for = key
		_changed.append(_copy)
	if !store(_renamed):
		return false
	_unstore(old_key)
	for _copy:RoomLayoutResource in _changed:
		store(_copy)
	_rename_recent(old_key, key)
	last_message = "Renamed room_%s to room_%s (%d linking rooms updated)" % [old_key, key, _changed.size()]
	return true

func delete_room(key:String)->bool:
	if key == creator.key:
		return _refuse("Leave the room before deleting it")
	if _mods() != null:
		if !in_mod(key):
			return _refuse("room_%s is built-in: nothing of the mod to delete" % key)
		_unstore(key)
		last_message = "Deleted the mod's room_%s%s" % [key, " (the built-in room is back)" if is_builtin(key) else ""]
		return true
	if !_baker().layouts.has(key):
		return _refuse("room_%s has no layout (hand-made scenes stay)" % key)
	_unstore(key)
	last_message = "Deleted room_%s" % key
	return true

## Hand-made scene -> layout in the workspace (warnings go to the log).
func import_room(key:String)->bool:
	if _baker().layouts.has(key):
		return _refuse("room_%s already has a layout" % key)
	if !creator.writable():
		return _refuse("Pick or create a mod first (workspace menu)")
	var _importer:RoomImporter = RoomImporter.new()
	var _layout:RoomLayoutResource = _importer.import_scene(_baker().scene_path(key), key, _baker())
	for _warning:String in _importer.warnings:
		push_warning("import room_%s: %s" % [key, _warning])
	if _layout == null:
		return _refuse("Can't import room_%s: %s" % [key, _importer.warnings[0] if !_importer.warnings.is_empty() else "?"])
	# a hand-made scene stays as it is in the project; the layout becomes its source
	if !store(_layout, _mods() == null):
		return false
	last_message = "Imported room_%s (%d entities, %d warnings)" % [key, _layout.entities.size(), _importer.warnings.size()]
	return true

## Writes and bakes `layout` in the workspace. `bake_scene` false keeps the project's
## scene (an import in the project files only adds the layout).
func store(layout:RoomLayoutResource, bake_scene:bool = true)->bool:
	var _baker:LayoutBaker = _baker()
	_baker.layouts[layout.key] = layout
	if _mods() != null:
		var _info:MapModInfo = _mods().active_mod()
		if _mods().write_layout(_info, layout) != OK:
			return _refuse("Can't write the mod layout of room_%s" % layout.key)
		if _mods().bake_room(_info, layout, _baker).is_empty():
			return _refuse("Bake failed: room_%s" % layout.key)
		return true
	if _baker.save_layout(layout) != OK:
		return _refuse("Can't write %s" % _baker.layout_path(layout.key))
	if !bake_scene:
		return true
	if _baker.bake(layout).is_empty():
		return _refuse("Bake failed: room_%s" % layout.key)
	if _baker.has_method(&"write_balance"):
		_baker.call(&"write_balance")
	if ResourceLoader.has_cached(_baker.written_path(layout.key)):
		ResourceLoader.load(_baker.written_path(layout.key), "", ResourceLoader.CACHE_MODE_REPLACE)
	return true

func _unstore(key:String)->void:
	var _baker:LayoutBaker = _baker()
	if _mods() != null:
		_mods().delete_layout(_mods().active_mod(), key)
		if ResourceLoader.exists(_baker.layout_path(key)):
			_baker.layouts[key] = ResourceLoader.load(_baker.layout_path(key), "", ResourceLoader.CACHE_MODE_REPLACE)
		else:
			_baker.layouts.erase(key)
		return
	_baker.layouts.erase(key)
	for _path:String in [_baker.layout_path(key), _baker.written_path(key)]:
		if FileAccess.file_exists(_path):
			DirAccess.remove_absolute(_path)
	if _baker.has_method(&"remove_balance"):
		_baker.call(&"remove_balance", key)
	_rename_recent(key, "")

func _rename_recent(old_key:String, key:String)->void:
	var _settings:MapCreatorSettings = creator.settings
	if _settings == null:
		return
	var _at:int = _settings.recent_rooms.find(old_key)
	if _at == -1:
		return
	if key.is_empty():
		_settings.recent_rooms.remove_at(_at)
	else:
		_settings.recent_rooms[_at] = key
	_settings.recent_changed.emit()
