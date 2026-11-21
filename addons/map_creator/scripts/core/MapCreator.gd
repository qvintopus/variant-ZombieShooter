## In-game room editor. Added to a room by MapCreatorHook when Admin tools are on. It
## edits a clone of the room's RoomLayoutResource and shows every edit on the live
## layers right away. Clean (C) reruns the bake's tile passes, colliders, hole scenes and
## the AStar grid. Save writes the layout and bakes the room scene through the shared baker.
## Edit mode freezes the room (editing_flag pauses it like the inventory does), takes the
## mouse and switches to a free camera. Play mode is the normal game, for testing.
class_name MapCreator
extends Node

signal mode_changed(editing:bool)
signal tool_changed
signal item_changed
signal layout_changed
signal dirty_changed
signal history_changed
## 0..1 while cleaning, -1 when done.
signal clean_progress(fraction:float)
signal message(text:String)
## The entity shown in the inspector changed (null = none).
signal inspected_changed(entity:LayoutEntity)
## Right click: the radial menu opens at a screen position with these slices.
signal radial_requested(screen_position:Vector2, slices:Array)

enum Tool { PAINT, ERASE, SELECT, MOVE }
enum Brush { ONE, THREE, RECT }

@export var catalog:MapCatalog
@export var baker:LayoutBaker
@export var settings:MapCreatorSettings
@export var preset:MapCreatorPreset
## Pauses the room while editing (in the room's PauseProcessingComponent extra_pause).
@export var editing_flag:BoolResource
@export var camera:Camera2D
@export var overlay:Node2D

var room:Node2D
var floor_layer:TileMapLayer
var holes_layer:TileMapLayer
var walls_layer:TileMapLayer
## Edited copy of the room layout; null for a hand-made room (view only).
var layout:RoomLayoutResource
var key:String
var editing:bool
var tool:Tool = Tool.PAINT
var brush:Brush = Brush.ONE
var item:MapCatalogItem
var category:MapCatalogCategory
var dirty:bool
var busy:bool
var hover_cell:Vector2i
var hover_valid:bool
## Live entity nodes of the edited layout.
var entities:LiveEntities
## Entity open in the inspector.
var inspected:LayoutEntity
## Entities edited together with `inspected` (same item, from a selection).
var inspected_group:Array[LayoutEntity] = []
var selection:MapSelection
## While moving/duplicating: {entries, payload, copy, origin}.
var moving:Dictionary = {}
## Ctrl+drag box selection start (null when not boxing).
var box_from:Variant = null

var _undo:Array[RoomLayoutResource] = []
var _redo:Array[RoomLayoutResource] = []
var _stroke_before:RoomLayoutResource
var _stroking:bool
var _rect_from:Vector2i
var _clean_queued:bool

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	selection = MapSelection.new(self)
	if room == null:
		room = get_parent() as Node2D
	floor_layer = room.get_node("Background/FloorLayer")
	holes_layer = room.get_node("Background/ObstacleLayer")
	walls_layer = room.get_node("WallLayer_Ysorted")
	key = room_key(room)
	if baker != null && !key.is_empty() && ResourceLoader.exists(baker.layout_path(key)):
		var _source:RoomLayoutResource = ResourceLoader.load(baker.layout_path(key), "", ResourceLoader.CACHE_MODE_REPLACE)
		layout = _source.clone()
		entities = LiveEntities.new(self)
		entities.claim(layout)
	if settings != null:
		settings.visit(key)
	if catalog != null && !catalog.categories.is_empty():
		select_category(catalog.categories[0])

func _exit_tree()->void:
	set_editing(false)

## Room key from its RoomController room_id (room_N02 -> N02), else the scene name.
static func room_key(node:Node)->String:
	var _controller:Node = node.get_node_or_null("RoomController")
	var _id:String = String(_controller.get(&"room_id")) if _controller != null else node.scene_file_path.get_file().get_basename()
	return _id.trim_prefix("room_")

func can_edit()->bool:
	return layout != null

# --- mode / tool / item ---------------------------------------------------------------

func set_editing(value:bool)->void:
	if editing == value:
		return
	editing = value
	if editing_flag != null:
		editing_flag.value = value
	if camera != null:
		camera.call(&"activate" if value else &"deactivate")
	if overlay != null:
		overlay.visible = value
	mode_changed.emit(value)

func toggle_editing()->void:
	set_editing(!editing)

func set_tool(value:Tool)->void:
	tool = value
	tool_changed.emit()

