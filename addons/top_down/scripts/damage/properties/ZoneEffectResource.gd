## Timed effects that zones (webs, puddles) apply to the actor standing in them.
## Kept on the actor's ResourceNode as "zone" and ticked by ZoneEffectNode.
class_name ZoneEffectResource
extends SaveableResource

## Seconds left of being stuck in place
var stuck_time:float

## Seconds left of slowed movement, and the speed factor used while slowed
var slow_time:float
var slow_factor:float = 1.0

## Seconds left of poison, and the damage taken every second while poisoned
var poison_time:float
var poison_damage:float

## Refreshes the timers, so a zone that keeps touching the actor keeps the effect running.
func apply(stuck:float, slow:float, slow_scale:float, poison:float, poison_value:float)->void:
	stuck_time = max(stuck_time, stuck)
	slow_time = max(slow_time, slow)
	slow_factor = slow_scale
	poison_time = max(poison_time, poison)
	poison_damage = poison_value

func reset_resource()->void:
	stuck_time = 0.0
	slow_time = 0.0
	poison_time = 0.0
