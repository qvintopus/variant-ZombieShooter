## Inventory screen: the 5 weapon quick slots on top (the HUD hotbar hides while
## it's open), the cell grid below. Mouse: drag and drop (outside the panel
## drops a weapon on the floor), click = pick / place, right click = quick move.
## Pad / keyboard: move the focus, accept = pick / place / swap, drop key drops
## the focused weapon, cancel puts back what's held or closes.
## Shift held while picking / dragging (or the split action on a pad) takes half
## a stack; dropping a stack onto the same item merges it.
## open_with() shows a second grid beside it (the home chest: scrolls, a few
## rows visible); Ctrl + click (pad: the drop key) sends a whole stack across.
## Solo the world pauses (room PauseProcessingComponent); online it keeps going
## and only the player stops (NetPlayers).
class_name InventoryScreen
extends Control

signal opened
signal closed

const GROUP:StringName = &"inventory_screen"

@export var style:InventoryStyle
@export var grid:InventoryGridResource
## Quick slots (the HUD hotbar's inventory)
@export var weapons:ItemCollectionResource
@export var weapon_upgrades:WeaponUpgradeResource
@export var open_resource:BoolResource
@export var pause_resource:BoolResource
@export var transition_resource:BoolResource
@export var action_resource:ActionResource
@export var player_reference:ReferenceNodeResource
## Hidden while the screen is open (no doubled quick slots)
@export var hud_hotbar:CanvasItem
## Held while picking up / dragging: take half the stack
@export var split_key:Key = KEY_SHIFT
## Pad: picks up half the focused stack (action name; empty = off)
@export var split_action:StringName = &"interact"
## Held while clicking: the whole stack goes to the other inventory (chest open)
@export var transfer_key:Key = KEY_CTRL
## Chest rows shown at once (the rest scroll)
@export_range(1, 16, 1) var side_visible_rows:int = 4
## Hint line, alone / with the chest beside
@export_multiline var hint_text:String = "Drag: move   Shift: half   Right click: quick move   Drop key: drop"
@export_multiline var side_hint_text:String = "Drag: move   Shift: half   Ctrl+click / right click: other side"

@export_group("Nodes")
@export var dim:ColorRect
@export var panel:PanelContainer
@export var title_label:Label
@export var quick_row:HBoxContainer
@export var grid_container:GridContainer
@export var info_label:Label
@export var hint_label:Label
## Drawn at the focused cell while the pad holds an item
@export var held_icon:TextureRect
## Second inventory (the chest), shown by open_with()
@export var side_panel:PanelContainer
@export var side_title_label:Label
@export var side_scroll:ScrollContainer
@export var side_grid_container:GridContainer

var quick_cells:Array[InventoryCellUI] = []
var grid_cells:Array[InventoryCellUI] = []
var side_cells:Array[InventoryCellUI] = []
## The chest while it's shown (open_with), else null
var side_grid:InventoryGridResource
var held:InventoryCellUI
## The held item is half its stack
var held_half:bool
var _hovered:InventoryCellUI
var _open_tween:Tween

## The screen in the HUD (null when there's none)
static func find(tree:SceneTree)->InventoryScreen:
	return tree.get_first_node_in_group(GROUP) as InventoryScreen if tree != null else null

func _ready()->void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if side_panel != null:
		side_panel.visible = false
	if open_resource != null:
		open_resource.set_value(false)
	_apply_style()
	if hint_label != null:
		hint_label.text = hint_text
	_build_quick()
	_build_grid()
	if grid != null:
		grid.changed_cells.connect(_refresh)
		grid.resized.connect(_build_grid)
	if weapons != null:
		weapons.updated.connect(_refresh)
		weapons.selected_changed.connect(_refresh)
	if pause_resource != null:
		pause_resource.changed_true.connect(close)
	if dim != null:
		dim.set_drag_forwarding(Callable(), _can_drop_outside, _drop_outside)
	tree_exiting.connect(_on_tree_exiting)
	_refresh()

func _on_tree_exiting()->void:
	if is_open():
		_set_open(false)

func is_open()->bool:
	return visible

