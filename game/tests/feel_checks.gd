## Headless checks for game-feel features (docs/notes.md): dash immunity, ...
##   Godot --headless --path . res://game/tests/feel_checks.tscn
extends Node

const TD:String = "res://addons/top_down/"
const ROOM:String = "res://game/scenes/room_A02.tscn"

var failures:int = 0
var checks:int = 0
var player:Node2D
var spawn_pos:Vector2

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
		spawn_pos = player.global_position
	if player != null:
		await _check_dash_immunity()
		await _check_damage_numbers()
		await _check_pickups()
		await _check_hole_fall()
		await _check_clear_fx()
		await _check_abilities()
	await _check_menus()
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

func _count_texts()->int:
	var _n:int = 0
	for _node:Node in get_tree().get_nodes_in_group(&"__none__"):
		_n += 1
	for _node:Node in _all(get_tree().root):
		if _node is FloatingText && _node.is_inside_tree():
			_n += 1
	return _n

func _all(node:Node)->Array[Node]:
	var _list:Array[Node] = [node]
	for _child:Node in node.get_children():
		_list.append_array(_all(_child))
	return _list

func _check_damage_numbers()->void:
	var _settings:DamageNumbersSettings = load(TD + "resources/global_resources/damage_numbers_settings.tres")
	var _display:DamageDisplay = player.get_node("DamageDisplay")
	check(_display.is_player && _display.settings == _settings, "player DamageDisplay is player + has settings")
	check(_settings.color_presets.size() == 2, "two color presets")
	var _damage:DamageResource = player.get_node("ResourceNode").get_resource("damage")
	await _frames(70)
	var _before:int = _count_texts()
	_settings.set_show_player(false)
	_damage.receive_points(3.0)
	await _frames(2)
	check(_count_texts() == _before, "player numbers hidden when off")
	_settings.set_show_player(true)
	_damage.receive_points(3.0)
	await _frames(2)
	check(_count_texts() == _before + 1, "player number shown when on")
	var _text:FloatingText = null
	for _node:Node in _all(get_tree().root):
		if _node is FloatingText && _node.is_inside_tree():
			_text = _node
	check(_text != null && _text.label.get_theme_color(&"font_color") == _settings.colors().player, "player number uses player color")
	var _size:int = _settings.font_size()
	_settings.cycle_size()
	check(_settings.font_size() != _size, "size cycles")
	_settings.reset_resource()
	var _saved:DamageNumbersSettings = _settings.prepare_save()
	_saved.show_enemy = false
	_saved.preset_index = 1
	_settings.prepare_load(_saved)
	check(!_settings.show_enemy && _settings.colors().preset_name == "Vivid", "settings load")
	_settings.reset_resource()

func _check_menus()->void:
	for _path:String in [TD + "scenes/ui/screens/pause.tscn", TD + "scenes/ui/screens/title.tscn"]:
		var _scene:Node = (load(_path) as PackedScene).instantiate()
		add_child(_scene)
		await _frames(2)
		var _menu:Node = _scene.get_node_or_null("MarginContainer/Control/Body/GameplayMenu")
		check(_menu != null, "gameplay menu in " + _path)
		var _label:Label = _scene.get_node_or_null("MarginContainer/Control/Body/GameplayMenu/EnemyNumbers/Label")
		check(_label != null && _label.text.begins_with("Enemy numbers"), "gameplay labels refreshed in " + _path)
		_scene.queue_free()
		await _frames(2)

func _spawn_coin(at:Vector2)->Node2D:
	var _res:InstanceResource = load(TD + "resources/InstanceResources/pickups/coin_instance_resource.tres")
	var _coin:Node2D = _res.instance(func (n:Node2D)->void: n.global_position = at)
	await _frames(25)
	return _coin

