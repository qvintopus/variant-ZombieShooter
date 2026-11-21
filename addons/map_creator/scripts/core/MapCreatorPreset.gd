## Feel and look of the map creator: hotkeys, camera, overlay colors, UI size.
class_name MapCreatorPreset
extends Resource

@export_group("Keys")
@export var key_toggle_edit:Key = KEY_F2
@export var key_clean:Key = KEY_C
@export var key_paint:Key = KEY_B
@export var key_erase:Key = KEY_X
@export var key_select:Key = KEY_V
@export var key_move:Key = KEY_G
@export var key_prev_item:Key = KEY_Q
@export var key_next_item:Key = KEY_E
@export var key_browse:Key = KEY_TAB
## Ctrl + these
@export var key_undo:Key = KEY_Z
@export var key_redo:Key = KEY_Y
@export var key_save:Key = KEY_S

@export_group("Camera")
@export var pan_speed:float = 260.0
@export var zoom_step:float = 1.15
@export var zoom_min:float = 0.25
@export var zoom_max:float = 4.0

@export_group("Overlay")
@export var hover_color:Color = Color(1, 1, 1, 0.5)
@export var brush_color:Color = Color(0.4, 0.9, 1.0, 0.35)
@export var erase_color:Color = Color(1.0, 0.3, 0.3, 0.4)
@export var selection_color:Color = Color(1.0, 0.85, 0.2, 0.55)
@export var grid_color:Color = Color(1, 1, 1, 0.14)
@export var entity_marker_alpha:float = 0.8

@export_group("UI")
@export var font_size:int = 6
@export var bar_color:Color = Color(0.08, 0.08, 0.1, 0.88)
@export var active_color:Color = Color(0.35, 0.65, 1.0)
@export var swatch_size:Vector2 = Vector2(8, 8)
@export var undo_limit:int = 100
