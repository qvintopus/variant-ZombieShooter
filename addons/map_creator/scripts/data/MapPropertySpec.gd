## One editable property of a catalog item (a LayoutEntity props key), shown by the
## property inspector. When `node_property` is set the value is also written onto the
## baked node as that export (generic scene items); otherwise the baker reads the key.
class_name MapPropertySpec
extends Resource

enum Type { INT, FLOAT, BOOL, STRING, ENUM, ROOM, SECTION }

## LayoutEntity.props key.
@export var key:StringName
@export var label:String
@export var type:Type = Type.INT
## Export written on the baked/live node (empty: the baker handles the key itself).
@export var node_property:StringName
@export var min_value:float = 0.0
@export var max_value:float = 10.0
## ENUM choices (stored as the index).
@export var options:PackedStringArray = []
@export_multiline var hint:String

## Value as text for a .tscn property line.
func to_scene_value(value:Variant)->String:
	if type == Type.ROOM:
		return "\"%s\"" % value
	return var_to_str(value)