func _check_pickups()->void:
	var _coins:ScoreResource = load(TD + "resources/global_resources/score_resource.tres")
	var _events:PickupEvents = load(TD + "resources/global_resources/pickup_events.tres")
	var _juice:PickupJuice = player.get_node_or_null("PickupJuice")
	check(_juice != null && _events.sound_owner == _juice, "player PickupJuice owns pickup sounds")
	var _got:Array = []
	_events.collected.connect(func (id:StringName, _a:int, _p:Vector2, _s:SoundResource, _l:String)->void: _got.append(id))
	var _mover:Node = player.get_node_or_null("PlayerInput")
	if _mover != null:
		_mover.process_mode = Node.PROCESS_MODE_DISABLED
	# far coin: pulled in and collected
	var _start:int = _coins.value
	player.global_position = player.global_position
	var _coin:Node2D = await _spawn_coin(player.global_position + Vector2(30, 0))
	var _magnet:PickupMagnet = _coin.get_node("PickupMagnet")
	check(_magnet.active, "coin magnet active after spawn")
	for i:int in 120:
		await get_tree().physics_frame
		if !_coin.is_inside_tree():
			break
	check(!_coin.is_inside_tree() && _coins.value == _start + 1, "magnet pulls coin in and collects it")
	check(_got.has(&"coin"), "pickup event fired")
	check(_juice.streak >= 1, "pickup streak counted")
	# out of range: stays
	var _far:Node2D = await _spawn_coin(player.global_position + Vector2(120, 0))
	await _frames(30)
	check(_far.is_inside_tree() && !_far.get_node("PickupMagnet").attracted, "coin out of range stays")
	# kiting: player moves away faster than max speed -> coin loses it
	var _kite_res:InstanceResource = load(TD + "resources/InstanceResources/pickups/coin_instance_resource.tres")
	var _kite:Node2D = _kite_res.instance(func (n:Node2D)->void: n.global_position = player.global_position + Vector2(-28, 0))
	var _km:PickupMagnet = null
	var _ever:bool = false
	for i:int in 60:
		await get_tree().physics_frame
		if _km == null && _kite.is_inside_tree():
			_km = _kite.get_node("PickupMagnet")
		if _km != null && _km.attracted:
			_ever = true
			break
	for i:int in 120:
		player.global_position += Vector2(1.5, 0)
		await get_tree().physics_frame
	check(_ever, "kite coin attracted")
	check(_kite.is_inside_tree() && !_km.attracted, "running away from a coin loses it")
	check(_km.velocity.length() <= _km.preset.max_speed + 0.01, "coin speed capped")
	_far.get_node("PoolNode").pool_return()
	_kite.get_node("PoolNode").pool_return()
	player.global_position = spawn_pos
	if _mover != null:
		_mover.process_mode = Node.PROCESS_MODE_INHERIT

func _check_hole_fall()->void:
	var _fall:HoleFall = player.get_node_or_null("HoleFall")
	var _recovery:HoleRecovery = player.get_node_or_null("HoleRecovery")
	check(_fall != null && _recovery != null && _recovery.hole_fall == _fall, "player has HoleFall wired to HoleRecovery")
	if _fall == null:
		return
	var _res:ResourceNode = player.get_node("ResourceNode")
	var _health:HealthResource = _res.get_resource("health")
	var _damage:DamageResource = _res.get_resource("damage")
	player.global_position = spawn_pos
	for i:int in 120:
		if !_fall.falling:
			break
		await get_tree().physics_frame
	await _frames(40)
	_damage.set_can_receive_damage(true)
	_health.hp = _health.max_hp
	var _safe:Vector2 = player.global_position
	player.global_position += Vector2(10, 0)
	_recovery._on_hole_touched()
	check(_fall.falling && _damage.fall_immune, "falling and immune")
	check(!player.get_node("PlayerInput").is_physics_processing(), "input locked while falling")
	_recovery._on_hole_touched()
	await _frames(12)
	var _body:Node2D = player.get_node("Body")
	check(_body.scale.x < 0.9, "body shrinks while sinking")
	check(_health.hp == _health.max_hp, "no damage before landing")
	for i:int in 90:
		await get_tree().physics_frame
		if !_fall.falling:
			break
	check(!_fall.falling && !_damage.fall_immune, "fall ends")
	check(player.global_position.distance_to(_safe) < 16.0, "lands near the safe spot (%s vs %s)" % [player.global_position, _safe])
	check(_health.hp == _health.max_hp - _recovery.hole_damage, "hole damage once on landing")
	check(player.get_node("PlayerInput").is_physics_processing(), "input back after landing")
	await _frames(10)
	check(is_equal_approx(_body.scale.x, 1.0), "body scale restored")
	_health.hp = _health.max_hp

func _count_type(script_class:Variant)->int:
	var _n:int = 0
	for _node:Node in _all(get_tree().root):
		if is_instance_of(_node, script_class) && _node.is_inside_tree():
			_n += 1
	return _n

func _check_clear_fx()->void:
	var _fx:ClearFx = null
	for _node:Node in _all(get_tree().root):
		if _node is ClearFx:
			_fx = _node
	check(_fx != null, "room has ClearFx")
	var _aggregator:ArenaSectionAggregator = get_tree().get_first_node_in_group(&"arena_aggregator")
	check(_aggregator != null, "room has aggregator")
	if _fx == null || _aggregator == null:
		return
	var _before:int = _count_type(ClearBurst)
	_aggregator.wave_finished.emit(1, 2, false, 3)
	await _frames(3)
	check(_count_type(ClearBurst) > _before, "wave clear bursts")
	_aggregator.wave_finished.emit(3, 0, true, 2)
	await _frames(20)
	check(_fx.blessing != null && _fx.blessing.rect.visible, "room clear shows blessing")
	await _frames(150)
	check(!_fx.blessing.rect.visible, "blessing fades out")
	check(_count_type(ClearBurst) == _before, "bursts return to pool")

func _make_slot(path:String)->AbilitySlot:
	var _slot:AbilitySlot = AbilitySlot.new()
	_slot.ability = load(TD + "resources/abilities/" + path)
	_slot.reset_state()
	return _slot

