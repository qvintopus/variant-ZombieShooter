## Map creator selection and radial menu on room_N02: Ctrl+click toggles the top thing on
## a cell, Ctrl+drag box-selects, a plain click lets go; ring 1 of the radial menu holds
## the hovered thing (or each selected type plus all of them), the room's kinds of things
## and More (categories); ring 2 the operations, "Change to" a third ring. Remove, select
## all, remove all, duplicate, move and replace work on selections, one undo step each.
##   Godot --headless --path . res://game/tests/map_creator_selection_check.tscn
extends Node

const BAKER:String = "res://game/resources/map_creator/layout_baker.tres"
const CREATOR:String = "res://addons/map_creator/scenes/map_creator.tscn"
const KEY:String = "N02"

var failures:int = 0
var checks:int = 0
var _creator:MapCreator

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	(load("res://addons/top_down/resources/global_resources/action_resource.tres") as ActionResource).reset_resource()
	var _room:Node2D = (load("res://game/scenes/room_%s.tscn" % KEY) as PackedScene).instantiate()
	_creator = (load(CREATOR) as PackedScene).instantiate()
	_creator.settings = MapCreatorSettings.new()
	_creator.settings.not_saved = true
	_creator.room = _room
	add_child(_room)
	_room.add_child(_creator)
	for _i:int in 3:
		await get_tree().process_frame
	_creator.set_editing(true)
	_check_selecting()
	_check_radial()
	_check_operations()
	print("map_creator_selection_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _click(cell:Vector2i, ctrl:bool)->void:
	_creator.hover_cell = cell
	_creator._left_pressed(ctrl)
	_creator._left_released()

func _drag(from:Vector2i, to:Vector2i)->void:
	_creator.hover_cell = from
	_creator._left_pressed(true)
	_creator.hover_cell = to
	_creator._left_released()

func _first(id:StringName)->LayoutEntity:
	var _list:Array[LayoutEntity] = _creator.layout.entities_of(id)
	return _list[0] if !_list.is_empty() else null

func _labels(slices:Array)->Array:
	return slices.map(func (s:Dictionary)->String: return s.label)

func _index(slices:Array, label:String)->int:
	return _labels(slices).find(label)

func _check_selecting()->void:
	var _sel:MapSelection = _creator.selection
	var _spawn:LayoutEntity = _first(&"spawn")
	check(_sel.type_at(_spawn.cell) == &"spawn", "an entity is the top thing on its cell")
	check(_sel.types_at(_spawn.cell).size() >= 2, "the floor under it counts too")
	_click(_spawn.cell, true)
	check(_sel.has(_spawn.cell, &"spawn"), "Ctrl+click selects the entity")
	check(_creator.inspected == _creator.layout.entity_at(_spawn.cell), "selecting one entity opens it in the inspector")
	_click(_spawn.cell, true)
	check(_sel.is_empty(), "Ctrl+click again unselects it")
	_drag(_spawn.cell - Vector2i(2, 2), _spawn.cell + Vector2i(2, 2))
	check(_sel.size() >= 20 && _sel.types().has(&"spawn"), "Ctrl+drag selects the box (%d, %s)" % [_sel.size(), _sel.types()])
	_creator.set_tool(MapCreator.Tool.PAINT)
	var _floor_before:Vector3i = _creator.layout.floor[_spawn.cell + Vector2i(5, 5)] if _creator.layout.floor.has(_spawn.cell + Vector2i(5, 5)) else Vector3i.ZERO
	_click(_spawn.cell + Vector2i(5, 5), false)
	check(_sel.is_empty(), "a plain click lets go of the selection")
	check(!_creator.can_undo(), "that click doesn't paint")

func _check_radial()->void:
	var _spawn:LayoutEntity = _first(&"spawn")
	var _ring:Array = _creator.radial_slices(_spawn.cell)
	check(_ring[0].label == "This Enemy spawner", "ring 1 starts with the hovered thing (%s)" % _ring[0].label)
	var _ops:Array = _labels(_ring[0].children)
	for _op:String in ["Use as brush", "Modify", "Change to", "Duplicate", "Move", "Remove"]:
		check(_ops.has(_op), "the hovered thing offers %s (%s)" % [_op, _ops])
	var _labels_1:Array = _labels(_ring)
	for _name:String in ["Enemy spawner", "Stairs", "Portal", "Wall", "Hole", "Gate", "Barrier", "Section trigger", "Sandstone floor"]:
		check(_labels_1.has(_name), "ring 1 lists the room's %s" % _name)
	check(_ring[-1].label == "More..." && _ring[-1].children.size() == _creator.catalog.categories.size(), "More opens the categories")
	var _catalog_ops:Array = _labels(_ring[_index(_ring, "Enemy spawner")].children)
	for _op:String in ["Add here", "Select all", "Remove all", "Use as brush"]:
		check(_catalog_ops.has(_op), "a kind of thing offers %s (%s)" % [_op, _catalog_ops])
	var _change:Array = _ring[0].children[_index(_ring[0].children, "Change to")].children
	check(_labels(_change).has("Boss spawner"), "Change to lists the category's items (%s)" % [_labels(_change)])

	# selection rings: each type, then all of them
	var _gate:LayoutEntity = _first(&"gate")
	_creator.selection.set_entries([{"cell": _spawn.cell, "type": &"spawn"}, {"cell": _gate.cell, "type": &"gate"}, {"cell": _gate.cell + Vector2i(0, 1), "type": &"gate"}])
	_ring = _creator.radial_slices(_spawn.cell)
	check(_ring[0].label == "1 x Enemy spawner" && _ring[1].label == "2 x Gate" && _ring[2].label == "All 3 selected", "a selection puts each type and all of it first (%s)" % [_labels(_ring).slice(0, 3)])

	# through the menu control: hover opens the next ring, a click runs the action
	var _menu:RadialMenu = _creator.get_node("UI/Root/RadialMenu")
	_creator.selection.clear()
	_menu.open(Vector2.ZERO, _creator.radial_slices(_spawn.cell))
	check(_menu.is_open(), "the radial menu opens")
	_menu.hover_slice(0, 0)
	check(_menu.ring_slices(1).size() == _ring[0].children.size() || _menu.ring_slices(1).size() > 0, "hovering a slice opens ring 2")
	var _spawns:int = _creator.layout.entities_of(&"spawn").size()
	_menu.press_slice(1, _index(_menu.ring_slices(1), "Remove"))
	check(!_menu.is_open(), "an action closes the menu")
	check(_creator.layout.entities_of(&"spawn").size() == _spawns - 1, "Remove from the menu removes the spawner")
	_creator.undo()
	check(_creator.layout.entities_of(&"spawn").size() == _spawns, "undo brings it back")

func _check_operations()->void:
	var _layout:RoomLayoutResource = _creator.layout
	var _spawns:int = _layout.entities_of(&"spawn").size()
	_creator.select_type(&"spawn")
	check(_creator.selection.size() == _spawns, "Select all picks every spawner (%d)" % _creator.selection.size())
	check(_creator.inspected_group.size() == _spawns, "the inspector edits them together")
	_creator.set_entity_prop(_creator.inspected, &"max_simultaneous", 3)
	var _all_three:bool = true
	for _entity:LayoutEntity in _creator.layout.entities_of(&"spawn"):
		_all_three = _all_three && _entity.props.get("max_simultaneous", 0) == 3
	check(_all_three, "a prop edit applies to the whole group")
	_creator.undo()

	# duplicate a spawner one cell over
	var _spawn:LayoutEntity = _first(&"spawn")
	var _to:Vector2i = _spawn.cell + Vector2i(1, 0)
	if _creator.layout.entity_at(_to) != null || !_creator.layout.floor.has(_to):
		_to = _spawn.cell + Vector2i(-1, 0)
	_creator.hover_cell = _spawn.cell
	_creator.begin_move([{"cell": _spawn.cell, "type": &"spawn"}], true)
	_creator.confirm_move(_to)
	check(_creator.layout.entities_of(&"spawn").size() == _spawns + 1, "Duplicate adds a copy")
	check(_creator.layout.entity_at(_to) != null && _creator.layout.entity_at(_to).item_id == &"spawn", "the copy lands where it was dropped")
	check(_creator.selection.has(_to, &"spawn"), "the copy is selected")
	# move it back over by one more
	var _to2:Vector2i = _to + (_to - _spawn.cell)
	if _creator.layout.floor.has(_to2) && _creator.layout.entity_at(_to2) == null:
		_creator.hover_cell = _to
		_creator.begin_move(_creator.selection.entries(), false)
		_creator.confirm_move(_to2)
		check(_creator.layout.entity_at(_to) == null && _creator.layout.entity_at(_to2) != null, "Move takes it to the new cell")
	# replace
	_creator.replace_entries(_creator.selection.entries() if !_creator.selection.is_empty() else [{"cell": _to, "type": &"spawn"}], _creator.catalog.item(&"loot_box"))
	check(_creator.layout.entities_of(&"loot_box").size() >= 1 && _creator.layout.entities_of(&"spawn").size() == _spawns, "Change to swaps the item")
	var _floor_cell:Vector2i = _spawn.cell
	_creator.replace_entries([{"cell": _floor_cell, "type": &"floor_sandstone"}], _creator.catalog.item(&"floor_flesh"))
	check(_creator.layout.floor[_floor_cell].x == 50, "Change to repaints a floor look")
	check(_creator.layout.entity_at(_floor_cell) != null, "repainting the floor keeps the entity on it")
	# remove all
	_creator.remove_type(&"trigger")
	check(_creator.layout.entities_of(&"trigger").is_empty(), "Remove all clears every trigger")
	var _steps:int = 0
	while _creator.can_undo():
		_creator.undo()
		_steps += 1
	check(_creator.layout.entities_of(&"trigger").size() > 0 && _creator.layout.entities_of(&"spawn").size() == _spawns, "undo restores everything (%d steps)" % _steps)
