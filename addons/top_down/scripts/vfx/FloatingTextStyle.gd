## Motion preset for FloatingText (damage numbers, pickup texts).
class_name FloatingTextStyle
extends Resource

@export_group("Motion")
## Seconds the text lives
@export_range(0.1, 3.0, 0.01) var duration:float = 0.8
## Pixels it rises to the top of its arc
@export var rise:float = 10.0
## Pixels it drops back from the top by the end
@export var fall:float = 6.0
## Max sideways drift in pixels (random sign)
@export var drift:float = 6.0
## Random spread of start position in pixels
@export var spread:float = 3.0
## Last part of the life (0..1) spent fading out
@export_range(0.0, 1.0, 0.01) var fade_portion:float = 0.3

@export_group("Pop")
@export var start_scale:float = 0.4
@export var pop_scale:float = 1.35
@export_range(0.01, 1.0, 0.01) var pop_time:float = 0.12

@export_group("Critical")
## Extra scale on critical hits
@export var critical_scale:float = 1.3
@export var critical_shake:float = 2.0
@export_range(0.0, 1.0, 0.01) var critical_shake_time:float = 0.15

@export_group("Label")
@export var outline_size:int = 2
@export var outline_color:Color = Color.BLACK
