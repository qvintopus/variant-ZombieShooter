## Look and feel of a healing Shrine.
class_name ShrinePreset
extends Resource

@export_group("Idle")
## Glow pulses while uses are left (cycles a second)
@export_range(0.0, 5.0, 0.01) var pulse_speed:float = 0.8
## How much brighter the shrine gets at the top of a pulse
@export_range(0.0, 1.0, 0.01) var pulse_amount:float = 0.25
@export var glow_color:Color = Color(0.6, 1.0, 0.8, 1.0)
## Modulate once spent
@export var spent_color:Color = Color(0.55, 0.55, 0.6, 1.0)

@export_group("Use")
@export var flash_color:Color = Color(2.0, 2.4, 2.0, 1.0)
@export_range(0.01, 2.0, 0.01) var flash_time:float = 0.45
@export var punch_scale:Vector2 = Vector2(1.25, 0.8)
@export_range(0.01, 2.0, 0.01) var punch_time:float = 0.3