func set_brush(value:Brush)->void:
	brush = value
	tool_changed.emit()

func select_category(value:MapCatalogCategory)->void:
	category = value
	if value != null && !value.items.is_empty() && (item == null || !value.items.has(item)):
		select_item(value.items[0])
	item_changed.emit()

func select_item(value:MapCatalogItem)->void:
	item = value
	if tool != Tool.PAINT && tool != Tool.ERASE:
		set_tool(Tool.PAINT)
	item_changed.emit()

## Steps through the current category's items (and their variants).
func cycle_item(step:int)->void:
	if category == null || category.items.is_empty():
		return
	var _list:Array[MapCatalogItem] = []
	for _entry:MapCatalogItem in category.items:
		_list.append(_entry)
		_list.append_array(_entry.variants)
	var _at:int = maxi(_list.find(item), 0)
	select_item(_list[posmod(_at + step, _list.size())])

func cell_at(global_position:Vector2)->Vector2i:
	return floor_layer.local_to_map(floor_layer.to_local(global_position))

func cell_center(cell:Vector2i)->Vector2:
	return floor_layer.to_global(floor_layer.map_to_local(cell))

## Cells the brush covers around `cell` (RECT uses the stroke's start).
func brush_cells(cell:Vector2i)->Array[Vector2i]:
	var _cells:Array[Vector2i] = []
	match brush:
		Brush.ONE:
			_cells.append(cell)
		Brush.THREE:
			for _y:int in range(-1, 2):
				for _x:int in range(-1, 2):
					_cells.append(cell + Vector2i(_x, _y))
		Brush.RECT:
			var _from:Vector2i = _rect_from if _stroking else cell
			var _min:Vector2i = _from.min(cell)
			var _max:Vector2i = _from.max(cell)
			for _y:int in range(_min.y, _max.y + 1):
				for _x:int in range(_min.x, _max.x + 1):
					_cells.append(Vector2i(_x, _y))
	return _cells

# --- input ------------------------------------------------------------------------------

func _unhandled_input(event:InputEvent)->void:
	if event is InputEventKey && event.pressed && !event.echo:
		if _handle_key(event):
			get_viewport().set_input_as_handled()
		return
	if !editing || busy:
		return
	if event is InputEventMouseMotion:
		_update_hover()
		if _stroking && brush != Brush.RECT:
			_apply_brush(hover_cell)
		return
	if !(event is InputEventMouseButton):
		return
	_update_hover()
	if event.button_index == MOUSE_BUTTON_RIGHT && event.pressed:
		if !moving.is_empty():
			cancel_move()
		elif can_edit():
			radial_requested.emit(event.position, radial_slices(hover_cell))
		get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if event.pressed:
		_left_pressed(event.ctrl_pressed)
	else:
		_left_released()

func _left_pressed(ctrl:bool)->void:
	if !moving.is_empty():
		confirm_move(hover_cell)
		return
	if ctrl:
		box_from = hover_cell
		return
	if tool == Tool.MOVE && can_edit():
		var _type:StringName = selection.type_at(hover_cell)
		if !selection.has_cell(hover_cell) && !_type.is_empty():
			selection.set_entries([{"cell": hover_cell, "type": _type}])
		if !selection.is_empty():
			begin_move(selection.entries(), false)
			moving.drag = true
		return
	if !selection.is_empty():
		# a plain click lets go of the selection first
		selection.clear()
		inspect(null)
		return
	if tool == Tool.PAINT || tool == Tool.ERASE:
		begin_stroke(hover_cell)
	elif tool == Tool.SELECT && can_edit():
		inspect(layout.entity_at(hover_cell))

func _left_released()->void:
	if box_from != null:
		_finish_box(box_from, hover_cell)
		box_from = null
	elif !moving.is_empty() && moving.get("drag", false):
		if hover_cell != moving.origin:
			confirm_move(hover_cell)
		else:
			# a click without dragging: keep following the cursor until the next click
			moving.drag = false
	elif _stroking:
		if brush == Brush.RECT:
			_apply_brush(hover_cell)
		end_stroke()

## Ctrl+click toggles the top thing on a cell; Ctrl+drag adds every cell of the box.
func _finish_box(from:Vector2i, to:Vector2i)->void:
	if !can_edit():
		return
	if from == to:
		selection.toggle(from, selection.type_at(from))
	else:
		var _min:Vector2i = from.min(to)
		var _max:Vector2i = from.max(to)
		for _y:int in range(_min.y, _max.y + 1):
			for _x:int in range(_min.x, _max.x + 1):
				var _cell:Vector2i = Vector2i(_x, _y)
				var _type:StringName = selection.type_at(_cell)
				if !_type.is_empty():
					selection.add(_cell, _type)
	_inspect_selection()

