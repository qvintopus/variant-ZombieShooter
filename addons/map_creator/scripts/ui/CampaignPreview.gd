## Campaign graph's Preview view: every room of the campaign drawn with its floor tiles,
## placed next to the rooms it links to on the side its stairs are (layout_rooms). Wheel
## zooms, drag pans, click selects, double click opens, hover shows the room's details.
## Positions are computed each time (nothing saved).
class_name CampaignPreview
extends Control

signal room_selected(key:String)
signal room_activated(key:String)

@export var door_color:Color = Color(0.7, 0.9, 1.0)
@export var portal_color:Color = Color(1.0, 0.75, 0.35)
@export var selected_color:Color = Color(1, 1, 0.4)
@export var dim_alpha:float = 0.25
@export var label_size:int = 7
## Zoom above which labels add the room's name to its key.
@export var name_zoom:float = 0.3
## Cells between a room's stairs and the linked room's.
@export var gap_cells:int = 3
@export var background_color:Color = Color(0.08, 0.08, 0.1)
@export var min_zoom:float = 0.03
@export var max_zoom:float = 2.0

## The campaign graph (layout_of, details, tints).
var graph:CampaignGraph
var tile_set:TileSet
## Cell -> local pixel position (the room floor layer's map_to_local).
var to_px:Callable
## key -> {layout, cell_offset, offset (px), rect, center, tint, exits: [{pos, kind, to}]}
var rooms:Dictionary = {}
## [{a, b, from (world), to (world), kind}]
var links:Array[Dictionary] = []
## Keys the search leaves out (drawn faded).
var dimmed:Dictionary = {}
var selected:String

var _canvas:Node2D
var _overlay:Control
var _dragging:bool
var _fit_pending:bool

func _ready()->void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_tiles)
	add_child(_canvas)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	resized.connect(func ()->void:
		if _fit_pending:
			fit())

## Places `keys` (start first) and redraws; tints: key -> Color.
func show_rooms(keys:Array, start:String, tints:Dictionary)->void:
	var _layouts:Dictionary = {}
	for _key:String in keys:
		var _layout:RoomLayoutResource = graph.layout_of(_key) if graph != null else null
		if _layout != null:
			_layouts[_key] = _layout
	var _offsets:Dictionary = layout_rooms(_layouts, start, gap_cells)
	rooms.clear()
	for _key:String in _layouts:
		var _shape:Dictionary = shape_of(_layouts[_key], to_px)
		_shape.layout = _layouts[_key]
		_shape.cell_offset = _offsets[_key]
		_shape.offset = cell_px(Vector2(_offsets[_key])) - cell_px(Vector2.ZERO)
		_shape.tint = tints.get(_key, Color.WHITE)
		rooms[_key] = _shape
	links.clear()
	for _a:String in _layouts:
		for _b:String in neighbours(_layouts, _a):
			if _a < _b:
				links.append({
					"a": _a, "b": _b, "kind": link_kind(_layouts, _a, _b),
					"from": cell_px(Vector2(_offsets[_a]) + ends(_layouts[_a], _a, _layouts[_b], _b)),
					"to": cell_px(Vector2(_offsets[_b]) + ends(_layouts[_b], _b, _layouts[_a], _a)),
				})
	_canvas.queue_redraw()
	_overlay.queue_redraw()
	fit()

func set_dimmed(keys:Dictionary)->void:
	dimmed = keys
	_canvas.queue_redraw()
	_overlay.queue_redraw()

func set_selected(key:String)->void:
	selected = key
	_overlay.queue_redraw()

## Pixel spot of a fractional cell (the grid is linear: interpolates to_px).
func cell_px(cell:Vector2)->Vector2:
	var _o:Vector2 = to_px.call(Vector2i.ZERO)
	return _o + (to_px.call(Vector2i(1, 0)) - _o) * cell.x + (to_px.call(Vector2i(0, 1)) - _o) * cell.y

## Fractional cell under a pixel spot (inverse of cell_px).
func px_cell(px:Vector2)->Vector2:
	var _o:Vector2 = to_px.call(Vector2i.ZERO)
	var _basis:Transform2D = Transform2D(to_px.call(Vector2i(1, 0)) - _o, to_px.call(Vector2i(0, 1)) - _o, Vector2.ZERO)
	return _basis.affine_inverse() * (px - _o)

# --- placement (cell space: every room shares the floor grid) ----------------------------

