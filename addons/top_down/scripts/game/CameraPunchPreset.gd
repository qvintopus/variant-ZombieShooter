## Tuning for CameraPunch: a quick zoom-in with a playful tilt, then back.
class_name CameraPunchPreset
extends Resource

@export var enabled:bool = true
## Zoom multiplier at the peak (1.15 = 15% closer)
@export_range(1.0, 2.0, 0.01) var zoom_mult:float = 1.15
## Tilt at the peak in degrees; the side is random each time
@export_range(0.0, 20.0, 0.1) var tilt_deg:float = 3.0
## Seconds after the trigger before the punch starts
@export_range(0.0, 2.0, 0.01) var delay:float = 0.0

@export_group("Timing")
@export_range(0.01, 2.0, 0.01) var in_time:float = 0.12
@export_range(0.0, 3.0, 0.01) var hold_time:float = 0.25
@export_range(0.01, 3.0, 0.01) var out_time:float = 0.35
@export var in_trans:Tween.TransitionType = Tween.TRANS_BACK
@export var in_ease:Tween.EaseType = Tween.EASE_OUT
@export var out_trans:Tween.TransitionType = Tween.TRANS_SINE
@export var out_ease:Tween.EaseType = Tween.EASE_IN_OUT