## One entity type selected: the inspector edits them together.
func _inspect_selection()->void:
	var _types:Array[StringName] = selection.types()
	if _types.size() == 1 && _is_entity_type(_types[0]):
		var _group:Array[LayoutEntity] = []
		for _entry:Dictionary in selection.entries():
			var _entity:LayoutEntity = layout.entity_at(_entry.cell)
			if _entity != null:
				_group.append(_entity)
		inspect(_group[0] if !_group.is_empty() else null, _group)

func _is_entity_type(type:StringName)->bool:
	var _item:MapCatalogItem = catalog.item(type)
	return _item != null && _item.kind == MapCatalogItem.Kind.ENTITY

func _handle_key(event:InputEventKey)->bool:
	if preset == null:
		return false
	if event.keycode == preset.key_toggle_edit:
		toggle_editing()
		return true
	if !editing:
		return false
	if event.keycode == KEY_ESCAPE:
		if !moving.is_empty():
			cancel_move()
		else:
			selection.clear()
			inspect(null)
		return true
	if event.keycode == KEY_DELETE && !selection.is_empty():
		remove_entries(selection.entries())
		return true
	if event.ctrl_pressed && event.keycode == KEY_D && !selection.is_empty():
		begin_move(selection.entries(), true)
		return true
	if event.ctrl_pressed:
		if event.keycode == preset.key_undo && event.shift_pressed:
			redo()
		elif event.keycode == preset.key_undo:
			undo()
		elif event.keycode == preset.key_redo:
			redo()
		elif event.keycode == preset.key_save:
			save()
		else:
			return false
		return true
	var _key:Key = event.keycode
	if _key == preset.key_clean:
		clean()
	elif _key == preset.key_paint:
		set_tool(Tool.PAINT)
	elif _key == preset.key_erase:
		set_tool(Tool.ERASE)
	elif _key == preset.key_select:
		set_tool(Tool.SELECT)
	elif _key == preset.key_move:
		set_tool(Tool.MOVE)
	elif _key == preset.key_prev_item:
		cycle_item(-1)
	elif _key == preset.key_next_item:
		cycle_item(1)
	else:
		var _index:int = _key - KEY_1
		if _index < 0 || _index >= 9 || catalog == null || _index >= catalog.categories.size():
			return false
		select_category(catalog.categories[_index])
	return true

func _update_hover()->void:
	if overlay == null:
		return
	hover_cell = cell_at(overlay.get_global_mouse_position())
	hover_valid = true

# --- strokes ----------------------------------------------------------------------------

func begin_stroke(cell:Vector2i)->void:
	if !can_edit():
		message.emit("No layout for this room: it's a hand-made scene.")
		return
	_stroke_before = layout.clone()
	_stroking = true
	_rect_from = cell
	if brush != Brush.RECT:
		_apply_brush(cell)

func end_stroke()->void:
	if !_stroking:
		return
	_stroking = false
	_push_undo(_stroke_before)
	_stroke_before = null
	if settings == null || settings.auto_clean:
		clean(false)

func _apply_brush(cell:Vector2i)->void:
	for _cell:Vector2i in brush_cells(cell):
		if tool == Tool.ERASE:
			erase_at(_cell, item)
		else:
			paint_at(_cell, item)

## Paints `with` at a cell into the layout and onto the live layers (raw until Clean).
func paint_at(cell:Vector2i, with:MapCatalogItem)->void:
	if with == null || !can_edit():
		return
	match with.kind:
		MapCatalogItem.Kind.FLOOR:
			var _v:Vector3i = Vector3i(with.floor_source, with.floor_atlas.x, with.floor_atlas.y)
			if layout.floor.get(cell, Vector3i(-1, -1, -1)) == _v:
				return
			layout.floor[cell] = _v
			layout.hole_overrides.erase(cell)
			floor_layer.set_cell(cell, _v.x, with.floor_atlas)
			holes_layer.erase_cell(cell)
		MapCatalogItem.Kind.WALL:
			if layout.wall_overrides.get(cell, false) || walls_layer.get_cell_source_id(cell) != -1:
				return
			layout.wall_overrides[cell] = true
			_set_marker(walls_layer, cell)
		MapCatalogItem.Kind.HOLE:
			if !layout.floor.has(cell) && holes_layer.get_cell_source_id(cell) != -1:
				return
			layout.floor.erase(cell)
			layout.hole_overrides[cell] = true
			floor_layer.erase_cell(cell)
			_set_marker(holes_layer, cell)
			_drop_entity_at(cell)
		MapCatalogItem.Kind.ENTITY:
			if !layout.floor.has(cell):
				message.emit("%s needs floor under it" % with.display_name)
				return
			var _old:LayoutEntity = layout.entity_at(cell)
			if _old != null && _old.item_id == with.id:
				return
			if _old != null:
				layout.entities.erase(_old)
			layout.entities.append(LayoutEntity.make(with.id, cell, new_props(with)))
			entities.sync(layout)
	_mark_dirty()