## Pixel floor bounds (rect), centre and the door / portal spots of a room, for drawing.
static func shape_of(layout:RoomLayoutResource, px:Callable)->Dictionary:
	var _sum:Vector2 = Vector2.ZERO
	var _rect:Rect2 = Rect2()
	var _first:bool = true
	for _cell:Vector2i in layout.floor:
		var _p:Vector2 = px.call(_cell)
		_sum += _p
		if _first:
			_rect = Rect2(_p, Vector2.ZERO)
			_first = false
		else:
			_rect = _rect.expand(_p)
	var _exits:Array = []
	for _i:int in CampaignStore.exits_of(layout):
		var _entity:LayoutEntity = layout.entities[_i]
		_exits.append({"pos": px.call(_entity.cell), "kind": _entity.item_id, "to": _target(_entity)})
	return {"rect": _rect.grow(16.0), "center": _sum / maxf(layout.floor.size(), 1), "exits": _exits}

## Mean floor cell.
static func center_of(layout:RoomLayoutResource)->Vector2:
	var _sum:Vector2 = Vector2.ZERO
	for _cell:Vector2i in layout.floor:
		_sum += Vector2(_cell)
	return _sum / maxf(layout.floor.size(), 1)

static func _target(entity:LayoutEntity)->String:
	return String(entity.props.get("room", "")).trim_prefix("room_")

## Rooms in `layouts` that `key` links to or that link to it: door links first, by key.
static func neighbours(layouts:Dictionary, key:String)->Array[String]:
	var _doors:Array[String] = []
	var _others:Array[String] = []
	for _other:String in layouts:
		if _other == key:
			continue
		var _kind:StringName = link_kind(layouts, key, _other)
		if _kind == &"door":
			_doors.append(_other)
		elif _kind != &"":
			_others.append(_other)
	_doors.sort()
	_others.sort()
	return _doors + _others

## &"door" when a door joins a and b (either way), &"portal" for only portals, else &"".
static func link_kind(layouts:Dictionary, a:String, b:String)->StringName:
	var _kind:StringName = &""
	for _pair:Array in [[a, b], [b, a]]:
		for _entity:LayoutEntity in layouts[_pair[0]].entities:
			if _target(_entity) == _pair[1] && _entity.item_id in [&"door", &"portal"]:
				if _entity.item_id == &"door":
					return &"door"
				_kind = &"portal"
	return _kind

## Where room `a` meets room `b` (cell): the mean of a's stairs / portals leading to b
## (several stairs side by side count as one spot); else of a's exits that b's links
## arrive at; else a's floor centre.
static func ends(a:RoomLayoutResource, a_key:String, b:RoomLayoutResource, b_key:String)->Vector2:
	var _cells:Array[Vector2i] = []
	for _entity:LayoutEntity in a.entities:
		if _target(_entity) == b_key && _entity.item_id in [&"door", &"portal"]:
			_cells.append(_entity.cell)
	if _cells.is_empty():
		var _tags:Array[String] = []
		for _entity:LayoutEntity in b.entities:
			if _target(_entity) == a_key:
				_tags.append(String(_entity.props.get("connect_tag", "")))
		for _entity:LayoutEntity in a.entities:
			var _tag:String = String(_entity.props.get("tag", ""))
			if _entity.item_id in [&"door", &"portal"] && !_tag.is_empty() && _tags.has(_tag):
				_cells.append(_entity.cell)
	if _cells.is_empty():
		return center_of(a)
	var _sum:Vector2 = Vector2.ZERO
	for _cell:Vector2i in _cells:
		_sum += Vector2(_cell)
	return _sum / _cells.size()

