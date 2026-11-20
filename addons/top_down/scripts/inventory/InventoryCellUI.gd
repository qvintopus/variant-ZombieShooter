## One cell of the inventory screen: a quick slot or a grid cell. Mouse drags
## and pad / keyboard presses go to the InventoryScreen, which owns the rules.
class_name InventoryCellUI
extends TextureRect

enum Area { QUICK, GRID }

var area:Area
var index:int
var screen:InventoryScreen

var icon_rect:TextureRect
var count_label:Label
var level_label:Label
var _hovered:bool
var _held:bool
var _selected:bool
var _pop_tween:Tween
var _flash_tween:Tween

func setup(owner_screen:InventoryScreen, cell_area:Area, cell_index:int)->void:
	screen = owner_screen
	area = cell_area
	index = cell_index
	var _style:InventoryStyle = screen.style
	custom_minimum_size = _style.cell_size
	size = _style.cell_size
	pivot_offset = _style.cell_size * 0.5
	texture = _style.frame_texture
	stretch_mode = TextureRect.STRETCH_SCALE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP

	icon_rect = TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.pivot_offset = _style.cell_size * 0.5
	icon_rect.scale = Vector2.ONE * _style.icon_scale
	add_child(icon_rect)

	count_label = _label("Count", _style.count_font_size, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_BOTTOM)
	level_label = _label("Level", _style.count_font_size, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	level_label.add_theme_color_override("font_color", _style.level_color)

	focus_entered.connect(_set_hovered.bind(true))
	focus_exited.connect(_set_hovered.bind(false))
	mouse_entered.connect(_on_mouse_entered)

func _label(label_name:String, font_size:int, h:HorizontalAlignment, v:VerticalAlignment)->Label:
	var _label_node:Label = Label.new()
	_label_node.name = label_name
	_label_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label_node.offset_right = 0.0
	_label_node.offset_left = 1.0
	_label_node.offset_bottom = 1.0
	_label_node.offset_top = -1.0
	_label_node.horizontal_alignment = h
	_label_node.vertical_alignment = v
	_label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_node.add_theme_font_size_override("font_size", font_size)
	_label_node.add_theme_color_override("font_outline_color", Color.BLACK)
	_label_node.add_theme_constant_override("outline_size", 2)
	add_child(_label_node)
	return _label_node

## icon null = empty cell
func show_item(icon:Texture2D, count_text:String, count_color:Color, level_text:String)->void:
	icon_rect.texture = icon
	count_label.text = count_text
	count_label.add_theme_color_override("font_color", count_color)
	level_label.text = level_text
	_refresh()

func set_selected(value:bool)->void:
	_selected = value
	_refresh()

func set_held(value:bool)->void:
	_held = value
	_refresh()

func is_empty()->bool:
	return icon_rect.texture == null

func _set_hovered(value:bool)->void:
	_hovered = value
	_refresh()
	if value:
		screen.on_cell_hovered(self)

func _on_mouse_entered()->void:
	if screen.is_open():
		grab_focus()

func _refresh()->void:
	var _style:InventoryStyle = screen.style
	texture = _style.selected_texture if _selected && _style.selected_texture != null else _style.frame_texture
	var _tint:Color = _style.empty_modulate if is_empty() else Color.WHITE
	if _hovered:
		_tint = _tint * _style.hover_modulate
	self_modulate = _tint
	icon_rect.modulate = _style.held_modulate if _held else Color.WHITE

func pop()->void:
	var _style:InventoryStyle = screen.style
	if _pop_tween != null:
		_pop_tween.kill()
	scale = Vector2.ONE * _style.place_pop_scale
	_pop_tween = create_tween()
	_pop_tween.tween_property(self, ^"scale", Vector2.ONE, _style.place_pop_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func flash_invalid()->void:
	var _style:InventoryStyle = screen.style
	if _flash_tween != null:
		_flash_tween.kill()
	modulate = _style.invalid_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, ^"modulate", Color.WHITE, _style.invalid_flash_time)

# --- mouse -----------------------------------------------------------------

func _get_drag_data(_at:Vector2)->Variant:
	if is_empty() || !screen.is_open():
		return null
	var _preview:TextureRect = TextureRect.new()
	_preview.texture = icon_rect.texture
	_preview.position = -icon_rect.texture.get_size() * 0.5
	var _holder:Control = Control.new()
	_holder.add_child(_preview)
	set_drag_preview(_holder)
	screen.on_drag_started(self)
	return {"inventory_cell": self}

func _can_drop_data(_at:Vector2, data:Variant)->bool:
	var _from:InventoryCellUI = _cell_of(data)
	return _from != null && screen.can_place(_from, self)

func _drop_data(_at:Vector2, data:Variant)->void:
	var _from:InventoryCellUI = _cell_of(data)
	if _from != null:
		screen.place(_from, self)

static func _cell_of(data:Variant)->InventoryCellUI:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	return (data as Dictionary).get("inventory_cell") as InventoryCellUI

func _gui_input(event:InputEvent)->void:
	var _mouse:InputEventMouseButton = event as InputEventMouseButton
	if _mouse != null && !_mouse.pressed && !get_viewport().gui_is_dragging():
		if _mouse.button_index == MOUSE_BUTTON_LEFT:
			screen.press(self)
			accept_event()
		elif _mouse.button_index == MOUSE_BUTTON_RIGHT:
			screen.quick_move(self)
			accept_event()
