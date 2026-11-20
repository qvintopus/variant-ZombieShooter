## Headless checks for game-feel features (docs/notes.md): dash immunity, ...
##   Godot --headless --path . res://game/tests/feel_checks.tscn
extends Node

const TD:String = "res://addons/top_down/"
const ROOM:String = "res://game/scenes/room_A02.tscn"

var failures:int = 0
var checks:int = 0
var player:Node2D

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	var _room:Node = (load(ROOM) as PackedScene).instantiate()
	add_child(_room)
	await _frames(10)
	player = (load(TD + "resources/ReferenceNodeResources/player_reference.tres") as ReferenceNodeResource).node
	check(player != null, "room has player")
	if player != null:
		await _check_dash_immunity()
	_finish()

func _finish()->void:
	print("feel_checks: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _frames(n:int)->void:
	for i:int in n:
		await get_tree().physics_frame

func _hit(resources:ResourceNode, amount:float)->void:
	var _data:DamageDataResource = DamageDataResource.new("damage")
	var _type:DamageTypeResource = DamageTypeResource.new()
	_type.value = amount
	_data.base_damage = [_type]
	_data.process(resources)

func _check_dash_immunity()->void:
	var _res:ResourceNode = player.get_node("ResourceNode")
	var _damage:DamageResource = _res.get_resource("damage")
	var _health:HealthResource = _res.get_resource("health")
	var _dash:BoolResource = _res.get_resource("dash")
	check(player.get_node_or_null("DashImmunity") != null, "player has DashImmunity node")
	_damage.set_can_receive_damage(true)
	_health.hp = _health.max_hp
	var _start:float = _health.hp

	_dash.set_value(true)
	check(_damage.dash_immune && _damage.is_blocked(), "dashing blocks hits")
	_hit(_res, 5.0)
	check(_health.hp == _start, "hit while dashing does no damage")
	NetEntities.apply_hit(player, 5.0, Vector2.ZERO, false)
	check(_health.hp == _start, "remote hurt while dashing does no damage")
	check(_damage.is_dot_blocked(), "dashing blocks damage over time")
	var _acid:BoolResource = _res.get_resource("acid")
	if _acid != null:
		for i:int in 40:
			_acid.set_value(true)
			await get_tree().physics_frame
		check(_health.hp == _start, "acid while dashing does no damage")

	_dash.set_value(false)
	check(!_damage.dash_immune, "immunity ends with the dash")
	_hit(_res, 5.0)
	check(_health.hp < _start, "hit after dash damages")
	_health.hp = _health.max_hp
	await _frames(40)