## key -> cell offset of every room: breadth first from `start`; a linked room goes out
## from its stairs (direction centre -> stairs), its own stairs `gap` cells from that
## spot, pushed further out while its floor touches a placed room's. Unlinked rooms line
## up below.
static func layout_rooms(layouts:Dictionary, start:String, gap:int = 3)->Dictionary:
	var _offsets:Dictionary = {}
	if layouts.is_empty():
		return _offsets
	var _keys:Array = layouts.keys()
	_keys.sort()
	if !layouts.has(start):
		start = _keys[0]
	## cells taken by placed rooms, grown by one so rooms keep a gap
	var _taken:Dictionary = {}
	var _queue:Array[String] = [start]
	_offsets[start] = Vector2i.ZERO
	_take(layouts[start], Vector2i.ZERO, _taken)
	while !_queue.is_empty():
		var _a:String = _queue.pop_front()
		var _center:Vector2 = center_of(layouts[_a])
		for _b:String in neighbours(layouts, _a):
			if _offsets.has(_b):
				continue
			var _exit:Vector2 = ends(layouts[_a], _a, layouts[_b], _b)
			var _entry:Vector2 = ends(layouts[_b], _b, layouts[_a], _a)
			var _dir:Vector2 = _exit - _center
			_dir = _dir.normalized() if _dir.length() > 0.5 else Vector2.RIGHT
			var _at:Vector2 = Vector2(_offsets[_a]) + _exit + _dir * gap - _entry
			var _offset:Vector2i = Vector2i(_at.round())
			for _i:int in 300:
				if !_touches(layouts[_b], _offset, _taken):
					break
				_at += _dir * 2.0
				_offset = Vector2i(_at.round())
			_offsets[_b] = _offset
			_take(layouts[_b], _offset, _taken)
			_queue.append(_b)
	var _min:Vector2i = Vector2i.ZERO
	var _max:Vector2i = Vector2i.ZERO
	for _cell:Vector2i in _taken:
		_min = _min.min(_cell)
		_max = _max.max(_cell)
	var _x:int = _min.x
	for _key:String in _keys:
		if _offsets.has(_key):
			continue
		var _size:Vector2i = layouts[_key].size()
		_offsets[_key] = Vector2i(_x, _max.y + gap * 2)
		_take(layouts[_key], _offsets[_key], _taken)
		_x += _size.x + gap
	return _offsets

static func _take(layout:RoomLayoutResource, offset:Vector2i, taken:Dictionary)->void:
	for _cell:Vector2i in layout.floor:
		for _y:int in range(-1, 2):
			for _x:int in range(-1, 2):
				taken[_cell + offset + Vector2i(_x, _y)] = true

static func _touches(layout:RoomLayoutResource, offset:Vector2i, taken:Dictionary)->bool:
	for _cell:Vector2i in layout.floor:
		if taken.has(_cell + offset):
			return true
	return false

# --- view --------------------------------------------------------------------------------

func world_bounds()->Rect2:
	var _bounds:Rect2 = Rect2()
	var _first:bool = true
	for _key:String in rooms:
		var _r:Rect2 = Rect2(rooms[_key].rect.position + rooms[_key].offset, rooms[_key].rect.size)
		_bounds = _r if _first else _bounds.merge(_r)
		_first = false
	return _bounds

## Zooms to show every room.
func fit()->void:
	if size.x < 4.0 || size.y < 4.0:
		_fit_pending = true
		return
	_fit_pending = false
	var _bounds:Rect2 = world_bounds()
	if _bounds.size.x <= 0.0 || _bounds.size.y <= 0.0:
		return
	var _zoom:float = clampf(minf(size.x / _bounds.size.x, size.y / _bounds.size.y) * 0.92, min_zoom, max_zoom)
	_canvas.scale = Vector2.ONE * _zoom
	_canvas.position = size * 0.5 - _bounds.get_center() * _zoom
	_overlay.queue_redraw()

func center_on(key:String)->void:
	if !rooms.has(key):
		return
	var _world:Vector2 = rooms[key].offset + rooms[key].center
	_canvas.position = size * 0.5 - _world * _canvas.scale.x
	_overlay.queue_redraw()

func to_screen(world:Vector2)->Vector2:
	return _canvas.position + world * _canvas.scale.x

func to_world(screen:Vector2)->Vector2:
	return (screen - _canvas.position) / _canvas.scale.x

## Room whose floor is under a screen point ("" = none).
func room_at(screen:Vector2)->String:
	var _world:Vector2 = to_world(screen)
	var _cell:Vector2i = Vector2i(px_cell(_world).round())
	for _key:String in rooms:
		if rooms[_key].layout.floor.has(_cell - rooms[_key].cell_offset):
			return _key
	# off the floor: nearest centre among the rooms whose bounds hold the point
	var _best:String = ""
	var _best_d:float = INF
	for _key:String in rooms:
		var _room:Dictionary = rooms[_key]
		var _local:Vector2 = _world - _room.offset
		if !_room.rect.has_point(_local):
			continue
		var _d:float = _local.distance_squared_to(_room.center)
		if _d < _best_d:
			_best = _key
			_best_d = _d
	return _best

