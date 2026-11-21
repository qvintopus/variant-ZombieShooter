## Room search and switch (topbar Rooms / Tab in Edit mode). The search box matches every
## word against everything in a room (RoomIndex), the list shows the matches, and the info
## panel shows the selected room's details. Go (double click / Enter) switches to it.
class_name RoomBrowser
extends PanelContainer

@export var creator:MapCreator
@export var panel_size:Vector2 = Vector2(300, 180)

var index:RoomIndex = RoomIndex.new()
var _search:LineEdit
var _list:ItemList
var _info:Label
var _keys:Array[String] = []
var _actions:Dictionary = {}
var _delete_armed:String
var _delete_until:float

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var _style:StyleBoxFlat = StyleBoxFlat.new()
	_style.bg_color = Color(creator.preset.bar_color, 1.0)
	_style.set_content_margin_all(3)
	add_theme_stylebox_override(&"panel", _style)
	custom_minimum_size = panel_size
	clip_contents = true
	var _box:VBoxContainer = VBoxContainer.new()
	add_child(_box)
	var _top:HBoxContainer = HBoxContainer.new()
	_box.add_child(_top)
	_search = LineEdit.new()
	_search.placeholder_text = "Search rooms: name, key, enemy, contraption, look..."
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.text_changed.connect(func (_t:String)->void: refresh())
	_search.text_submitted.connect(func (_t:String)->void: go())
	_top.add_child(_search)
	var _go:Button = Button.new()
	_go.text = "Go"
	_go.pressed.connect(go)
	_top.add_child(_go)
	var _close:Button = Button.new()
	_close.text = "x"
	_close.pressed.connect(close)
	_top.add_child(_close)
	var _bar:HBoxContainer = HBoxContainer.new()
	_box.add_child(_bar)
	for _entry:Array in [
			["New", "New empty room in the workspace", _new_room],
			["Duplicate", "Copy the selected room under a new key", _duplicate_room],
			["Rename", "New key for the selected room; links to it are rewritten", _rename_room],
			["Delete", "Delete the selected room (press twice). In a mod: drops the mod's copy", _delete_room],
			["Import", "Make a layout from the selected hand-made scene", _import_room]]:
		var _b:Button = Button.new()
		_b.text = _entry[0]
		_b.tooltip_text = _entry[1]
		_b.focus_mode = Control.FOCUS_NONE
		_b.pressed.connect(_entry[2])
		_bar.add_child(_b)
		_actions[_entry[0]] = _b
	var _split:HBoxContainer = HBoxContainer.new()
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(_split)
	_list = ItemList.new()
	_list.custom_minimum_size.x = panel_size.x * 0.38
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func (_i:int)->void: _show_info())
	_list.item_activated.connect(func (_i:int)->void: go())
	_split.add_child(_list)
	var _scroll:ScrollContainer = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_split.add_child(_scroll)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_info)
	if !creator.is_node_ready():
		await creator.ready
	creator.browse_requested.connect(toggle)

func toggle()->void:
	if visible:
		close()
	else:
		open()

func open()->void:
	index.build(creator.baker, creator.catalog, creator.mod_state)
	visible = true
	size = panel_size
	position = ((get_parent() as Control).size - size) * 0.5
	refresh()
	_search.grab_focus()
	_search.select_all()

func close()->void:
	visible = false
	_search.release_focus()

## Fills the list with the rooms matching the search box; the current room is selected.
func refresh()->void:
	_keys = index.search(_search.text)
	_list.clear()
	for _key:String in _keys:
		var _e:Dictionary = index.entries[_key]
		_list.add_item("%s  %s%s" % [_key, _e.name, "  [%s]" % _e.source if !_e.source.is_empty() else ""])
		if _e.layout == null:
			_list.set_item_custom_fg_color(_list.item_count - 1, Color(1, 1, 1, 0.5))
	var _at:int = _keys.find(creator.key)
	if _at == -1 && !_keys.is_empty():
		_at = 0
	if _at != -1:
		_list.select(_at)
		_list.ensure_current_is_visible()
	_show_info()

func selected_key()->String:
	var _sel:PackedInt32Array = _list.get_selected_items()
	return _keys[_sel[0]] if !_sel.is_empty() && _sel[0] < _keys.size() else ""

func _show_info()->void:
	var _key:String = selected_key()
	_info.text = index.details(_key, creator.catalog, creator.rooms) if !_key.is_empty() else "No room matches."
	if _key.is_empty():
		for _name:String in _actions:
			_actions[_name].disabled = _name != "New"
		return
	var _e:Dictionary = index.entries[_key]
	var _rooms:RoomManager = creator.rooms
	_actions.Duplicate.disabled = _e.layout == null
	_actions.Import.disabled = _e.layout != null
	_actions.Rename.disabled = _e.layout == null || (creator.mod_state != null && creator.mod_state.is_active() && (_rooms.is_builtin(_key) || !_rooms.in_mod(_key)))
	_actions.Delete.disabled = _key == creator.key || (creator.mod_state != null && creator.mod_state.is_active() && !_rooms.in_mod(_key)) || (_e.layout == null)

## Re-reads the rooms (after a change) and selects `key`.
func _reload(key:String)->void:
	index.build(creator.baker, creator.catalog, creator.mod_state)
	refresh()
	var _at:int = _keys.find(key)
	if _at != -1:
		_list.select(_at)
		_list.ensure_current_is_visible()
		_show_info()

func _report(ok:bool, done:String, key:String)->void:
	creator.message.emit(done if ok && creator.rooms.last_message.is_empty() else creator.rooms.last_message)
	creator.rooms.last_message = ""
	if ok:
		_reload(key)

func _new_room()->void:
	creator.prompt_requested.emit("New room key (letters, digits, _)", creator.free_key("M"), func (key:String)->void:
		_report(creator.rooms.new_room(key, "", creator.layout), "Created room_%s" % key, key))

func _duplicate_room()->void:
	creator.ask_duplicate(selected_key(), false, func (ok:bool, key:String)->void:
		if ok:
			_reload(key))

func _rename_room()->void:
	creator.ask_rename(selected_key(), func (ok:bool, key:String)->void:
		if ok:
			_reload(key))

func _delete_room()->void:
	var _key:String = selected_key()
	var _now:float = Time.get_ticks_msec() / 1000.0
	if _delete_armed != _key || _now > _delete_until:
		_delete_armed = _key
		_delete_until = _now + 3.0
		var _links:int = creator.rooms.links_to(_key).size()
		creator.message.emit("Delete room_%s%s? Press Delete again" % [_key, " (%d doors/portals link to it)" % _links if _links > 0 else ""])
		return
	_delete_armed = ""
	_report(creator.rooms.delete_room(_key), "", _key)

func _import_room()->void:
	var _key:String = selected_key()
	_report(creator.rooms.import_room(_key), "", _key)


func go()->void:
	var _key:String = selected_key()
	if _key.is_empty():
		return
	if creator.switch_room(_key):
		close()

func _unhandled_key_input(event:InputEvent)->void:
	if visible && event is InputEventKey && event.pressed && event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
