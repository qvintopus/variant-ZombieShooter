## Details of a room (room browser, campaign graph): RoomIndex.describe() text, then
## its exits ("Leads to") and the exits of other rooms leading here ("Linked from") as
## rows with an open button. Opening lands on the matching stairs selected (the arrival
## stairs, or the linking exit); `opened` tells the panel to close.
class_name RoomDetails
extends VBoxContainer

signal opened

var creator:MapCreator
var index:RoomIndex
## Everything shown, as plain text (tooltips, checks).
var text:String

func _init(owner:MapCreator, room_index:RoomIndex)->void:
	creator = owner
	index = room_index
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 1)

func show_message(message:String)->void:
	_clear()
	text = message
	_label(message)

## `extra`: lines added at the end (problems).
func show_room(key:String, extra:String = "")->void:
	_clear()
	var _e:Dictionary = index.entries.get(key, {})
	if _e.is_empty():
		text = ""
		return
	var _lines:PackedStringArray = [index.describe(key, creator.catalog, false)]
	_label(_lines[0])
	if !_e.links.is_empty():
		_label("Leads to:")
		_lines.append("Leads to:")
		for _link:Dictionary in _e.links:
			var _target:String = String(_link.room).trim_prefix("room_")
			var _focus:Dictionary = {}
			if _link.get("prop", "room") == "room":
				_focus = {"tags": PackedStringArray([String(_link.connect_tag)]), "back_to": "room_" + key}
			var _line:String = index.link_text(_link)
			_lines.append(_line)
			_row(" " + _line, "%s at %s" % [_link.kind, _link.cell], _target, _focus)
	var _from:Array = creator.rooms.link_entries(key) if creator.rooms != null else []
	if !_from.is_empty():
		_label("Linked from:")
		_lines.append("Linked from:")
		for _link:Dictionary in _from:
			var _line:String = "room_%s %s at %s" % [_link.room, _link.kind, _link.cell]
			_lines.append(_line)
			_row(" " + _line, String(_link.tag), _link.room, {"tags": PackedStringArray([_link.tag]), "back_to": "room_" + key})
	if !extra.is_empty():
		_label(extra)
		_lines.append(extra)
	text = "\n".join(_lines)

func _clear()->void:
	for _child:Node in get_children():
		remove_child(_child)
		_child.queue_free()

func _label(line:String)->Label:
	var _l:Label = Label.new()
	_l.text = line
	_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_l)
	return _l

func _row(line:String, hint:String, room_key:String, focus:Dictionary)->void:
	var _row:HBoxContainer = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", 1)
	add_child(_row)
	var _l:Label = Label.new()
	_l.text = line
	_l.tooltip_text = hint
	_l.mouse_filter = Control.MOUSE_FILTER_PASS
	_l.clip_text = true
	_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(_l)
	var _b:Button = Button.new()
	_b.icon = creator.open_room_icon()
	_b.tooltip_text = "Open room_%s with the linked stairs selected" % room_key
	_b.focus_mode = Control.FOCUS_NONE
	_b.pressed.connect(func ()->void:
		if creator.open_room(room_key, focus):
			opened.emit())
	_row.add_child(_b)
