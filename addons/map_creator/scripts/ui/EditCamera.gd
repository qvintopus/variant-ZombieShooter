## Free camera of the map creator's edit mode: WASD / arrows pan, middle mouse drags,
## the wheel zooms at the cursor. Takes over from the room camera and hands back.
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

## Zooms by `factor`, keeping the world point under `anchor` in place.
func zoom_at(anchor:Vector2, factor:float)->void:
	var _min:float = preset.zoom_min if preset != null else 0.25
	var _max:float = preset.zoom_max if preset != null else 4.0
	var _new:float = clampf(zoom.x * factor, _min, _max)
	var _ratio:float = zoom.x / _new
	global_position = anchor + (global_position - anchor) * _ratio
	zoom = Vector2(_new, _new)
