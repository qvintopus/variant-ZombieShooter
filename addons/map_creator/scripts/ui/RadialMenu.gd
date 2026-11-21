## Circular context menu (right click in Edit mode). Ring 1 is a full circle; hovering
## a slice opens its children as an arc on the next ring outward, centered on that slice
## (any depth). Clicking a slice with an action runs it and closes the menu. The hovered
## slice's label shows in the middle. Right click, Esc or a click outside closes it.
## Slices: {label, color, icon, children: Array, action: Callable} (MapCreator.radial_slices).
class_name RadialMenu
extends Control

@export var creator:MapCreator
@export var inner_radius:float = 14.0
@export var ring_width:float = 18.0
@export var ring_gap:float = 2.0
## Arc length one slice of an outer ring takes.
@export var outer_slice_length:float = 17.0
## Least arc length of a ring-1 slice: many slices push ring 1 outward.
@export var min_slice_length:float = 11.0
@export var icon_size:float = 7.0
@export var fill_color:Color = Color(0.1, 0.1, 0.13, 0.92)
@export var hover_color:Color = Color(0.35, 0.65, 1.0, 0.9)
@export var line_color:Color = Color(1, 1, 1, 0.15)

var center:Vector2
## Inner radius of ring 1 for the current slices.
var _base:float
var _rings:Array = []
## Hovered slice index per ring (-1 none); ring n+1 shows children of _path[n].
var _path:Array[int] = []
var _label:String

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	if !creator.is_node_ready():
		await creator.ready
	creator.radial_requested.connect(open)
	creator.mode_changed.connect(func (_v:bool)->void: close())

## Opens at a viewport (window) position with ring-1 slices.
## `at` is in viewport coords (the mouse event's position).
func open(at:Vector2, slices:Array)->void:
	if slices.is_empty():
		return
	_base = maxf(inner_radius, slices.size() * min_slice_length / TAU - ring_width * 0.5)
	var _reach:float = minf(_base + 3.0 * (ring_width + ring_gap), minf(size.x, size.y) * 0.5)
	center = (get_global_transform_with_canvas().affine_inverse() * at).clamp(Vector2(_reach, _reach), size - Vector2(_reach, _reach))
	_rings = [slices]
	_path = [-1]
	_label = ""
	visible = true
	queue_redraw()

func close()->void:
	visible = false
	_rings = []
	_path = []

func is_open()->bool:
	return visible

func _radius(ring:int)->Vector2:
	var _r0:float = _base + ring * (ring_width + ring_gap)
	return Vector2(_r0, _r0 + ring_width)

## [start angle, angle per slice] of a ring. Ring 0: full circle from the top.
func _span(ring:int)->Vector2:
	var _count:int = _rings[ring].size()
	if ring == 0:
		return Vector2(-PI * 0.5 - PI / _count, TAU / _count)
	var _r:Vector2 = _radius(ring)
	var _step:float = minf(outer_slice_length / ((_r.x + _r.y) * 0.5), TAU / _count)
	var _parent:Vector2 = _span(ring - 1)
	var _mid:float = _parent.x + (_path[ring - 1] + 0.5) * _parent.y
	return Vector2(_mid - _step * _count * 0.5, _step)

func _hit(local:Vector2)->Vector2i:
	var _offset:Vector2 = local - center
	var _dist:float = _offset.length()
	for _ring:int in _rings.size():
		var _r:Vector2 = _radius(_ring)
		if _dist < _r.x - ring_gap * 0.5 || _dist > _r.y + ring_gap * 0.5:
			continue
		var _span:Vector2 = _span(_ring)
		var _angle:float = fposmod(_offset.angle() - _span.x, TAU)
		var _index:int = int(floor(_angle / _span.y))
		if _index >= 0 && _index < _rings[_ring].size():
			return Vector2i(_ring, _index)
	return Vector2i(-1, -1)

func _gui_input(event:InputEvent)->void:
	if !visible:
		return
	accept_event()
	if event is InputEventMouseMotion:
		_hover(_hit(event.position))
	elif event is InputEventMouseButton && event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			close()
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var _at:Vector2i = _hit(event.position)
		if _at.x < 0:
			close()
			return
		_hover(_at)
		var _slice:Dictionary = _rings[_at.x][_at.y]
		var _action:Callable = _slice.get("action", Callable())
		if _action.is_valid():
			close()
			_action.call()

func _unhandled_key_input(event:InputEvent)->void:
	if visible && event is InputEventKey && event.pressed && event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

