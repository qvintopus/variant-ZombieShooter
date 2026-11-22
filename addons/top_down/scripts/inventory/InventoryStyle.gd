## Look of the inventory screen (preset; swap .tres for variants).
class_name InventoryStyle
extends Resource

@export_group("Cells")
@export var cell_size:Vector2 = Vector2(18, 18)
@export var cell_gap:int = 2
@export var icon_scale:float = 1.0
@export var frame_texture:Texture2D
## Quick slot holding the weapon in hand
@export var selected_texture:Texture2D
@export var hover_modulate:Color = Color(1.35, 1.35, 1.2)
@export var empty_modulate:Color = Color(0.75, 0.75, 0.8)
## Cell picked up with the pad / keyboard
@export var held_modulate:Color = Color(0.5, 0.5, 0.55)
@export var invalid_color:Color = Color(1.0, 0.35, 0.3)
@export_range(0.01, 1.0, 0.01) var invalid_flash_time:float = 0.25

@export_group("Text")
@export var title:String = "INVENTORY"
@export var title_font_size:int = 8
@export var count_font_size:int = 6
@export var count_color:Color = Color(1, 1, 1)
## Stack at its cell limit
@export var full_stack_color:Color = Color(1.0, 0.85, 0.35)
## More than the grid has room for
@export var overflow_color:Color = Color(1.0, 0.45, 0.4)
@export var level_color:Color = Color(0.6, 0.85, 1.0)
@export var info_font_size:int = 7
@export var info_color:Color = Color(0.9, 0.9, 0.95)
@export var hint_font_size:int = 6
@export var hint_color:Color = Color(0.65, 0.65, 0.72)
## Amounts from this many on are shortened (12k)
@export var compact_from:int = 10000

@export_group("Panel")
@export var dim_color:Color = Color(0, 0, 0, 0.55)
@export var panel_color:Color = Color(0.09, 0.07, 0.12, 0.92)
@export var panel_border_color:Color = Color(0.33, 0.32, 0.43)
@export var panel_padding:int = 6
@export var section_gap:int = 4

@export_group("Motion")
@export_range(0.0, 1.0, 0.01) var open_time:float = 0.12
@export var open_from_scale:float = 0.9
@export var held_offset:Vector2 = Vector2(4, -4)
@export_range(0.0, 1.0, 0.01) var place_pop_time:float = 0.12
@export var place_pop_scale:float = 1.2

@export_group("Sound")
@export var open_sound:SoundResource
@export var close_sound:SoundResource
@export var pick_sound:SoundResource
@export var place_sound:SoundResource
@export var invalid_sound:SoundResource

func format_amount(value:int)->String:
	if compact_from > 0 && value >= compact_from:
		if value >= 1000000:
			return "%dM" % (value / 1000000)
		return "%dk" % (value / 1000)
	return str(value)