func _apply_style()->void:
	if style == null:
		style = InventoryStyle.new()
	if dim != null:
		dim.color = style.dim_color
	if panel != null:
		var _box:StyleBoxFlat = StyleBoxFlat.new()
		_box.bg_color = style.panel_color
		_box.border_color = style.panel_border_color
		_box.set_border_width_all(1)
		_box.set_content_margin_all(style.panel_padding)
		panel.add_theme_stylebox_override("panel", _box)
		if side_panel != null:
			side_panel.add_theme_stylebox_override("panel", _box)
	if side_title_label != null:
		side_title_label.add_theme_font_size_override("font_size", style.title_font_size)
	if title_label != null:
		title_label.text = style.title
		title_label.add_theme_font_size_override("font_size", style.title_font_size)
	if info_label != null:
		info_label.add_theme_font_size_override("font_size", style.info_font_size)
		info_label.add_theme_color_override("font_color", style.info_color)
	if hint_label != null:
		hint_label.add_theme_font_size_override("font_size", style.hint_font_size)
		hint_label.add_theme_color_override("font_color", style.hint_color)
	for _box_node:Control in [quick_row, grid_container, side_grid_container]:
		if _box_node != null:
			_box_node.add_theme_constant_override("separation", style.cell_gap)
			_box_node.add_theme_constant_override("h_separation", style.cell_gap)
			_box_node.add_theme_constant_override("v_separation", style.cell_gap)

func _new_cell(area:InventoryCellUI.Area, index:int)->InventoryCellUI:
	var _cell:InventoryCellUI = InventoryCellUI.new()
	_cell.name = ("Quick%d" if area == InventoryCellUI.Area.QUICK else "Chest%d" if area == InventoryCellUI.Area.CHEST else "Cell%d") % index
	_cell.setup(self, area, index)
	return _cell

func _build_quick()->void:
	if quick_row == null || weapons == null:
		return
	for _child:Node in quick_row.get_children():
		quick_row.remove_child(_child)
		_child.queue_free()
	quick_cells.clear()
	for _i:int in maxi(weapons.max_items, 1):
		var _cell:InventoryCellUI = _new_cell(InventoryCellUI.Area.QUICK, _i)
		quick_row.add_child(_cell)
		quick_cells.append(_cell)

func _build_grid()->void:
	if grid_container == null || grid == null:
		return
	held = null
	_hovered = null
	for _child:Node in grid_container.get_children():
		grid_container.remove_child(_child)
		_child.queue_free()
	grid_cells.clear()
	grid_container.columns = grid.width()
	for _i:int in grid.capacity():
		var _cell:InventoryCellUI = _new_cell(InventoryCellUI.Area.GRID, _i)
		grid_container.add_child(_cell)
		grid_cells.append(_cell)
	_refresh()

func _build_side()->void:
	if side_grid_container == null:
		return
	if held != null && held.area == InventoryCellUI.Area.CHEST:
		_cancel_held()
	if _hovered != null && _hovered.area == InventoryCellUI.Area.CHEST:
		_hovered = null
	for _child:Node in side_grid_container.get_children():
		side_grid_container.remove_child(_child)
		_child.queue_free()
	side_cells.clear()
	if side_grid == null:
		return
	side_grid_container.columns = side_grid.width()
	for _i:int in side_grid.capacity():
		var _cell:InventoryCellUI = _new_cell(InventoryCellUI.Area.CHEST, _i)
		side_grid_container.add_child(_cell)
		side_cells.append(_cell)
	if side_scroll != null:
		var _rows:int = mini(side_visible_rows, side_grid.height())
		side_scroll.custom_minimum_size.y = _rows * style.cell_size.y + maxi(_rows - 1, 0) * style.cell_gap
		side_scroll.scroll_vertical = 0

func _set_side(value:InventoryGridResource, title:String = "")->void:
	if side_grid != null:
		if side_grid.changed_cells.is_connected(_refresh):
			side_grid.changed_cells.disconnect(_refresh)
		if side_grid.resized.is_connected(_build_side):
			side_grid.resized.disconnect(_build_side)
	side_grid = value
	if side_grid != null:
		side_grid.changed_cells.connect(_refresh)
		side_grid.resized.connect(_build_side)
	if side_title_label != null:
		side_title_label.text = title
	if side_panel != null:
		side_panel.visible = side_grid != null
	if hint_label != null:
		hint_label.text = side_hint_text if side_grid != null else hint_text
	_build_side()

# --- open / close ------------------------------------------------------------

