## Searchable summary of every room: the baker's layouts (name, campaign, look, flags,
## size, entities with their catalog names and tags, enemies of each section, door and
## portal targets) plus hand-made room scenes without a layout (node names read from the
## packed scene, nothing instantiated). search() matches every word of the query anywhere.
class_name RoomIndex
extends RefCounted

## key -> entry {key, name, campaign, layout (or null), scene, text, ...}
var entries:Dictionary = {}

## With an active mod in `mods`, baker.layouts already holds its rooms over the built-in
## ones (MapModState.activate); entries get source "mod" (new) or "override".
func build(baker:LayoutBaker, catalog:MapCatalog, mods:MapModState = null)->void:
	entries.clear()
	if baker.layouts.is_empty():
		baker.load_layouts()
	var _mod:MapModInfo = mods.active_mod() if mods != null else null
	for _key:String in baker.layouts:
		var _entry:Dictionary = _layout_entry(baker.layouts[_key], baker, catalog)
		if _mod != null && _mod.has_room(_key):
			_entry.source = "override" if ResourceLoader.exists(baker.layout_path(_key)) else "mod"
			_entry.scene = mods.scene_for(_key)
			_entry.text += " " + _entry.source + " " + _mod.id
		entries[_key] = _entry
	for _file:String in DirAccess.get_files_at(baker.scenes_dir):
		var _file_name:String = _file.trim_suffix(".remap")
		if !_file_name.begins_with("room_") || !_file_name.ends_with(".tscn"):
			continue
		var _key:String = _file_name.get_basename().trim_prefix("room_")
		if !entries.has(_key):
			entries[_key] = _scene_entry(_key, baker.scenes_dir + _file_name)

func _layout_entry(layout:RoomLayoutResource, baker:LayoutBaker, catalog:MapCatalog)->Dictionary:
	var _counts:Dictionary = {}
	var _words:PackedStringArray = [layout.key, layout.scene_name(), layout.display_name, layout.campaign, layout.look, layout.accent]
	var _links:Array = []
	for _entity:LayoutEntity in layout.entities:
		_counts[_entity.item_id] = _counts.get(_entity.item_id, 0) + 1
		var _item:MapCatalogItem = catalog.item(_entity.item_id)
		if _item != null:
			_words.append(String(_item.id))
			_words.append(_item.display_name)
			_words.append_array(_item.tags)
		if _entity.props.has("room"):
			_links.append({"kind": _entity.item_id, "room": _entity.props.room, "tag": _entity.props.get("tag", "")})
			_words.append(String(_entity.props.room))
	var _enemies:Array = []
	for _section:Dictionary in layout.sections:
		var _ids:Array = []
		for _wave:Dictionary in _section.get("waves", []):
			for _id:Variant in _wave.get("enemies", []):
				if !_ids.has(_id):
					_ids.append(_id)
				_words.append(String(_id))
			if _wave.get("is_boss", false):
				_words.append("boss")
				_words.append(String(_wave.get("display_name", "")))
		_enemies.append(_ids)
	for _flag:Array in [[layout.start, "start"], [layout.home, "home"], [layout.side_room > 0, "side room"], [layout.boss_section > 0, "boss"]]:
		if _flag[0]:
			_words.append(_flag[1])
	return {
		"key": layout.key, "name": layout.display_name, "campaign": String(layout.campaign), "layout": layout,
		"scene": baker.scene_path(layout.key), "size": layout.size(), "cells": layout.floor.size(),
		"counts": _counts, "enemies": _enemies, "links": _links, "source": "",
		"text": " ".join(_words).to_lower(),
	}

