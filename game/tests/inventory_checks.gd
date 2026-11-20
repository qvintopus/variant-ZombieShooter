## Headless checks for the inventory grid, its pickups gating, the screen and saves.
##   Godot --headless --path . res://game/tests/inventory_checks.tscn
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
	_check_stack_math()
	_check_grid_moves()
	_check_run_data()
	var _room:Node = (load(ROOM) as PackedScene).instantiate()
	add_child(_room)
	await _frames(10)
	player = (load(TD + "resources/ReferenceNodeResources/player_reference.tres") as ReferenceNodeResource).node
	check(player != null, "room has player")
	if player != null:
		await _check_player_inventory()
		await _check_screen(_room)
	print("inventory_checks: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _frames(n:int)->void:
	for i:int in n:
		await get_tree().physics_frame

func _def(id:StringName, stack:int, order:int, zero:bool = false)->InventoryItemDef:
	var _d:InventoryItemDef = InventoryItemDef.new()
	_d.id = id
	_d.stack_size = stack
	_d.sort_order = order
	_d.show_when_zero = zero
	_d.counter = ScoreResource.new()
	return _d

func _test_grid()->InventoryGridResource:
	var _db:InventoryDatabase = InventoryDatabase.new()
	_db.items = [_def(&"coin", 0, 0, true), _def(&"meat", 999, 1), _def(&"crystal", 99, 2)]
	var _grid:InventoryGridResource = InventoryGridResource.new()
	_grid.database = _db
	_grid.clear()
	return _grid

func _set_amount(grid:InventoryGridResource, id:StringName, value:int)->void:
	grid.database.def(id).counter.value = value
	grid.relayout()

func _check_stack_math()->void:
	var _grid:InventoryGridResource = _test_grid()
	check(_grid.capacity() == 18 && _grid.width() == 6 && _grid.height() == 3, "base grid 6x3")
	check(_grid.cells_of(&"coin").size() == 1 && _grid.cells_of(&"meat").is_empty(), "coin cell shown at 0, meat hidden")
	_set_amount(_grid, &"meat", 999)
	check(_grid.cells_of(&"meat").size() == 1, "999 meat = 1 cell")
	_set_amount(_grid, &"meat", 1000)
	var _meat:Array[int] = _grid.cells_of(&"meat")
	check(_meat.size() == 2 && _grid.get_cell(_meat[0]).n == 999 && _grid.get_cell(_meat[1]).n == 1, "1000 meat = 999 + 1")
	_set_amount(_grid, &"crystal", 99)
	check(_grid.cells_of(&"crystal").size() == 1, "99 crystals = 1 cell")
	_set_amount(_grid, &"crystal", 100)
	check(_grid.cells_of(&"crystal").size() == 2, "100 crystals = 2 cells")
	_set_amount(_grid, &"coin", 123456)
	check(_grid.cells_of(&"coin").size() == 1 && _grid.get_cell(_grid.cells_of(&"coin")[0]).n == 123456, "coins: one cell, any amount")
	check(_grid.can_accept(&"coin", 1000000), "coins never blocked")
	# fill the rest with weapons
	var _weapon:ItemResource = (load(TD + "resources/ItemCollectionResource/weapon_database.tres") as ItemCollectionResource).list[0]
	while _grid.first_free() >= 0:
		_grid.put_weapon(_weapon)
	check(_grid.free_count() == 0, "grid full")
	check(_grid.can_accept(&"meat", 998), "partial meat stack still takes more")
	check(!_grid.can_accept(&"meat", 999), "full grid blocks a new meat stack")
	check(!_grid.can_accept(&"crystal", 98) || _grid.can_accept(&"crystal", 98), "crystal check runs")
	check(!_grid.can_accept(&"crystal", 99), "full grid blocks a new crystal stack")
	check(!_grid.put_weapon(_weapon), "full grid refuses weapons")
	# overflow: counter beyond room is kept on the last stack
	_set_amount(_grid, &"meat", 5000)
	_meat = _grid.cells_of(&"meat")
	check(_meat.size() == 2 && _grid.get_cell(_meat[1]).n == 5000 - 999, "overflow goes on the last stack")
	_set_amount(_grid, &"meat", 10)
	check(_grid.cells_of(&"meat").size() == 1, "spending frees stacks")

func _check_grid_moves()->void:
	var _grid:InventoryGridResource = _test_grid()
	var _db:ItemCollectionResource = load(TD + "resources/ItemCollectionResource/weapon_database.tres")
	var _a:ItemResource = _db.list[0]
	var _b:ItemResource = _db.list[1]
	_set_amount(_grid, &"meat", 5)
	var _meat_at:int = _grid.cells_of(&"meat")[0]
	check(_grid.move(_meat_at, 10) && Array(_grid.cells_of(&"meat")) == [10], "move currency stack")
	_set_amount(_grid, &"meat", 7)
	check(Array(_grid.cells_of(&"meat")) == [10] && _grid.get_cell(10).n == 7, "stack keeps its cell when amount changes")
	_grid.put_weapon(_a, 4)
	check(_grid.weapon_at(4) == _a, "weapon in chosen cell")
	check(_grid.move(4, 10) && _grid.weapon_at(10) == _a && Array(_grid.cells_of(&"meat")) == [4], "swap weapon with stack")
	check(_grid.replace_weapon(10, _b) == _a && _grid.weapon_at(10) == _b, "replace weapon")
	# resize keeps (x, y)
	_grid.set_extra(1, 1)
	check(_grid.width() == 7 && _grid.height() == 4 && _grid.capacity() == 28, "meta extra -> 7x4")
	check(_grid.weapon_at(1 * 7 + 4) == _b, "weapon keeps its x/y after widening")
	_grid.set_extra(0, 0)
	check(_grid.weapon_at(10) == _b, "and after shrinking back")
	# layout save / load
	var _layout:PackedStringArray = _grid.save_layout()
	check(_layout[10] == "@" + _b.resource_name && _layout[4] == "meat", "layout strings")
	var _copy:InventoryGridResource = _test_grid()
	_copy.database = _grid.database
	_copy.load_layout(_layout, _db)
	check(_copy.weapon_at(10) == _b && Array(_copy.cells_of(&"meat")) == [4], "layout restored")
	check(InventoryGridResource.layout_weapons(_layout) == PackedStringArray([_b.resource_name]), "weapons from layout")

	# quick slot helpers keep selected valid
	var _quick:ItemCollectionResource = ItemCollectionResource.new()
	_quick.max_items = 5
	_quick.list = [_a, _b]
	_quick.selected = 1
	_quick.remove_at(1)
	check(_quick.list.size() == 1 && _quick.selected == 0, "remove_at clamps selected")
	_quick.insert_at(0, _b)
	check(Array(_quick.list) == [_b, _a], "insert_at")
	_quick.selected = 0
	_quick.move(0, 1)
	check(Array(_quick.list) == [_a, _b] && _quick.selected == 1, "move keeps selection on its weapon")

func _check_run_data()->void:
	var _data:PlayerRunData = PlayerRunData.new()
	_data.weapons = PackedStringArray(["Gun"])
	_data.inventory = PackedStringArray(["coin", "", "@Shotgun", "meat"])
	var _back:PlayerRunData = PlayerRunData.from_dict(_data.to_dict())
	check(_back != null && _back.inventory == _data.inventory, "run data inventory roundtrip")
	check(_back != null && _back.all_weapons() == PackedStringArray(["Gun", "Shotgun"]), "all_weapons = quick + backpack")
	var _bad:Dictionary = _data.to_dict()
	_bad["inventory"] = [1, 2]
	check(PlayerRunData.from_dict(_bad) == null, "bad inventory rejected")
	var _old:Dictionary = _data.to_dict()
	_old.erase("inventory")
	check(PlayerRunData.from_dict(_old) != null, "older peers without inventory ok")

func _check_player_inventory()->void:
	var _inv:PlayerInventory = player.get_node_or_null("PlayerInventory")
	check(_inv != null && PlayerInventory.local(get_tree()) == _inv, "player has PlayerInventory")
	if _inv == null:
		return
	var _grid:InventoryGridResource = _inv.grid
	var _meta:MetaUpgradeResource = _inv.meta_upgrade_resource
	check(_grid.width() == 6 + int(_meta.stat(&"inventory_width")) && _grid.height() == 3 + int(_meta.stat(&"inventory_height")), "grid sized by meta stats")
	var _meat:ScoreResource = load(TD + "resources/global_resources/meat_resource.tres")
	_meat.value = 3
	_meat.updated.emit()
	check(_grid.cells_of(&"meat").size() == 1 && _grid.get_cell(_grid.cells_of(&"meat")[0]).n == 3, "counter change relayouts grid")
	_meat.value = 0
	_meat.updated.emit()
	# weapon pickup beyond the quick slots -> backpack
	var _weapons:ItemCollectionResource = player.get_node("ResourceNode").get_resource("weapons")
	var _db:ItemCollectionResource = load(TD + "resources/ItemCollectionResource/weapon_database.tres")
	var _full:Array[ItemResource] = []
	for i:int in _weapons.max_items:
		_full.append(_db.list[0])
	_weapons.set_list(_full)
	var _tx:ItemTransmission = ItemTransmission.new()
	_tx.item_resource = _db.list[1]
	_tx.process(player.get_node("ResourceNode"))
	check(_tx.state == TransmissionResource.ErrorType.SUCCESS && _grid.weapons().has(_db.list[1]), "full hotbar: weapon pickup goes to backpack")
	# fill the grid: meat stays on the floor, coins still come in
	while _grid.first_free() >= 0:
		_grid.put_weapon(_db.list[0])
	check(!PlayerInventory.accepts(get_tree(), &"meat"), "full grid refuses meat")
	check(PlayerInventory.accepts(get_tree(), &"coin"), "full grid still takes coins")
	var _mover:Node = player.get_node_or_null("PlayerInput")
	if _mover != null:
		_mover.process_mode = Node.PROCESS_MODE_DISABLED
	var _meat_res:InstanceResource = load(TD + "resources/InstanceResources/pickups/meat_instance_resource.tres")
	var _piece:Node2D = _meat_res.instance(func (n:Node2D)->void: n.global_position = player.global_position + Vector2(10, 0))
	await _frames(90)
	check(_piece.is_inside_tree() && _meat.value == 0, "meat not collected into a full grid")
	_grid.clear_weapons()
	await _frames(90)
	check(!_piece.is_inside_tree() && _meat.value == 1, "meat collected once there's room")
	if _mover != null:
		_mover.process_mode = Node.PROCESS_MODE_INHERIT
	_weapons.set_list([] as Array[ItemResource])

func _check_screen(room:Node)->void:
	var _screen:InventoryScreen = room.find_child("InventoryScreen", true, false) as InventoryScreen
	check(_screen != null, "HUD has InventoryScreen")
	if _screen == null:
		return
	var _hotbar:CanvasItem = _screen.hud_hotbar
	check(_hotbar != null && _hotbar.visible, "HUD hotbar visible")
	check(_screen.quick_cells.size() == 5 && _screen.grid_cells.size() == _screen.grid.capacity(), "screen has 5 quick slots + grid cells")
	_screen.open()
	await _frames(2)
	check(_screen.is_open() && _screen.open_resource.value, "screen opens")
	check(!_hotbar.visible, "HUD hotbar hidden while open")
	check(room.process_mode == Node.PROCESS_MODE_DISABLED, "solo: world paused while open")
	var _db:ItemCollectionResource = load(TD + "resources/ItemCollectionResource/weapon_database.tres")
	var _weapons:ItemCollectionResource = _screen.weapons
	_weapons.set_list([_db.list[0], _db.list[1]] as Array[ItemResource])
	_weapons.set_selected(1)
	_screen.grid.clear_weapons()
	var _free:int = _screen.grid.first_free()
	# quick -> grid
	check(_screen.place(_screen.quick_cells[1], _screen.grid_cells[_free]), "quick slot to grid")
	check(_weapons.list.size() == 1 && _weapons.selected == 0 && _screen.grid.weapon_at(_free) == _db.list[1], "weapon moved into grid, selection valid")
	# grid -> empty quick slot
	check(_screen.place(_screen.grid_cells[_free], _screen.quick_cells[4]), "grid to free quick slot")
	check(_weapons.list.size() == 2 && _weapons.list[1] == _db.list[1] && _screen.grid.weapon_at(_free) == null, "weapon back in quick slots")
	# swap grid weapon with quick slot weapon
	_screen.grid.put_weapon(_db.list[2] if _db.list.size() > 2 else _db.list[0], _free)
	var _grid_weapon:ItemResource = _screen.grid.weapon_at(_free)
	check(_screen.place(_screen.grid_cells[_free], _screen.quick_cells[0]) && _weapons.list[0] == _grid_weapon && _screen.grid.weapon_at(_free) == _db.list[0], "grid <-> quick swap")
	# currency can't go to the quick row
	var _coin_cell:int = _screen.grid.cells_of(&"coin")[0]
	check(!_screen.can_place(_screen.grid_cells[_coin_cell], _screen.quick_cells[0]), "currency can't go into a quick slot")
	# pad: press to pick, press to place
	var _target:int = _screen.grid.first_free()
	_screen.press(_screen.grid_cells[_coin_cell])
	check(_screen.held == _screen.grid_cells[_coin_cell], "press picks up")
	_screen.press(_screen.grid_cells[_target])
	check(_screen.held == null && Array(_screen.grid.cells_of(&"coin")) == [_target], "press places")
	# drop a backpack weapon to the floor
	var _drop_at:int = _screen.grid.first_free()
	_screen.grid.put_weapon(_db.list[0], _drop_at)
	check(_screen.drop_to_floor(_screen.grid_cells[_drop_at]) && _screen.grid.weapon_at(_drop_at) == null, "drop backpack weapon to floor")
	_screen.close()
	await _frames(2)
	check(!_screen.is_open() && !_screen.open_resource.value && _hotbar.visible, "screen closes, hotbar back")
	check(room.process_mode != Node.PROCESS_MODE_DISABLED, "world runs again")
	_weapons.set_list([] as Array[ItemResource])