func _check_abilities()->void:
	player.global_position = spawn_pos
	await _frames(5)
	var _manager:AbilityManager = player.get_node_or_null("AbilityManager")
	check(_manager != null && _manager.slot(0) != null, "player has AbilityManager with slot 0")
	if _manager == null:
		return
	var _bomb:AbilitySlot = _manager.slot(0)
	check(_bomb.ability.id == &"bomb" && _bomb.can_use(), "bomb ready")
	# place an enemy next to the player and bomb it
	var _res:InstanceResource = load(TD + "resources/InstanceResources/actors/slime_small_instance_resource.tres")
	var _enemy:Node2D = _res.instance(func (n:Node2D)->void: n.global_position = spawn_pos + Vector2(14, 0))
	await _frames(10)
	var _enemy_health:HealthResource = _enemy.get_node("ResourceNode").get_resource("health")
	var _enemy_start:float = _enemy_health.hp
	var _input:InputResource = player.get_node("ResourceNode").get_resource("input")
	_input.set_aim_direction(Vector2.RIGHT)
	_input.ability_pressed.emit(0)
	check(!_bomb.can_use() && _bomb.cooldown_left > 5.0, "bomb used, on cooldown")
	await _frames(2)
	var _found:Bomb = null
	for _node:Node in _all(get_tree().root):
		if _node is Bomb && _node.is_inside_tree():
			_found = _node
	check(_found != null, "bomb dropped")
	await _frames(100)
	check(_enemy_health.is_dead || _enemy_health.hp < _enemy_start, "bomb damages a nearby enemy (%s -> %s)" % [_enemy_start, _enemy_health.hp])
	check(_found == null || !_found.is_inside_tree(), "bomb gone after exploding")
	check(_bomb.cooldown_left > 0.0, "bomb's own hit doesn't refill it")
	if is_instance_valid(_enemy) && _enemy.is_inside_tree() && !_enemy_health.is_dead:
		_enemy_health.insta_kill() if _enemy_health.has_method(&"insta_kill") else null
	# store keeps cooldown between rooms
	var _store:AbilityChargesResource = _manager.store
	check(_store != null && float(_store.cooldowns.get("bomb", 0.0)) > 0.0, "cooldown kept in store")

	# refill rules on detached slots
	var _kill:AbilitySlot = _make_slot("example_consumable_kill.tres")
	check(_kill.is_consumable() && _kill.charges == 3, "consumable starts with charges")
	_kill.ability.effect = null
	_kill.charges = 1
	_kill.on_trigger(AbilityResource.Refill.KILL)
	check(_kill.charges == 2, "kill adds a charge")
	_kill.on_trigger(AbilityResource.Refill.DAMAGE_DEALT)
	check(_kill.charges == 2, "damage doesn't refill a kill ability")
	_kill.ability = load(TD + "resources/abilities/example_consumable_kill.tres")
	var _dmg:AbilitySlot = _make_slot("example_cooldown_damage.tres")
	_dmg.cooldown_left = 5.0
	_dmg.on_trigger(AbilityResource.Refill.DAMAGE_DEALT)
	check(is_equal_approx(_dmg.cooldown_left, 4.5), "damage takes time off cooldown")
	_dmg.on_trigger(AbilityResource.Refill.DAMAGE_DEALT)
	check(is_equal_approx(_dmg.cooldown_left, 4.5), "refill_cooldown blocks rapid refills")
	var _full:AbilitySlot = _make_slot("example_cooldown_health_full.tres")
	_full.cooldown_left = 9.0
	_full.on_trigger(AbilityResource.Refill.HEALTH_AT_FULL)
	check(_full.cooldown_left == 0.0, "health at full resets cooldown")
	var _coin:AbilitySlot = _make_slot("example_cooldown_coin.tres")
	_coin.cooldown_left = 3.0
	_coin.on_trigger(AbilityResource.Refill.COIN_PICKUP)
	check(is_equal_approx(_coin.cooldown_left, 2.0), "coin takes a second off")
	for _s:AbilitySlot in [_kill, _dmg, _full, _coin]:
		_s.free()
	# run data roundtrip
	var _data:PlayerRunData = PlayerRunData.new()
	_data.abilities = {"x": 2}
	var _back:PlayerRunData = PlayerRunData.from_dict(_data.to_dict())
	check(_back != null && _back.abilities.get("x") == 2, "run data keeps ability charges")
	var _bad:Dictionary = _data.to_dict()
	_bad["abilities"] = {"x": "lots"}
	check(PlayerRunData.from_dict(_bad) == null, "bad ability data rejected")
	# HUD
	var _hud:AbilitySlotUI = null
	for _node:Node in _all(get_tree().root):
		if _node is AbilitySlotUI:
			_hud = _node
	check(_hud != null && _hud.visible && _hud.pie.value > 0.0, "HUD shows bomb cooldown")