## Props a newly placed entity starts with: the item defaults, plus a unique tag and
## this room as the target for doors and portals (edit them in the inspector).
func new_props(with:MapCatalogItem)->Dictionary:
	var _props:Dictionary = with.defaults.duplicate(true)
	if with.bake == MapCatalogItem.Bake.DOOR || with.bake == MapCatalogItem.Bake.PORTAL:
		var _n:int = layout.entities_of(with.id).size() + 1
		_props.merge({"tag": "%s_%s%d" % [key.to_lower(), with.id, _n], "connect_tag": "unset", "room": "room_" + key}, false)
		if with.bake == MapCatalogItem.Bake.PORTAL:
			_props.merge({"waits_for": "room_" + key}, false)
	return _props

## Removes what `with` would paint at a cell (any floor look for FLOOR).
func erase_at(cell:Vector2i, with:MapCatalogItem)->void:
	if with == null || !can_edit():
		return
	match with.kind:
		MapCatalogItem.Kind.FLOOR:
			if !layout.floor.has(cell):
				return
			layout.floor.erase(cell)
			floor_layer.erase_cell(cell)
			_drop_entity_at(cell)
		MapCatalogItem.Kind.WALL:
			if walls_layer.get_cell_source_id(cell) == -1 && !layout.wall_overrides.get(cell, false):
				return
			layout.wall_overrides[cell] = false
			walls_layer.erase_cell(cell)
		MapCatalogItem.Kind.HOLE:
			if holes_layer.get_cell_source_id(cell) == -1 && !layout.hole_overrides.has(cell):
				return
			layout.hole_overrides[cell] = false
			holes_layer.erase_cell(cell)
			# a removed hole is walkable again
			var _floor:MapCatalogItem = _default_floor()
			layout.floor[cell] = Vector3i(_floor.floor_source, _floor.floor_atlas.x, _floor.floor_atlas.y)
			floor_layer.set_cell(cell, _floor.floor_source, _floor.floor_atlas)
		MapCatalogItem.Kind.ENTITY:
			var _old:LayoutEntity = layout.entity_at(cell)
			if _old == null || _old.item_id != with.id:
				return
			layout.entities.erase(_old)
			entities.sync(layout)
			if inspected == _old:
				inspect(null)
	_mark_dirty()

## Entities can't stand on a removed floor cell.
func _drop_entity_at(cell:Vector2i)->void:
	var _old:LayoutEntity = layout.entity_at(cell)
	if _old != null:
		layout.entities.erase(_old)
		entities.sync(layout)
		if inspected == _old:
			inspect(null)

# --- entity edits (one undo step each) --------------------------------------------------

func inspect(entity:LayoutEntity, group:Array[LayoutEntity] = [])->void:
	inspected = entity
	inspected_group = group
	inspected_changed.emit(entity)

## Runs `change` on the layout as one undoable edit, then syncs the live room.
func edit(change:Callable, reclean:bool = false)->void:
	if !can_edit() || busy:
		return
	var _before:RoomLayoutResource = layout.clone()
	change.call()
	_push_undo(_before)
	entities.sync(layout)
	_mark_dirty()
	if reclean:
		clean(false)
	selection.prune()

## Sets a prop on the entity (and on the rest of an inspected group of the same item).
func set_entity_prop(entity:LayoutEntity, prop:StringName, value:Variant)->void:
	var _targets:Array[LayoutEntity] = [entity]
	if entity == inspected:
		for _other:LayoutEntity in inspected_group:
			if _other != entity && _other.item_id == entity.item_id:
				_targets.append(_other)
	edit(func ()->void:
		for _target:LayoutEntity in _targets:
			if value == null:
				_target.props.erase(prop)
			else:
				_target.props[prop] = value)

