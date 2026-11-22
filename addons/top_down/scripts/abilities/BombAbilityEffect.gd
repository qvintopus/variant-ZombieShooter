## Drops a Bomb at the player's feet, tossed a little toward the aim.
class_name BombAbilityEffect
extends AbilityEffect

@export var bomb_instance:InstanceResource
## Pixels the bomb is tossed toward the aim direction
@export var toss_distance:float = 12.0
## Isometric squash for the toss
@export var toss_squash:Vector2 = Vector2(1.0, 0.5)

func activate(slot:AbilitySlot)->bool:
	var _body:Node2D = slot.body()
	if _body == null || bomb_instance == null:
		return false
	var _aim:Vector2 = Vector2.RIGHT
	var _resources:ResourceNode = slot.resource_node()
	var _input:InputResource = _resources.get_resource("input") if _resources != null else null
	if _input != null && _input.aim_direction.length_squared() > 0.01:
		_aim = _input.aim_direction.normalized()
	var _from:Vector2 = _body.global_position
	var _to:Vector2 = _from + _aim * toss_distance * toss_squash
	var _damage:DamageResource = _resources.get_resource("damage") if _resources != null else null
	var _report:Callable = _damage.report if _damage != null else Callable()
	bomb_instance.instance(func (n:Node2D)->void: (n as Bomb).setup(_from, _to, false, _report))
	slot.send_fx([_from, _to])
	return true

func play_remote(_slot:AbilitySlot, args:Array)->void:
	if args.size() != 2 || typeof(args[0]) != TYPE_VECTOR2 || typeof(args[1]) != TYPE_VECTOR2 || bomb_instance == null:
		return
	var _from:Vector2 = args[0]
	var _to:Vector2 = args[1]
	if !_from.is_finite() || !_to.is_finite():
		return
	bomb_instance.instance(func (n:Node2D)->void: (n as Bomb).setup(_from, _to, true))