## Hovering a slice opens its children on the next ring (and closes deeper ones).
func _hover(at:Vector2i)->void:
	if at.x < 0:
		return
	_path.resize(at.x + 1)
	_rings.resize(at.x + 1)
	_path[at.x] = at.y
	var _slice:Dictionary = _rings[at.x][at.y]
	_label = _slice.label
	var _children:Array = _slice.get("children", [])
	if !_children.is_empty():
		_rings.append(_children)
		_path.append(-1)
	queue_redraw()

## Test hook: hovers slice `index` on `ring` (as the mouse would).
func hover_slice(ring:int, index:int)->void:
	_hover(Vector2i(ring, index))

## Test hook: slice dicts of a ring.
func ring_slices(ring:int)->Array:
	return _rings[ring] if ring < _rings.size() else []

## Test hook: clicks slice `index` on `ring`.
func press_slice(ring:int, index:int)->void:
	_hover(Vector2i(ring, index))
	var _action:Callable = _rings[ring][index].get("action", Callable())
	if _action.is_valid():
		close()
		_action.call()

func _draw()->void:
	if _rings.is_empty():
		return
	draw_circle(center, minf(inner_radius, _base) - ring_gap, fill_color)
	for _ring:int in _rings.size():
		var _r:Vector2 = _radius(_ring)
		var _span:Vector2 = _span(_ring)
		var _slices:Array = _rings[_ring]
		for _i:int in _slices.size():
			var _a0:float = _span.x + _i * _span.y
			var _a1:float = _a0 + _span.y
			var _hovered:bool = _ring < _path.size() && _path[_ring] == _i
			_draw_slice(_r, _a0, _a1, hover_color if _hovered else fill_color, _slices[_i])
	var _font:Font = get_theme_default_font()
	var _size:int = maxi(get_theme_default_font_size() - 1, 5)
	if !_label.is_empty():
		var _text_size:Vector2 = _font.get_string_size(_label, HORIZONTAL_ALIGNMENT_CENTER, -1, _size)
		var _at:Vector2 = center + Vector2(-_text_size.x * 0.5, _size * 0.35)
		draw_rect(Rect2(_at + Vector2(-2, -_size), _text_size + Vector2(4, 3)), fill_color)
		draw_string(_font, _at, _label, HORIZONTAL_ALIGNMENT_LEFT, -1, _size, Color.WHITE)

func _draw_slice(r:Vector2, a0:float, a1:float, color:Color, slice:Dictionary)->void:
	var _points:PackedVector2Array = []
	var _steps:int = maxi(int((a1 - a0) / 0.15), 2)
	for _s:int in _steps + 1:
		_points.append(center + Vector2.from_angle(lerpf(a0, a1, float(_s) / _steps)) * r.y)
	for _s:int in range(_steps, -1, -1):
		_points.append(center + Vector2.from_angle(lerpf(a0, a1, float(_s) / _steps)) * r.x)
	draw_colored_polygon(_points, color)
	_points.append(_points[0])
	draw_polyline(_points, line_color)
	var _mid:Vector2 = center + Vector2.from_angle((a0 + a1) * 0.5) * (r.x + r.y) * 0.5
	var _icon:Texture2D = slice.get("icon")
	var _half:float = icon_size * 0.5
	if _icon != null:
		draw_texture_rect(_icon, Rect2(_mid - Vector2(_half, _half), Vector2(icon_size, icon_size)), false)
	else:
		var _color:Color = slice.get("color", Color.WHITE)
		draw_rect(Rect2(_mid - Vector2(_half, _half), Vector2(icon_size, icon_size)), _color)
		# no icon: the label's first letter on the swatch
		var _letter:String = String(slice.get("label", "")).left(1)
		var _font:Font = get_theme_default_font()
		var _size:int = int(icon_size)
		var _w:float = _font.get_string_size(_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, _size).x
		draw_string(_font, _mid + Vector2(-_w * 0.5, _size * 0.35), _letter, HORIZONTAL_ALIGNMENT_LEFT, -1, _size, Color(0, 0, 0, 0.8) if _color.get_luminance() > 0.5 else Color(1, 1, 1, 0.9))
	if !slice.get("children", []).is_empty():
		# a dot marks slices that open another ring
		draw_circle(center + Vector2.from_angle((a0 + a1) * 0.5) * (r.y - 2.0), 1.0, Color(1, 1, 1, 0.6))
