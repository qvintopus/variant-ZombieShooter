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
## Campaign graph.
@export var key_graph:Key = KEY_M
@export var key_fill:Key = KEY_F
## Eyedropper (also Alt+click).
@export var key_pick:Key = KEY_I
@export var key_line:Key = KEY_L
## Waves editor panel.
@export var key_waves:Key = KEY_K
## Live problems list.
@export var key_problems:Key = KEY_O
## Leave Edit mode with the player at the cursor.
@export var key_play_here:Key = KEY_P
@export var key_help:Key = KEY_F1
## Seconds between autosaves of unsaved edits (0 = off).
@export var autosave_seconds:float = 30.0
## Entering Edit on an original (built-in) room first offers to copy it.
@export var ask_copy_original:bool = true
## Seconds after an edit before the live checks run.
@export var check_delay:float = 0.3
## Biggest area a fill covers (an open area stops the fill).
@export var fill_max:int = 4000
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
## Icon of the "open this room" buttons (empty: a drawn open-in-new-tab arrow).
@export var open_room_icon:Texture2D
@export var undo_limit:int = 100

@export_group("Waves panel")
@export var waves_panel_width:float = 190.0
## Section card background (tinted by the section's own color).
@export var section_card_color:Color = Color(0.13, 0.13, 0.17, 0.95)
## Wave card background inside a section card.
@export var wave_card_color:Color = Color(0.07, 0.1, 0.13, 0.95)
@export var wave_accent_color:Color = Color(0.45, 0.6, 0.75)
@export var boss_wave_color:Color = Color(0.95, 0.35, 0.3)
## Delete buttons and destructive prompt choices.
@export var danger_color:Color = Color(1.0, 0.4, 0.35)
## Flash on the section card of the inspected entity.
@export var focus_flash_color:Color = Color(1.0, 0.95, 0.6)