func _scene_entry(key:String, path:String)->Dictionary:
	var _words:PackedStringArray = [key, "room_" + key, "hand-made", "scene"]
	var _scene:PackedScene = load(path) as PackedScene
	if _scene != null:
		var _state:SceneState = _scene.get_state()
		for _i:int in _state.get_node_count():
			_words.append(String(_state.get_node_name(_i)))
			var _instance:PackedScene = _state.get_node_instance(_i)
			if _instance != null:
				_words.append(_instance.resource_path.get_file().get_basename())
	return {"key": key, "name": "(hand-made scene)", "campaign": "", "layout": null, "scene": path, "counts": {}, "enemies": [], "links": [], "source": "", "text": " ".join(_words).to_lower()}

## Keys whose text holds every word of `query` (all rooms for an empty query): the
## room with that key first, then rooms whose key or name has the query, then the rest.
func search(query:String)->Array[String]:
	var _words:PackedStringArray = query.to_lower().split(" ", false)
	var _keys:Array[String] = []
	for _key:String in entries:
		var _text:String = entries[_key].text
		var _ok:bool = true
		for _word:String in _words:
			if !_text.contains(_word):
				_ok = false
				break
		if _ok:
			_keys.append(_key)
	var _query:String = query.strip_edges().to_lower()
	var _rank:Callable = func (key:String)->int:
		if _query.is_empty():
			return 2
		if key.to_lower() == _query.trim_prefix("room_"):
			return 0
		if key.to_lower().contains(_query) || String(entries[key].name).to_lower().contains(_query):
			return 1
		return 2
	_keys.sort_custom(func (a:String, b:String)->bool:
		var _ra:int = _rank.call(a)
		var _rb:int = _rank.call(b)
		return _ra < _rb || (_ra == _rb && a < b))
	return _keys

## Multi-line details of a room for the info panel.
func describe(key:String, catalog:MapCatalog)->String:
	var _e:Dictionary = entries.get(key, {})
	if _e.is_empty():
		return ""
	var _lines:PackedStringArray = ["room_%s  %s" % [key, _e.name]]
	if !_e.source.is_empty():
		_lines.append("Mod room (%s)" % ("replaces the built-in room" if _e.source == "override" else "new"))
	if _e.layout == null:
		_lines.append("Hand-made scene, no layout (view only)")
		return "\n".join(_lines)
	var _layout:RoomLayoutResource = _e.layout
	_lines.append("Campaign: %s   Look: %s%s" % [_e.campaign, _layout.look, (" + " + _layout.accent) if !_layout.accent.is_empty() else ""])
	_lines.append("Size: %dx%d, %d floor cells" % [_e.size.x, _e.size.y, _e.cells])
	var _flags:PackedStringArray = []
	if _layout.start:
		_flags.append("campaign start")
	if _layout.home:
		_flags.append("home base")
	if _layout.side_room > 0:
		_flags.append("side room S%d" % _layout.side_room)
	if _layout.boss_section > 0:
		_flags.append("boss S%d" % _layout.boss_section)
	if !_flags.is_empty():
		_lines.append(", ".join(_flags))
	for _i:int in _e.enemies.size():
		_lines.append("Section %d: %d waves, %s" % [_i + 1, _layout.sections[_i].get("waves", []).size(), ", ".join(_e.enemies[_i])])
	var _by_category:Dictionary = {}
	for _id:StringName in _e.counts:
		var _category:MapCatalogCategory = catalog.category_of(_id)
		var _name:String = _category.display_name if _category != null else "Other"
		var _item:MapCatalogItem = catalog.item(_id)
		_by_category[_name] = _by_category.get(_name, []) + ["%s x%d" % [_item.display_name if _item != null else String(_id), _e.counts[_id]]]
	for _name:String in _by_category:
		_lines.append("%s: %s" % [_name, ", ".join(_by_category[_name])])
	for _link:Dictionary in _e.links:
		var _target:String = String(_link.room)
		var _other:Dictionary = entries.get(_target.trim_prefix("room_"), {})
		_lines.append("%s -> %s%s" % [_link.kind, _target, ("  " + _other.name) if !_other.is_empty() else ""])
	return "\n".join(_lines)
