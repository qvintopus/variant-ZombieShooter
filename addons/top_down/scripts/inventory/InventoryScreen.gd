## Inventory screen: the 5 weapon quick slots on top (the HUD hotbar hides while
## it's open), the cell grid below. Mouse: drag and drop (outside the panel
## drops a weapon on the floor), click = pick / place, right click = quick move.
## Pad / keyboard: move the focus, accept = pick / place / swap, drop key drops
## the focused weapon, cancel puts back what's held or closes.
## Shift held while picking / dragging (or the split action on a pad) takes half
## a stack; dropping a stack onto the same item merges it.
## Solo the world pauses (room PauseProcessingComponent); online it keeps going
## and only the player stops (NetPlayers).
class_name InventoryScreen
extends Control

signal opened
signal closed

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

var quick_cells:Array[InventoryCellUI] = []
var grid_cells:Array[InventoryCellUI] = []
var held:InventoryCellUI
## The held item is half its stack
var held_half:bool
var _hovered:InventoryCellUI
var _open_tween:Tween

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if open_resource != null:
		open_resource.set_value(false)
	_apply_style()
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
	if title_label != null:
		title_label.text = style.title
		title_label.add_theme_font_size_override("font_size", style.title_font_size)
	if info_label != null:
		info_label.add_theme_font_size_override("font_size", style.info_font_size)
		info_label.add_theme_color_override("font_color", style.info_color)
	if hint_label != null:
		hint_label.add_theme_font_size_override("font_size", style.hint_font_size)
		hint_label.add_theme_color_override("font_color", style.hint_color)
	for _box_node:Control in [quick_row, grid_container]:
		if _box_node != null:
			_box_node.add_theme_constant_override("separation", style.cell_gap)
			_box_node.add_theme_constant_override("h_separation", style.cell_gap)
			_box_node.add_theme_constant_override("v_separation", style.cell_gap)

func _new_cell(area:InventoryCellUI.Area, index:int)->InventoryCellUI:
	var _cell:InventoryCellUI = InventoryCellUI.new()
	_cell.name = ("Quick%d" if area == InventoryCellUI.Area.QUICK else "Cell%d") % index
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
		if _hovered != null:
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
			_show_grid_cell(grid_cells[_i], grid.get_cell(_i))
	if _hovered != null && is_instance_valid(_hovered):
		_update_info(_hovered)

func _show_grid_cell(cell:InventoryCellUI, entry:Variant)->void:
	if entry == null:
		cell.show_item(null, "", style.count_color, "")
		return
	var _entry:Dictionary = entry
	if _entry.has("weapon"):
		var _item:ItemResource = _entry.weapon
		cell.show_item(_item.icon, "", style.count_color, _level_text(_item))
		return
	var _def:InventoryItemDef = grid.database.def(_entry.id) if grid.database != null else null
	var _n:int = int(_entry.get("n", 0))
	var _color:Color = style.count_color
	var _text:String = style.format_amount(_n)
	if _def != null && !_def.is_infinite():
		if _n > _def.stack_size:
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
	if held != null && held_half && grid != null:
		info_label.text = "Holding %d  -  %s" % [grid.half_of(held.index), info_label.text]

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
		var _cells:int = grid.cells_of(_def.id).size()
		var _text:String = "%s  %d" % [_def.display_name, _def.amount()]
		if !_def.is_infinite():
			_text += "  (%d/cell)" % _def.stack_size
		if _cells > 1:
			_text += "  %d cells" % _cells
		return _text
	return "Weapon slot %d" % (cell.index + 1) if cell.area == InventoryCellUI.Area.QUICK else ""

# --- rules -------------------------------------------------------------------

func weapon_of(cell:InventoryCellUI)->ItemResource:
	if cell.area == InventoryCellUI.Area.QUICK:
		return weapons.list[cell.index] if weapons != null && cell.index < weapons.list.size() else null
	return grid.weapon_at(cell.index) if grid != null else null

func def_of(cell:InventoryCellUI)->InventoryItemDef:
	if cell.area != InventoryCellUI.Area.GRID || grid == null || grid.database == null:
		return null
	var _entry:Variant = grid.get_cell(cell.index)
	if _entry == null || !(_entry as Dictionary).has("id"):
		return null
	return grid.database.def(_entry.id)

func has_content(cell:InventoryCellUI)->bool:
	if cell.area == InventoryCellUI.Area.QUICK:
		return weapon_of(cell) != null
	return grid != null && grid.get_cell(cell.index) != null

## Is this a half-stack move (a splittable stack in the grid)?
func _is_split(from:InventoryCellUI, half:bool)->bool:
	if !half || from.area != InventoryCellUI.Area.GRID:
		return false
	var _def:InventoryItemDef = def_of(from)
	return _def != null && !_def.is_infinite() && grid.amount_at(from.index) >= 2

## Currencies stay in the grid; weapons go anywhere. Half a stack goes into an
## empty cell or onto the same item.
func can_place(from:InventoryCellUI, to:InventoryCellUI, half:bool = false)->bool:
	if from == null || to == null || from == to || !has_content(from):
		return false
	if _is_split(from, half):
		return to.area == InventoryCellUI.Area.GRID && grid.can_split(from.index, to.index)
	if to.area == InventoryCellUI.Area.GRID:
		if from.area == InventoryCellUI.Area.GRID:
			return true
		# quick slot weapon onto a currency stack: no
		return grid.get_cell(to.index) == null || grid.weapon_at(to.index) != null
	# onto a quick slot: weapons only
	if weapon_of(from) == null:
		return false
	if from.area == InventoryCellUI.Area.QUICK:
		return true
	return to.index < weapons.list.size() || weapons.list.size() < weapons.max_items

func place(from:InventoryCellUI, to:InventoryCellUI, half:bool = false)->bool:
	if !can_place(from, to, half):
		to.flash_invalid()
		_play(style.invalid_sound)
		return false
	var _q:InventoryCellUI.Area = InventoryCellUI.Area.QUICK
	if _is_split(from, half):
		grid.split(from.index, to.index)
	elif from.area == _q && to.area == _q:
		weapons.move(from.index, mini(to.index, weapons.list.size() - 1))
	elif from.area == InventoryCellUI.Area.GRID && to.area == InventoryCellUI.Area.GRID:
		grid.move(from.index, to.index)
	elif from.area == _q:
		# quick slot -> grid: into the cell, or swap with the weapon there
		var _there:ItemResource = grid.weapon_at(to.index)
		if _there != null:
			grid.replace_weapon(to.index, weapons.list[from.index])
			weapons.replace_at(from.index, _there)
		else:
			var _item:ItemResource = weapons.remove_at(from.index)
			grid.put_weapon(_item, to.index)
	else:
		# grid -> quick slot: swap with what's there, or into the next free slot
		var _item:ItemResource = grid.weapon_at(from.index)
		if to.index < weapons.list.size():
			var _old:ItemResource = weapons.replace_at(to.index, _item)
			grid.replace_weapon(from.index, _old)
		else:
			grid.take_weapon(from.index)
			weapons.append(_item)
	_play(style.place_sound)
	to.pop()
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

## Right click: weapon between quick slots and grid in one go.
func quick_move(cell:InventoryCellUI)->void:
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