func _gui_input(event:InputEvent)->void:
	if event is InputEventMouseButton:
		var _mb:InputEventMouseButton = event
		if _mb.pressed && (_mb.button_index == MOUSE_BUTTON_WHEEL_UP || _mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var _before:Vector2 = to_world(_mb.position)
			var _zoom:float = clampf(_canvas.scale.x * (1.15 if _mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), min_zoom, max_zoom)
			_canvas.scale = Vector2.ONE * _zoom
			_canvas.position = _mb.position - _before * _zoom
			_overlay.queue_redraw()
			accept_event()
		elif _mb.button_index == MOUSE_BUTTON_LEFT || _mb.button_index == MOUSE_BUTTON_MIDDLE:
			if _mb.pressed && _mb.button_index == MOUSE_BUTTON_LEFT:
				var _key:String = room_at(_mb.position)
				if _mb.double_click && !_key.is_empty():
					room_activated.emit(_key)
				elif !_key.is_empty():
					set_selected(_key)
					room_selected.emit(_key)
			_dragging = _mb.pressed
			accept_event()
	elif event is InputEventMouseMotion && _dragging:
		_canvas.position += (event as InputEventMouseMotion).relative
		_overlay.queue_redraw()
		accept_event()

func _get_tooltip(at_position:Vector2)->String:
	var _key:String = room_at(at_position)
	return graph.details_of(_key) if graph != null && !_key.is_empty() else ""

# --- drawing -----------------------------------------------------------------------------

func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color)

func _draw_tiles()->void:
	for _key:String in rooms:
		var _room:Dictionary = rooms[_key]
		var _layout:RoomLayoutResource = _room.layout
		var _modulate:Color = Color(1, 1, 1, dim_alpha) if dimmed.has(_key) else Color.WHITE
		for _cell:Vector2i in _layout.floor:
			var _tile:Vector3i = _layout.floor[_cell]
			var _at:Vector2 = _room.offset + to_px.call(_cell)
			var _source:TileSetAtlasSource = tile_set.get_source(_tile.x) as TileSetAtlasSource if tile_set != null && tile_set.has_source(_tile.x) else null
			var _atlas:Vector2i = Vector2i(_tile.y, _tile.z)
			if _source != null && _source.texture != null && _source.has_tile(_atlas):
				var _region:Rect2i = _source.get_tile_texture_region(_atlas)
				var _origin:Vector2 = Vector2(_source.get_tile_data(_atlas, 0).texture_origin)
				_canvas.draw_texture_rect_region(_source.texture, Rect2(_at - Vector2(_region.size) * 0.5 - _origin, _region.size), _region, _modulate)
			else:
				var _half:Vector2 = Vector2(tile_set.tile_size) * 0.5 if tile_set != null else Vector2(16, 8)
				_canvas.draw_colored_polygon(PackedVector2Array([_at + Vector2(0, -_half.y), _at + Vector2(_half.x, 0), _at + Vector2(0, _half.y), _at + Vector2(-_half.x, 0)]), Color(0.5, 0.5, 0.5, _modulate.a))

func _draw_overlay()->void:
	var _font:Font = get_theme_default_font()
	for _link:Dictionary in links:
		var _faded:bool = dimmed.has(_link.a) && dimmed.has(_link.b)
		var _color:Color = door_color if _link.kind == &"door" else portal_color
		_color.a = dim_alpha if _faded else 0.9
		if _link.kind == &"door":
			_overlay.draw_line(to_screen(_link.from), to_screen(_link.to), _color, 2.0)
		else:
			_overlay.draw_dashed_line(to_screen(_link.from), to_screen(_link.to), _color, 2.0, 5.0)
	for _key:String in rooms:
		var _room:Dictionary = rooms[_key]
		var _alpha:float = dim_alpha if dimmed.has(_key) else 1.0
		for _exit:Dictionary in _room.exits:
			var _color:Color = door_color if _exit.kind == &"door" else portal_color
			_color.a = _alpha
			_overlay.draw_circle(to_screen(_room.offset + _exit.pos), 3.0, _color)
		if _key == selected:
			var _r:Rect2 = Rect2(to_screen(_room.offset + _room.rect.position), _room.rect.size * _canvas.scale.x)
			_overlay.draw_rect(_r, selected_color, false, 2.0)
		var _layout:RoomLayoutResource = _room.layout
		var _named:bool = _canvas.scale.x >= name_zoom && !_layout.display_name.is_empty() && _layout.display_name != "room_" + _key
		var _text:String = "%s %s" % [_key, _layout.display_name] if _named else _key
		var _at:Vector2 = to_screen(_room.offset + _room.center)
		var _width:float = _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
		var _tint:Color = _room.tint
		_tint.a = _alpha
		_overlay.draw_rect(Rect2(_at + Vector2(-_width * 0.5 - 2, -label_size), Vector2(_width + 4, label_size + 4)), Color(0, 0, 0, 0.6 * _alpha))
		_overlay.draw_string(_font, _at + Vector2(-_width * 0.5, 0), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, _tint)