## Sets a room-level layout field (look, side_room, sections...).
func set_layout_field(field:StringName, value:Variant)->void:
	edit(func ()->void: layout.set(field, value))

func _set_marker(layer:TileMapLayer, cell:Vector2i)->void:
	var _autotiler:TileVisualAutotiler = LayoutBaker.autotiler_of(layer)
	var _src:int = floor_layer.get_cell_source_id(cell)
	if _src == -1 || !layer.tile_set.has_source(_src):
		_src = layer.tile_set.get_source_id(0)
	layer.set_cell(cell, _src, _autotiler.marker_atlas if _autotiler != null else Vector2i(0, 2))

## Floor look a removed hole gets back: the room look's plain floor.
func _default_floor()->MapCatalogItem:
	var _look:MapCatalogItem = catalog.item(StringName("floor_" + layout.look))
	return _look if _look != null else catalog.first_of_kind(MapCatalogItem.Kind.FLOOR)

func _mark_dirty()->void:
	layout_changed.emit()
	if !dirty:
		dirty = true
		dirty_changed.emit()

# --- clean / undo / save ----------------------------------------------------------------

## Reruns the bake's tile passes on the live room from the layout, then colliders, hole
## scenes and the AStar grid. With progress, one step per frame (the bar shows it).
func clean(progress:bool = true)->void:
	if busy:
		_clean_queued = true
		return
	if !can_edit():
		message.emit("No layout for this room: it's a hand-made scene.")
		return
	busy = true
	var _step:Callable = func (fraction:float)->void:
		clean_progress.emit(fraction)
	_step.call(0.0)
	if progress:
		await get_tree().process_frame
	LayoutBaker.paint_floor(floor_layer, layout)
	_step.call(0.15)
	if progress:
		await get_tree().process_frame
	LayoutBaker.generate_tiles(floor_layer, holes_layer, walls_layer, layout, _step)
	_step.call(0.7)
	if progress:
		await get_tree().process_frame
	for _layer:TileMapLayer in [holes_layer, walls_layer]:
		var _body:Node = _layer.get_node_or_null("StaticBody2D")
		if _body != null:
			_body.cleanup()
			_body.setup_colliders()
	_step.call(0.85)
	if progress:
		await get_tree().process_frame
	for _child:Node in holes_layer.get_children():
		if _child is TileSpawner:
			_child.respawn()
	_rebuild_navigation()
	_step.call(1.0)
	if progress:
		await get_tree().process_frame
	clean_progress.emit(-1.0)
	busy = false
	if _clean_queued:
		_clean_queued = false
		clean(progress)

func _rebuild_navigation()->void:
	for _child:Node in floor_layer.get_children():
		if _child is TileNavigationSetter:
			_child.astargrid_resource.value = null
			_child.initialize_astargrid()

func _push_undo(snapshot:RoomLayoutResource)->void:
	_undo.append(snapshot)
	var _limit:int = preset.undo_limit if preset != null else 100
	while _undo.size() > _limit:
		_undo.pop_front()
	_redo.clear()
	history_changed.emit()

func can_undo()->bool:
	return !_undo.is_empty()

func can_redo()->bool:
	return !_redo.is_empty()

func undo()->void:
	if _undo.is_empty() || busy:
		return
	_redo.append(layout)
	_restore(_undo.pop_back())

func redo()->void:
	if _redo.is_empty() || busy:
		return
	_undo.append(layout)
	_restore(_redo.pop_back())

func _restore(snapshot:RoomLayoutResource)->void:
	layout = snapshot
	history_changed.emit()
	entities.sync(layout)
	cancel_move()
	if inspected != null:
		inspect(null)
	selection.clear()
	_mark_dirty()
	clean(false)

## Writes the layout and bakes the room scene (and its balance.json entry).
func save()->bool:
	if !can_edit():
		message.emit("No layout for this room: it's a hand-made scene.")
		return false
	var _saved:RoomLayoutResource = layout.clone()
	if baker.save_layout(_saved) != OK:
		message.emit("Can't write %s" % baker.layout_path(key))
		return false
	baker.problems = 0
	var _ctx:Dictionary = baker.bake(_saved)
	if baker.has_method(&"write_balance"):
		baker.call(&"write_balance")
	if _ctx.is_empty():
		message.emit("Bake failed: %s" % baker.scene_path(key))
		return false
	# the next visit loads the new scene, not the cached one
	ResourceLoader.load(baker.scene_path(key), "", ResourceLoader.CACHE_MODE_REPLACE)
	dirty = false
	dirty_changed.emit()
	message.emit("Saved room_%s%s" % [key, "" if baker.problems == 0 else " (%d problems, see the log)" % baker.problems])
	return true

