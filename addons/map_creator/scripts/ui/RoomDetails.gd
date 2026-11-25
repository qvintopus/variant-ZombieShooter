## Details of a room (room browser, campaign graph): RoomIndex.describe() text, then
## its exits ("Leads to") and the exits of other rooms leading here ("Linked from") as
## rows with an open button. Opening lands on the matching stairs selected (the arrival
## stairs, or the linking exit); `opened` tells the panel to close. Given relink rows
## (campaign graph), each exit also gets a dropdown of the exits it can lead to.
class_name RoomDetails
extends VBoxContainer

signal opened
## Exit `index` of room `key` picked exit `to_index` of `to_key` ("" = unlink).
signal relink_requested(key:String, index:int, to_key:String, to_index:int)

## Dropdown text of a broken current link.
var broken_color:Color = Color(1, 0.45, 0.3)

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

## `extra`: lines added at the end (problems); `relinks`: CampaignGraph._relink_rows.
func show_room(key:String, extra:String = "", relinks:Array = [])->void:
	_clear()
	var _e:Dictionary = index.entries.get(key, {})
	if _e.is_empty():
		text = ""
		return
	var _lines:PackedStringArray = [index.describe(key, creator.catalog, false)]
	_label(_lines[0])
	if !relinks.is_empty():
		_label("Links (pick to rewire):")
		_lines.append("Links:")
		for _relink:Dictionary in relinks:
			_lines.append(_relink_row(key, _relink))
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

## Label + dropdown: (unlinked), the current target when it isn't an option (broken), the
## options. Picking one asks the graph to relink.
func _relink_row(key:String, relink:Dictionary)->String:
	var _row:HBoxContainer = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", 1)
	add_child(_row)
	var _l:Label = Label.new()
	_l.text = " " + String(relink.label)
	_l.clip_text = true
	_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_l.size_flags_stretch_ratio = 0.6
	_row.add_child(_l)
	var _pick:OptionButton = OptionButton.new()
	_pick.focus_mode = Control.FOCUS_NONE
	_pick.clip_text = true
	_pick.fit_to_longest_item = false
	_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var _choices:Array = [{"key": "", "index": -1}]
	_pick.add_item("(unlinked)")
	var _state:String = String(relink.state).replace("_", " ")
	var _broken:bool = !(relink.state in [CampaignLinks.LINKED, CampaignLinks.UNKNOWN])
	var _current:int = 0
	if relink.selected < 0 && !String(relink.current).is_empty():
		_current = _pick.item_count
		_pick.add_item("%s (%s)" % [relink.current, _state])
		_choices.append({})
	for _i:int in relink.options.size():
		if _i == relink.selected:
			_current = _pick.item_count
		_pick.add_item("%s%s" % [relink.options[_i].text, " (%s)" % _state if _i == relink.selected && _broken else ""])
		_choices.append(relink.options[_i])
	_pick.select(_current)
	_pick.tooltip_text = "Where %s leads (stairs link both ways; their old partners get unlinked)" % relink.label
	if _broken:
		_pick.add_theme_color_override(&"font_color", broken_color)
		_pick.tooltip_text += "\nBroken: " + _state
	var _index:int = relink.index
	_pick.item_selected.connect(func (i:int)->void:
		if _choices[i].is_empty():
			return
		relink_requested.emit(key, _index, _choices[i].key, _choices[i].index))
	_row.add_child(_pick)
	return "%s -> %s" % [relink.label, _pick.get_item_text(_current)]

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