func _input(event:InputEvent)->void:
	if action_resource == null:
		return
	var _toggle:bool = !action_resource.inventory_action.is_empty() && event.is_action_pressed(action_resource.inventory_action)
	if !is_open():
		if _toggle && can_open():
			open()
			get_viewport().set_input_as_handled()
		return
	if _toggle || event.is_action_released(action_resource.pause_action):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if held != null:
			_cancel_held()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif !action_resource.drop_action.is_empty() && event.is_action_pressed(action_resource.drop_action):
		# with the chest open the drop key sends the stack across instead
		if _hovered != null && side_grid != null:
			transfer(_hovered)
		elif _hovered != null:
			drop_to_floor(_hovered)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		var _focus:InventoryCellUI = get_viewport().gui_get_focus_owner() as InventoryCellUI
		if _focus != null:
			press(_focus, split_down())
			get_viewport().set_input_as_handled()
	elif !split_action.is_empty() && InputMap.has_action(split_action) && event.is_action_pressed(split_action):
		var _focus:InventoryCellUI = get_viewport().gui_get_focus_owner() as InventoryCellUI
		if _focus != null:
			press(_focus, true)
			get_viewport().set_input_as_handled()

## Shift (split_key) held right now
func split_down()->bool:
	return split_key != KEY_NONE && Input.is_physical_key_pressed(split_key)

## Ctrl (transfer_key) held right now, with a second inventory open
func transfer_down()->bool:
	return side_grid != null && transfer_key != KEY_NONE && Input.is_physical_key_pressed(transfer_key)

func can_open()->bool:
	if pause_resource != null && pause_resource.value:
		return false
	if transition_resource != null && transition_resource.value:
		return false
	if player_reference != null && !is_instance_valid(player_reference.node):
		return false
	var _player:Node = player_reference.node if player_reference != null else null
	if _player != null:
		var _resources:ResourceNode = _player.get_node_or_null(^"ResourceNode") as ResourceNode
		var _health:HealthResource = _resources.get_resource("health") as HealthResource if _resources != null else null
		if _health != null && _health.is_dead:
			return false
	return true

## Opens with a second inventory beside the player's (the home chest).
func open_with(other:InventoryGridResource, title:String = "")->void:
	if is_open():
		close()
	_set_side(other, title)
	open()

