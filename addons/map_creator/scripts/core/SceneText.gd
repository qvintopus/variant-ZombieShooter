## Minimal .tscn writer for an inherited scene: ext/sub resources, then node overrides.
## (A packed instance can't be saved as inherited from a script, so LayoutBaker writes
## the overrides out itself.)
class_name SceneText
extends RefCounted

var uid:String
var editable:PackedStringArray = []
var _ext_ids:Dictionary = {}
var _ext_lines:PackedStringArray = []
var _sub_lines:PackedStringArray = []
var _node_lines:PackedStringArray = []

## Returns ExtResource("id") for path, registering it once.
func ext(type:String, path:String)->String:
	if !_ext_ids.has(path):
		var _id:String = "%d_%s" % [_ext_ids.size() + 1, path.get_file().get_basename().left(12)]
		_ext_ids[path] = _id
		var _uid:int = ResourceLoader.get_resource_uid(path)
		var _uid_text:String = " uid=\"%s\"" % ResourceUID.id_to_text(_uid) if _uid != ResourceUID.INVALID_ID else ""
		_ext_lines.append("[ext_resource type=\"%s\"%s path=\"%s\" id=\"%s\"]" % [type, _uid_text, path, _id])
	return "ExtResource(\"%s\")" % _ext_ids[path]

## Adds a sub resource and returns SubResource("id").
func sub(type:String, props:Dictionary)->String:
	var _id:String = "%s_%d" % [type, _sub_lines.size() + 1]
	_sub_lines.append("[sub_resource type=\"%s\" id=\"%s\"]\n%s" % [type, _id, _props_text(props)])
	return "SubResource(\"%s\")" % _id

## parent "" is the root; a node with type or instance is new, else an override.
func node(name:String, parent:String, props:Dictionary, instance:String = "", type:String = "")->void:
	var _head:String = "[node name=\"%s\"" % name
	if !type.is_empty():
		_head += " type=\"%s\"" % type
	if !parent.is_empty():
		_head += " parent=\"%s\"" % parent
	var _paths:PackedStringArray = []
	for _key:String in props:
		if String(props[_key]).begins_with("NodePath(") || String(props[_key]).begins_with("[NodePath("):
			_paths.append("\"%s\"" % _key)
	if !_paths.is_empty():
		_head += " node_paths=PackedStringArray(%s)" % ", ".join(_paths)
	if !instance.is_empty():
		_head += " instance=%s" % instance
	_node_lines.append(_head + "]\n" + _props_text(props))

func _props_text(props:Dictionary)->String:
	var _text:String = ""
	for _key:String in props:
		_text += "%s = %s\n" % [_key, props[_key]]
	return _text

func text()->String:
	var _parts:PackedStringArray = ["[gd_scene format=4 uid=\"%s\"]\n" % uid, "\n".join(_ext_lines) + "\n"]
	for _line:String in _sub_lines:
		_parts.append(_line)
	for _line:String in _node_lines:
		_parts.append(_line)
	for _path:String in editable:
		_parts.append("[editable path=\"%s\"]\n" % _path)
	return "\n".join(_parts)
