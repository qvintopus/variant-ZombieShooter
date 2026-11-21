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

var _undo:Array[RoomLayoutResource] = []
var _redo:Array[RoomLayoutResource] = []
var _stroke_before:RoomLayoutResource
var _stroking:bool
var _rect_from:Vector2i
var _clean_queued:bool

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	elif event is InputEventMouseButton && event.button_index == MOUSE_BUTTON_LEFT:
		_update_hover()
		if event.pressed && (tool == Tool.PAINT || tool == Tool.ERASE):
			begin_stroke(hover_cell)
			get_viewport().set_input_as_handled()
		elif event.pressed && tool == Tool.SELECT && can_edit():
			inspect(layout.entity_at(hover_cell))
			get_viewport().set_input_as_handled()
		elif !event.pressed && _stroking:
			if brush == Brush.RECT:
				_apply_brush(hover_cell)
			end_stroke()
			get_viewport().set_input_as_handled()

func _handle_key(event:InputEventKey)->bool:
	if preset == null:
		return false
	if event.keycode == preset.key_toggle_edit:
		toggle_editing()
		return true
	if !editing:
		return false
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

func inspect(entity:LayoutEntity)->void:
	inspected = entity
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

func set_entity_prop(entity:LayoutEntity, prop:StringName, value:Variant)->void:
	edit(func ()->void:
		if value == null:
			entity.props.erase(prop)
		else:
			entity.props[prop] = value)

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
	if inspected != null:
		inspect(null)
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