# --- selection operations ---------------------------------------------------------------

## What an entry carries when moved/copied.
func _payload(entry:Dictionary)->Dictionary:
	var _cell:Vector2i = entry.cell
	var _type:StringName = entry.type
	if _type == MapSelection.WALL || _type == MapSelection.HOLE:
		return {"type": _type, "cell": _cell}
	var _item:MapCatalogItem = catalog.item(_type)
	if _item != null && _item.kind == MapCatalogItem.Kind.FLOOR:
		return {"type": _type, "cell": _cell, "floor": layout.floor.get(_cell, Vector3i(_item.floor_source, _item.floor_atlas.x, _item.floor_atlas.y))}
	var _entity:LayoutEntity = layout.entity_at(_cell)
	return {"type": _type, "cell": _cell, "entity": _entity.copy() if _entity != null else null}

## Takes a thing off the layout (no clean, no sync).
func _take(cell:Vector2i, type:StringName)->void:
	if type == MapSelection.WALL:
		layout.wall_overrides[cell] = false
	elif type == MapSelection.HOLE:
		layout.hole_overrides[cell] = false
		var _floor:MapCatalogItem = _default_floor()
		layout.floor[cell] = Vector3i(_floor.floor_source, _floor.floor_atlas.x, _floor.floor_atlas.y)
	elif _is_entity_type(type):
		var _entity:LayoutEntity = layout.entity_at(cell)
		if _entity != null && _entity.item_id == type:
			layout.entities.erase(_entity)
	else:
		layout.floor.erase(cell)
		var _entity:LayoutEntity = layout.entity_at(cell)
		if _entity != null:
			layout.entities.erase(_entity)

## Puts a catalog item on the layout (no clean, no sync). Entities need floor.
func _put(cell:Vector2i, with:MapCatalogItem, props:Variant = null, floor_value:Variant = null)->void:
	match with.kind:
		MapCatalogItem.Kind.FLOOR:
			layout.floor[cell] = floor_value if floor_value != null else Vector3i(with.floor_source, with.floor_atlas.x, with.floor_atlas.y)
			layout.hole_overrides.erase(cell)
		MapCatalogItem.Kind.WALL:
			layout.wall_overrides[cell] = true
		MapCatalogItem.Kind.HOLE:
			layout.floor.erase(cell)
			layout.hole_overrides[cell] = true
			var _gone:LayoutEntity = layout.entity_at(cell)
			if _gone != null:
				layout.entities.erase(_gone)
		MapCatalogItem.Kind.ENTITY:
			if !layout.floor.has(cell):
				return
			var _old:LayoutEntity = layout.entity_at(cell)
			if _old != null:
				layout.entities.erase(_old)
			layout.entities.append(LayoutEntity.make(with.id, cell, props if props != null else new_props(with)))

func _type_item(type:StringName)->MapCatalogItem:
	return catalog.item(type)

func remove_entries(entries:Array)->void:
	edit(func ()->void:
		for _entry:Dictionary in entries:
			_take(_entry.cell, _entry.type), true)
	selection.clear()
	inspect(null)

## Changes every entry to `with`. A floor keeps its cells under a new entity; entity props
## carry over where the new item has the same keys.
func replace_entries(entries:Array, with:MapCatalogItem)->void:
	edit(func ()->void:
		for _entry:Dictionary in entries:
			var _old:LayoutEntity = layout.entity_at(_entry.cell)
			var _props:Variant = null
			if _old != null && _old.item_id == _entry.type && with.kind == MapCatalogItem.Kind.ENTITY:
				_props = new_props(with)
				for _key:Variant in _old.props:
					if with.property(_key) != null:
						_props[_key] = _old.props[_key]
			var _target_item:MapCatalogItem = _type_item(_entry.type)
			var _from_floor:bool = _target_item != null && _target_item.kind == MapCatalogItem.Kind.FLOOR
			# a new look keeps the cell's cracks
			var _floor_value:Variant = null
			if _from_floor && with.kind == MapCatalogItem.Kind.FLOOR && layout.floor.has(_entry.cell) && with.floor_atlas == Vector2i(0, 3):
				var _old_floor:Vector3i = layout.floor[_entry.cell]
				_floor_value = Vector3i(with.floor_source, _old_floor.y, _old_floor.z)
			# a floor stays under a new entity or wall, and a new look just repaints it
			if !_from_floor:
				_take(_entry.cell, _entry.type)
			_put(_entry.cell, with, _props, _floor_value), true)
	selection.clear()

