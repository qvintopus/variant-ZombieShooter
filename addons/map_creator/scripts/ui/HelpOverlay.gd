## F1 (preset.key_help): every map creator key and mouse action, read from the preset.
class_name HelpOverlay
extends PanelContainer

@export var creator:MapCreator

var _grid:GridContainer

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if !creator.is_node_ready():
		await creator.ready
	var _style:StyleBoxFlat = StyleBoxFlat.new()
	_style.bg_color = Color(creator.preset.bar_color, 0.97)
	_style.set_content_margin_all(4)
	add_theme_stylebox_override(&"panel", _style)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override(&"h_separation", 8)
	_grid.add_theme_constant_override(&"v_separation", 0)
	add_child(_grid)
	creator.help_requested.connect(toggle)
	gui_input.connect(func (event:InputEvent)->void:
		if event is InputEventMouseButton && event.pressed:
			visible = false)

func toggle()->void:
	visible = !visible
	if visible:
		for _child:Node in _grid.get_children():
			_child.free()
		for _row:Array in rows():
			for _text:String in _row:
				var _label:Label = Label.new()
				_label.text = _text
				_grid.add_child(_label)
		reset_size()
		position = ((get_parent() as Control).size - size) * 0.5

## [action, keys] rows.
func rows()->Array:
	var _p:MapCreatorPreset = creator.preset
	var _k:Callable = func (key:Key)->String: return OS.get_keycode_string(key)
	var _rows:Array = [
		["Edit / Play", _k.call(_p.key_toggle_edit)], ["Help", _k.call(_p.key_help)],
		["Paint / Erase", "%s / %s" % [_k.call(_p.key_paint), _k.call(_p.key_erase)]],
		["Fill / Pick", "%s / %s (Alt+click picks)" % [_k.call(_p.key_fill), _k.call(_p.key_pick)]],
		["Select / Move", "%s / %s" % [_k.call(_p.key_select), _k.call(_p.key_move)]],
		["Line brush", _k.call(_p.key_line)], ["Items", "%s / %s, categories 1-9" % [_k.call(_p.key_prev_item), _k.call(_p.key_next_item)]],
		["Clean visuals", _k.call(_p.key_clean)], ["Rooms / Campaign map", "%s / %s" % [_k.call(_p.key_browse), _k.call(_p.key_graph)]],
		["Waves / Problems", "%s / %s" % [_k.call(_p.key_waves), _k.call(_p.key_problems)]],
		["Play from cursor", _k.call(_p.key_play_here)],
		["Undo / Redo / Save", "Ctrl+%s / Ctrl+%s / Ctrl+%s" % [_k.call(_p.key_undo), _k.call(_p.key_redo), _k.call(_p.key_save)]],
		["Copy / Paste / Duplicate", "Ctrl+C / Ctrl+V / Ctrl+D"], ["Restore autosave", "Ctrl+R"],
		["Shift room", "Ctrl+Shift+arrows"], ["Delete selection", "Delete"],
		["Select", "Ctrl+click toggles, Ctrl+drag box"], ["Menu", "Right click"],
		["Camera", "WASD / arrows, middle drag, wheel"], ["Cancel", "Esc"],
	]
	return _rows
