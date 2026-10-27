## Walking version of JumpMove. It keeps the same signals and calls, so BigJellyChase,
## BigJellyJumpDamage and BossAnimator work unchanged: the body glides along the ground
## with a step bob instead of arcing through the air.
class_name WalkMove
extends JumpMove

## Steps taken during one walk to the target
@export var steps:int = 3

## Height of each step bob, in pixels
@export var step_height:float = 2.0

func move_target_position(value:Vector2, time:float)->void:
	if is_jumping:
		return
	is_jumping = true

	previous_position = character_body.global_position
	jump_started.emit()

	if move_tween != null:
		move_tween.kill()

	move_tween = create_tween()
	move_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)

	move_tween.tween_method(_move_body.bind(character_body.global_position, value), 0.0, 1.0, time)
	move_tween.finished.connect(_jump_finished.bind(value))

func _move_body(t:float, from:Vector2, to:Vector2)->void:
	var _new_pos:Vector2 = from.lerp(to, t)
	var _distance:Vector2 = _new_pos - previous_position
	previous_position = _new_pos
	character_body.velocity = _distance * physics_ticks
	character_body.move_and_slide()

	# whole number of steps, so the bob is back at zero when the walk ends
	sprite.offset.y = -abs(sin(t * steps * PI)) * step_height

	movement_interpolation.emit(t)
