## Tuning for PickupMagnet. Distances in flat (non-isometric) pixels.
class_name MagnetPreset
extends Resource

## Starts pulling inside this distance
@export var radius:float = 48.0
## Lets go outside this distance (hysteresis: keep > radius)
@export var release_radius:float = 64.0
## Pull acceleration, px/s^2
@export var acceleration:float = 600.0
## Speed cap, px/s. Below the player's speed (60) so running away loses them.
@export var max_speed:float = 54.0
## Velocity damping when not pulled (1/s). Low = items keep gliding (kiting).
@export var drag:float = 4.0
## Collected inside this distance
@export var collect_radius:float = 6.0
## Slight swirl: sideways share of the pull (0 = straight in)
@export_range(0.0, 1.0, 0.01) var swirl:float = 0.15
