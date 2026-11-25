## Free camera of the map creator's edit mode: WASD / arrows pan, middle mouse drags,
## the wheel zooms at the cursor (not over a panel). Takes over from the room camera and hands back.
class_name EditCamera
extends Camera2D

@export var preset:MapCreatorPreset

var _previous:Camera2D
var _dragging:bool

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = false

func activate()->void:
	_previous = get_viewport().get_camera_2d()
	if _previous != null && _previous != self:
		global_position = _previous.get_screen_center_position()
		zoom = _previous.zoom
	enabled = true
	make_current()

func deactivate()->void:
	enabled = false
	if is_instance_valid(_previous) && _previous != self:
		_previous.make_current()
	_previous = null

func _process(delta:float)->void:
	if !enabled:
		return
	var _dir:Vector2 = Vector2.ZERO
	if _held(KEY_A) || _held(KEY_LEFT):
		_dir.x -= 1
	if _held(KEY_D) || _held(KEY_RIGHT):
		_dir.x += 1
	if _held(KEY_W) || _held(KEY_UP):
		_dir.y -= 1
	if _held(KEY_S) || _held(KEY_DOWN):
		_dir.y += 1
	var _speed:float = preset.pan_speed if preset != null else 260.0
	global_position += _dir.normalized() * _speed * delta / zoom.x

func _held(key:Key)->bool:
	return Input.is_physical_key_pressed(key) && !Input.is_key_pressed(KEY_CTRL)

func _unhandled_input(event:InputEvent)->void:
	if !enabled:
		return
	if event is InputEventMouseButton:
		# the wheel / drag over a panel (e.g. past the end of its scroll) isn't for the map
		if event.pressed && over_ui():
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_MIDDLE]:
				get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed && (event.button_index == MOUSE_BUTTON_WHEEL_UP || event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var _step:float = preset.zoom_step if preset != null else 1.15
			zoom_at(get_global_mouse_position(), _step if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / _step)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion && _dragging:
		global_position -= event.relative / zoom.x
		get_viewport().set_input_as_handled()

## The wheel over `spin` scrolls `scroll` (its panel) instead of changing the value,
## unless the number is being typed in.
static func wheel_scrolls(spin:SpinBox, scroll:ScrollContainer, step:int = 24)->void:
	spin.gui_input.connect(func (event:InputEvent)->void:
		if !(event is InputEventMouseButton) || spin.get_line_edit().has_focus():
			return
		var _button:MouseButton = (event as InputEventMouseButton).button_index
		if _button != MOUSE_BUTTON_WHEEL_UP && _button != MOUSE_BUTTON_WHEEL_DOWN:
			return
		spin.accept_event()
		if event.pressed:
			scroll.scroll_vertical += -step if _button == MOUSE_BUTTON_WHEEL_UP else step)

## The pointer is over a visible control of the map creator's UI (a panel, the
## topbar...), not over the map.
func over_ui()->bool:
	var _hovered:Control = get_viewport().gui_get_hovered_control()
	if _hovered == null || !_hovered.is_visible_in_tree():
		return false
	var _root:Node = get_parent().get_node_or_null(^"UI/Root") if get_parent() != null else null
	return _root == null || _root.is_ancestor_of(_hovered)

## Zooms by `factor`, keeping the world point under `anchor` in place.
func zoom_at(anchor:Vector2, factor:float)->void:
	var _min:float = preset.zoom_min if preset != null else 0.25
	var _max:float = preset.zoom_max if preset != null else 4.0
	var _new:float = clampf(zoom.x * factor, _min, _max)
	var _ratio:float = zoom.x / _new
	global_position = anchor + (global_position - anchor) * _ratio
	zoom = Vector2(_new, _new)
