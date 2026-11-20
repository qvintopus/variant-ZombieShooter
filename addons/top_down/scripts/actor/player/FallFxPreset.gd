## Tuning for HoleFall (sink into a hole, pop back up on safe ground).
class_name FallFxPreset
extends Resource

@export_group("Sink")
@export_range(0.05, 2.0, 0.01) var sink_time:float = 0.35
## Body scale at the bottom of the sink
@export var sink_scale:float = 0.25
## Pixels the body slides into the hole (along the fall direction)
@export var slide_into_hole:float = 4.0
## Pixels the body drops down (sinking)
@export var sink_drop:float = 5.0
@export var sink_color:Color = Color(0.3, 0.3, 0.4, 1.0)
## Slight spin while falling, in turns
@export var sink_spin:float = 0.25

@export_group("Hidden")
## Seconds invisible before popping back up
@export_range(0.0, 2.0, 0.01) var hidden_time:float = 0.15

@export_group("Pop up")
@export_range(0.05, 2.0, 0.01) var pop_time:float = 0.25
@export var pop_start_scale:float = 0.3
@export var pop_overshoot:float = 1.15
## Pixels from the safe tile center, away from the hole
@export var land_push:float = 6.0