func open()->void:
	if is_open():
		return
	if grid != null:
		grid.relayout()
	_set_open(true)
	_refresh()
	_play(style.open_sound)
	var _first:InventoryCellUI = quick_cells[weapons.selected] if weapons != null && weapons.selected < quick_cells.size() else (grid_cells[0] if !grid_cells.is_empty() else null)
	if _first != null:
		_first.grab_focus()
	if panel != null && style.open_time > 0.0:
		if _open_tween != null:
			_open_tween.kill()
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2.ONE * style.open_from_scale
		modulate.a = 0.0
		_open_tween = create_tween().set_parallel()
		_open_tween.tween_property(panel, ^"scale", Vector2.ONE, style.open_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_open_tween.tween_property(self, ^"modulate:a", 1.0, style.open_time)
	opened.emit()

func close()->void:
	if !is_open():
		return
	_cancel_held()
	_set_open(false)
	if side_grid != null:
		_set_side(null)
	_play(style.close_sound)
	closed.emit()

func _set_open(value:bool)->void:
	visible = value
	if hud_hotbar != null:
		hud_hotbar.visible = !value
	if open_resource != null:
		open_resource.set_value(value)
	if !value:
		var _focus:Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		if _focus != null && is_ancestor_of(_focus):
			_focus.release_focus()

# --- view --------------------------------------------------------------------

func _refresh()->void:
	if weapons != null:
		for _i:int in quick_cells.size():
			var _item:ItemResource = weapons.list[_i] if _i < weapons.list.size() else null
			quick_cells[_i].show_item(_item.icon if _item != null else null, "", style.count_color, _level_text(_item))
			quick_cells[_i].set_selected(_item != null && _i == weapons.selected)
	if grid != null:
		for _i:int in grid_cells.size():
			_show_grid_cell(grid, grid_cells[_i], grid.get_cell(_i))
	if side_grid != null:
		for _i:int in side_cells.size():
			_show_grid_cell(side_grid, side_cells[_i], side_grid.get_cell(_i))
	if _hovered != null && is_instance_valid(_hovered):
		_update_info(_hovered)

func _show_grid_cell(source:InventoryGridResource, cell:InventoryCellUI, entry:Variant)->void:
	if entry == null:
		cell.show_item(null, "", style.count_color, "")
		return
	var _entry:Dictionary = entry
	if _entry.has("weapon"):
		var _item:ItemResource = _entry.weapon
		cell.show_item(_item.icon, "", style.count_color, _level_text(_item))
		return
	var _def:InventoryItemDef = source.database.def(_entry.id) if source.database != null else null
	var _n:int = int(_entry.get("n", 0))
	var _color:Color = style.count_color
	var _text:String = style.format_amount(_n)
	if _def != null && !_def.is_infinite():
		if _n > _def.stack_size && source.counter_backed:
			_color = style.overflow_color
			_text += "+"
		elif _n == _def.stack_size:
			_color = style.full_stack_color
	cell.show_item(_def.icon if _def != null else null, _text, _color, "")

func _level_text(item:ItemResource)->String:
	if item == null || weapon_upgrades == null:
		return ""
	var _level:int = weapon_upgrades.get_level(item.scene_path)
	return "L%d" % _level if _level > 0 else ""

func on_cell_hovered(cell:InventoryCellUI)->void:
	_hovered = cell
	_update_info(cell)
	if held != null && held_icon != null:
		_place_held_icon(cell)

func _update_info(cell:InventoryCellUI)->void:
	if info_label == null:
		return
	info_label.text = describe(cell)
	var _from:InventoryGridResource = grid_of(held) if held != null else null
	if held != null && held_half && _from != null:
		info_label.text = "Holding %d  -  %s" % [_from.half_of(held.index), info_label.text]

func describe(cell:InventoryCellUI)->String:
	var _weapon:ItemResource = weapon_of(cell)
	if _weapon != null:
		var _text:String = _weapon.resource_name
		if weapon_upgrades != null:
			var _max:int = weapon_upgrades.max_level(_weapon.scene_path)
			if _max > 0:
				_text += "  Lv %d/%d" % [weapon_upgrades.get_level(_weapon.scene_path), _max]
		return _text
	var _def:InventoryItemDef = def_of(cell)
	if _def != null:
		var _in:InventoryGridResource = grid_of(cell)
		var _cells:int = _in.cells_of(_def.id).size()
		var _total:int = _def.amount() if _in.counter_backed else _in.total_of(_def.id)
		var _text:String = "%s  %d" % [_def.display_name, _total]
		if !_def.is_infinite():
			_text += "  (%d/cell)" % _def.stack_size
		if _cells > 1:
			_text += "  %d cells" % _cells
		return _text
	return "Weapon slot %d" % (cell.index + 1) if cell.area == InventoryCellUI.Area.QUICK else ""

# --- rules -------------------------------------------------------------------

## The grid a cell shows (null for quick slots)
func grid_of(cell:InventoryCellUI)->InventoryGridResource:
	if cell == null:
		return null
	match cell.area:
		InventoryCellUI.Area.GRID:
			return grid
		InventoryCellUI.Area.CHEST:
			return side_grid
	return null

func weapon_of(cell:InventoryCellUI)->ItemResource:
	if cell.area == InventoryCellUI.Area.QUICK:
		return weapons.list[cell.index] if weapons != null && cell.index < weapons.list.size() else null
	var _in:InventoryGridResource = grid_of(cell)
	return _in.weapon_at(cell.index) if _in != null else null

func def_of(cell:InventoryCellUI)->InventoryItemDef:
	var _in:InventoryGridResource = grid_of(cell)
	if _in == null || _in.database == null:
		return null
	var _entry:Variant = _in.get_cell(cell.index)
	if _entry == null || !(_entry as Dictionary).has("id"):
		return null
	return _in.database.def(_entry.id)

func has_content(cell:InventoryCellUI)->bool:
	if cell.area == InventoryCellUI.Area.QUICK:
		return weapon_of(cell) != null
	var _in:InventoryGridResource = grid_of(cell)
	return _in != null && _in.get_cell(cell.index) != null

## Is this a half-stack move (a splittable stack in a grid)?
func _is_split(from:InventoryCellUI, half:bool)->bool:
	if !half || from.area == InventoryCellUI.Area.QUICK:
		return false
	var _def:InventoryItemDef = def_of(from)
	return _def != null && !_def.is_infinite() && grid_of(from).amount_at(from.index) >= 2

## Currencies stay in the grids (player's or chest); weapons go anywhere. Half
## a stack goes into an empty cell or onto the same item. Across grids a stack
## goes into an empty cell or onto the same item (as much as fits).
func can_place(from:InventoryCellUI, to:InventoryCellUI, half:bool = false)->bool:
	if from == null || to == null || from == to || !has_content(from):
		return false
	var _q:InventoryCellUI.Area = InventoryCellUI.Area.QUICK
	if to.area == _q:
		# onto a quick slot: weapons only
		if weapon_of(from) == null:
			return false
		if from.area == _q:
			return true
		return to.index < weapons.list.size() || weapons.list.size() < weapons.max_items
	var _to:InventoryGridResource = grid_of(to)
	if _to == null:
		return false
	if from.area == _q:
		# quick slot weapon onto a currency stack: no
		return _to.get_cell(to.index) == null || _to.weapon_at(to.index) != null
	var _from:InventoryGridResource = grid_of(from)
	if _from == _to:
		if _is_split(from, half):
			return _from.can_split(from.index, to.index)
		return true
	if weapon_of(from) != null:
		return _to.get_cell(to.index) == null || _to.weapon_at(to.index) != null
	return _from.amount_at(from.index) > 0 && _to.room_at(to.index, _from.get_cell(from.index).id) > 0

func place(from:InventoryCellUI, to:InventoryCellUI, half:bool = false)->bool:
	if !can_place(from, to, half):
		to.flash_invalid()
		_play(style.invalid_sound)
		return false
	var _q:InventoryCellUI.Area = InventoryCellUI.Area.QUICK
	var _from:InventoryGridResource = grid_of(from)
	var _to:InventoryGridResource = grid_of(to)
	if from.area == _q && to.area == _q:
		weapons.move(from.index, mini(to.index, weapons.list.size() - 1))
	elif _from != null && _from == _to:
		if _is_split(from, half):
			_from.split(from.index, to.index)
		else:
			_from.move(from.index, to.index)
	elif from.area == _q:
		# quick slot -> grid: into the cell, or swap with the weapon there
		var _there:ItemResource = _to.weapon_at(to.index)
		if _there != null:
			_to.replace_weapon(to.index, weapons.list[from.index])
			weapons.replace_at(from.index, _there)
		else:
			var _item:ItemResource = weapons.remove_at(from.index)
			_to.put_weapon(_item, to.index)
	elif to.area == _q:
		# grid -> quick slot: swap with what's there, or into the next free slot
		var _item:ItemResource = _from.weapon_at(from.index)
		if to.index < weapons.list.size():
			var _old:ItemResource = weapons.replace_at(to.index, _item)
			_from.replace_weapon(from.index, _old)
		else:
			_from.take_weapon(from.index)
			weapons.append(_item)
	elif weapon_of(from) != null:
		# weapon across grids: into the cell, or swap weapons
		var _item:ItemResource = _from.take_weapon(from.index)
		var _old:ItemResource = _to.replace_weapon(to.index, _item)
		if _old != null:
			_from.put_weapon(_old, from.index)
	else:
		# currency across grids: the stack (or half) as far as it fits
		var _id:StringName = _from.get_cell(from.index).id
		var _amount:int = _from.half_of(from.index) if _is_split(from, half) else _from.amount_at(from.index)
		_amount = mini(_amount, _to.room_at(to.index, _id))
		_to.add_at(to.index, _id, _from.remove_amount(from.index, _amount))
	_play(style.place_sound)
	to.pop()
	_refresh()
	return true

## Ctrl + click / pad drop key with the chest open: the whole stack to the
## other inventory (same-item stacks first, then free cells; weapons from the
## chest go to the grid, else a quick slot).
func transfer(cell:InventoryCellUI)->bool:
	if side_grid == null || cell == null || !has_content(cell):
		return false
	if held != null:
		_cancel_held()
	var _from:InventoryGridResource = grid_of(cell)
	var _to:InventoryGridResource = grid if cell.area == InventoryCellUI.Area.CHEST else side_grid
	var _weapon:ItemResource = weapon_of(cell)
	var _moved:bool = false
	if _weapon != null:
		var _free:int = _to.first_free()
		if _free >= 0:
			if cell.area == InventoryCellUI.Area.QUICK:
				weapons.remove_at(cell.index)
			else:
				_from.take_weapon(cell.index)
			_to.put_weapon(_weapon, _free)
			_moved = true
		elif cell.area == InventoryCellUI.Area.CHEST && weapons.list.size() < weapons.max_items:
			_from.take_weapon(cell.index)
			weapons.append(_weapon)
			_moved = true
	else:
		var _id:StringName = _from.get_cell(cell.index).id
		var _amount:int = mini(_from.amount_at(cell.index), _to.room_for(_id))
		if _amount > 0:
			_to.add_amount(_id, _from.remove_amount(cell.index, _amount))
			_moved = true
	if !_moved:
		cell.flash_invalid()
		_play(style.invalid_sound)
		return false
	_play(style.place_sound)
	cell.pop()
	_refresh()
	return true

## Pad / click: pick up (half the stack with `half`), then place / swap /
## merge on the next press.
func press(cell:InventoryCellUI, half:bool = false)->void:
	if held == null:
		if !has_content(cell):
			return
		held = cell
		held_half = _is_split(cell, half)
		cell.set_held(true)
		_play(style.pick_sound)
		_place_held_icon(cell)
		_update_info(cell)
		return
	var _from:InventoryCellUI = held
	var _half:bool = held_half
	_cancel_held()
	if _from != cell:
		place(_from, cell, _half)

## Right click: weapon between quick slots and grid in one go (chest cells:
## across to the player).
func quick_move(cell:InventoryCellUI)->void:
	if cell.area == InventoryCellUI.Area.CHEST:
		transfer(cell)
		return
	var _weapon:ItemResource = weapon_of(cell)
	if _weapon == null:
		return
	var _target:InventoryCellUI = null
	if cell.area == InventoryCellUI.Area.GRID:
		if weapons.list.size() < weapons.max_items:
			_target = quick_cells[weapons.list.size()]
	else:
		var _free:int = grid.first_free()
		if _free >= 0 && _free < grid_cells.size():
			_target = grid_cells[_free]
	if _target == null:
		cell.flash_invalid()
		_play(style.invalid_sound)
		return
	place(cell, _target)

func on_drag_started(_cell:InventoryCellUI)->void:
	_cancel_held()

func _cancel_held()->void:
	if held != null && is_instance_valid(held):
		held.set_held(false)
	held = null
	held_half = false
	if held_icon != null:
		held_icon.visible = false

func _place_held_icon(cell:InventoryCellUI)->void:
	if held_icon == null || held == null:
		return
	held_icon.texture = held.icon_rect.texture
	held_icon.visible = held_icon.texture != null
	held_icon.size = cell.size
	held_icon.global_position = cell.global_position + style.held_offset

## Weapons only: out of the inventory onto the floor at the player's feet.
func drop_to_floor(cell:InventoryCellUI)->bool:
	var _weapon:ItemResource = weapon_of(cell)
	if _weapon == null:
		cell.flash_invalid()
		_play(style.invalid_sound)
		return false
	if held == cell:
		_cancel_held()
	if cell.area == InventoryCellUI.Area.QUICK:
		var _was:int = weapons.selected
		weapons.selected = cell.index
		weapons.drop()
		weapons.set_selected(mini(_was, maxi(weapons.list.size() - 1, 0)))
	else:
		if cell.area == InventoryCellUI.Area.CHEST:
			return false
		var _inventory:PlayerInventory = PlayerInventory.local(get_tree())
		if _inventory != null:
			_inventory.drop_weapon(cell.index)
		else:
			return false
	_play(style.place_sound)
	_refresh()
	return true

func _can_drop_outside(_at:Vector2, data:Variant)->bool:
	var _from:InventoryCellUI = InventoryCellUI._cell_of(data)
	return _from != null && weapon_of(_from) != null

func _drop_outside(_at:Vector2, data:Variant)->void:
	var _from:InventoryCellUI = InventoryCellUI._cell_of(data)
	if _from != null:
		drop_to_floor(_from)

func _play(sound:SoundResource)->void:
	if sound != null:
		sound.play_managed()