func select_type(type:StringName)->void:
	var _entries:Array = []
	for _cell:Vector2i in selection.cells_of(type):
		_entries.append({"cell": _cell, "type": type})
	for _entry:Dictionary in selection.entries():
		_entries.append(_entry)
	selection.set_entries(_entries)
	_inspect_selection()

func remove_type(type:StringName)->void:
	var _entries:Array = []
	for _cell:Vector2i in selection.cells_of(type):
		_entries.append({"cell": _cell, "type": type})
	remove_entries(_entries)

func add_at(cell:Vector2i, with:MapCatalogItem)->void:
	if with.kind == MapCatalogItem.Kind.ENTITY && !layout.floor.has(cell):
		message.emit("%s needs floor under it" % with.display_name)
		return
	edit(func ()->void: _put(cell, with), with.kind != MapCatalogItem.Kind.ENTITY)

## Starts moving (or copying) entries: they follow the cursor until a click drops them.
func begin_move(entries:Array, copy:bool)->void:
	if entries.is_empty() || !can_edit():
		return
	var _payload:Array = []
	for _entry:Dictionary in entries:
		_payload.append(_payload(_entry))
	moving = {"entries": entries, "payload": _payload, "copy": copy, "origin": hover_cell, "drag": false}
	message.emit("%s %d: click to drop, right click / Esc to cancel" % ["Copy" if copy else "Move", entries.size()])

func cancel_move()->void:
	moving = {}

func confirm_move(cell:Vector2i)->void:
	if moving.is_empty():
		return
	var _delta:Vector2i = cell - moving.origin
	var _payload:Array = moving.payload
	var _copy:bool = moving.copy
	moving = {}
	if _delta == Vector2i.ZERO && !_copy:
		return
	var _moved:Array = []
	edit(func ()->void:
		if !_copy:
			for _p:Dictionary in _payload:
				_take(_p.cell, _p.type)
		# floors first so entities land on floor
		_payload.sort_custom(func (a:Dictionary, b:Dictionary)->bool: return a.has("floor") && !b.has("floor"))
		for _p:Dictionary in _payload:
			var _to:Vector2i = _p.cell + _delta
			if _p.has("floor"):
				_put(_to, _type_item(_p.type), null, _p.floor)
			elif _p.has("entity"):
				if _p.entity != null:
					_put(_to, _type_item(_p.type), _p.entity.props.duplicate(true))
			else:
				_put(_to, _type_item(_p.type))
			_moved.append({"cell": _to, "type": _p.type}), true)
	selection.set_entries(_moved)
	selection.prune()

# --- radial menu ------------------------------------------------------------------------

func _type_name(type:StringName)->String:
	var _item:MapCatalogItem = catalog.item(type)
	return _item.display_name if _item != null else String(type)

func _type_color(type:StringName)->Color:
	var _item:MapCatalogItem = catalog.item(type)
	return _item.color if _item != null else Color.WHITE

func _slice(label:String, color:Color, icon:Texture2D = null, children:Array = [], action:Callable = Callable())->Dictionary:
	return {"label": label, "color": color, "icon": icon, "children": children, "action": action}

## Ring 1: the selection's types (and all of it) or the hovered thing, then every kind of
## thing in the room plus the brush item, then More (categories -> items). Ring 2 holds
## the operations; "Change to" opens a third ring of items.
func radial_slices(cell:Vector2i)->Array:
	var _ring:Array = []
	if !selection.is_empty():
		var _types:Array[StringName] = selection.types()
		for _type:StringName in _types:
			var _entries:Array = selection.entries(_type)
			_ring.append(_target_slice("%d x %s" % [_entries.size(), _type_name(_type)], _type, _entries))
		if _types.size() > 1:
			_ring.append(_target_slice("All %d selected" % selection.size(), &"", selection.entries()))
	else:
		var _type:StringName = selection.type_at(cell)
		if !_type.is_empty():
			_ring.append(_target_slice("This %s" % _type_name(_type), _type, [{"cell": cell, "type": _type}]))
	var _room_types:Array[StringName] = selection.room_types()
	for _type:StringName in _room_types:
		_ring.append(_catalog_slice(_type, cell))
	if item != null && !_room_types.has(item.id):
		_ring.append(_catalog_slice(item.id, cell))
	var _categories:Array = []
	for _category:MapCatalogCategory in catalog.categories:
		var _items:Array = []
		for _entry:MapCatalogItem in category_items(_category):
			_items.append(_catalog_slice(_entry.id, cell))
		_categories.append(_slice(_category.display_name, _category.color, _category.icon, _items))
	_ring.append(_slice("More...", Color(0.7, 0.7, 0.7), null, _categories))
	return _ring

