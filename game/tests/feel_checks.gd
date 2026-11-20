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
		await _check_damage_numbers()
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