## A category's items and their variants.
func category_items(of:MapCatalogCategory)->Array[MapCatalogItem]:
	var _list:Array[MapCatalogItem] = []
	for _entry:MapCatalogItem in of.items:
		_list.append(_entry)
		_list.append_array(_entry.variants)
	return _list

func _ops_for(type:StringName, context:int)->Array[MapCatalogOperation]:
	var _list:Array[MapCatalogOperation] = []
	var _ops:Array[MapCatalogOperation] = catalog.operations_of(type) if !type.is_empty() else catalog.categories[0].operations
	var _item:MapCatalogItem = catalog.item(type)
	var _kind:int = _item.kind if _item != null else -1
	for _op:MapCatalogOperation in _ops:
		if (_op.context & context) != 0 && (_kind == -1 || _op.kinds.is_empty() || _op.kinds.has(_kind)):
			if type.is_empty() && (_op.id == &"pick" || _op.id == &"modify"):
				continue
			_list.append(_op)
	return _list

func _target_slice(label:String, type:StringName, entries:Array)->Dictionary:
	var _children:Array = []
	for _op:MapCatalogOperation in _ops_for(type, MapCatalogOperation.Context.TARGET):
		match _op.id:
			&"pick":
				_children.append(_slice(_op.label, _op.color, _op.icon, [], select_item.bind(catalog.item(type))))
			&"modify":
				_children.append(_slice(_op.label, _op.color, _op.icon, [], func ()->void:
					selection.set_entries(entries)
					_inspect_selection()))
			&"replace":
				_children.append(_slice(_op.label, _op.color, _op.icon, _replace_slices(type, entries)))
			&"duplicate":
				_children.append(_slice(_op.label, _op.color, _op.icon, [], func ()->void:
					hover_cell = entries[0].cell
					begin_move(entries, true)))
			&"move":
				_children.append(_slice(_op.label, _op.color, _op.icon, [], func ()->void:
					hover_cell = entries[0].cell
					begin_move(entries, false)))
			&"remove":
				_children.append(_slice(_op.label, _op.color, _op.icon, [], remove_entries.bind(entries)))
	return _slice(label, _type_color(type) if !type.is_empty() else preset.selection_color, catalog.item(type).icon if catalog.item(type) != null else null, _children)

## "Change to": the brush item first, then the target's category (and variants).
func _replace_slices(type:StringName, entries:Array)->Array:
	var _list:Array = []
	var _seen:Dictionary = {}
	var _candidates:Array[MapCatalogItem] = []
	if item != null:
		_candidates.append(item)
	var _category:MapCatalogCategory = catalog.category_of(type) if !type.is_empty() else null
	if _category != null:
		_candidates.append_array(category_items(_category))
	for _entry:MapCatalogItem in _candidates:
		if _seen.has(_entry.id) || _entry.id == type:
			continue
		_seen[_entry.id] = true
		_list.append(_slice(_entry.display_name, _entry.color, _entry.icon, [], replace_entries.bind(entries, _entry)))
	return _list

func _catalog_slice(type:StringName, cell:Vector2i)->Dictionary:
	var _children:Array = []
	var _item:MapCatalogItem = catalog.item(type)
	for _op:MapCatalogOperation in _ops_for(type, MapCatalogOperation.Context.CATALOG):
		match _op.id:
			&"add":
				if _item != null:
					_children.append(_slice("%s here" % _op.label, _op.color, _op.icon, [], add_at.bind(cell, _item)))
			&"select_all":
				_children.append(_slice(_op.label, _op.color, _op.icon, [], select_type.bind(type)))
			&"remove_all":
				_children.append(_slice(_op.label, _op.color, _op.icon, [], remove_type.bind(type)))
			&"pick":
				if _item != null:
					_children.append(_slice(_op.label, _op.color, _op.icon, [], select_item.bind(_item)))
	return _slice(_type_name(type), _type_color(type), _item.icon if _item != null else null, _children)
