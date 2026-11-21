## Map creator painting tools (MapTools) on a live room: bucket fill (same look, enclosed
## empty area, open area refused), line brush, mirror, scatter variants, eyedropper,
## copy / paste through the move ghost, and stamps (save, list, place).
##   Godot --headless --path . res://game/tests/map_creator_tools_check.tscn
extends Node

const BAKER:String = "res://game/resources/map_creator/layout_baker.tres"
const CREATOR:String = "res://addons/map_creator/scenes/map_creator.tscn"
const OUT:String = "user://map_creator_tools_check/"
const KEY:String = "N01"

var failures:int = 0
var checks:int = 0

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _frames(count:int)->void:
	for _i:int in count:
		await get_tree().process_frame

func _ready()->void:
	(load("res://addons/top_down/resources/global_resources/action_resource.tres") as ActionResource).reset_resource()
	var _source:GameLayoutBaker = load(BAKER)
	var _baker:GameLayoutBaker = _source.duplicate()
	_baker.catalog = _source.catalog
	_baker.layouts_dir = OUT + "layouts/"
	_baker.write_dir = OUT + "scenes/"
	_baker.balance_path = OUT + "balance.json"
	for _dir:String in [_baker.layouts_dir, _baker.write_dir]:
		DirAccess.make_dir_recursive_absolute(_dir)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/rooms/layouts/room_%s.tres" % KEY), ProjectSettings.globalize_path(_baker.layout_path(KEY)))
	_baker.load_layouts()
	var _room:Node2D = (load("res://game/scenes/room_%s.tscn" % KEY) as PackedScene).instantiate()
	var _creator:MapCreator = (load(CREATOR) as PackedScene).instantiate()
	_creator.baker = _baker
	_creator.settings = MapCreatorSettings.new()
	_creator.settings.not_saved = true
	_creator.settings.auto_clean = false
	_creator.room = _room
	add_child(_room)
	_room.add_child(_creator)
	await _frames(2)
	_creator.set_editing(true)
	await _frames(1)
	_check_fill(_creator)
	_check_line_mirror(_creator)
	_check_scatter(_creator)
	_check_pick(_creator)
	_check_clipboard(_creator)
	_check_stamps(_creator)
	_check_icons(_creator)
	_creator.set_editing(false)
	_room.queue_free()
	await _frames(2)
	print("map_creator_tools_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _item(creator:MapCreator, id:StringName)->MapCatalogItem:
	return creator.catalog.item(id)

func _check_fill(creator:MapCreator)->void:
	var _layout:RoomLayoutResource = creator.layout
	var _start:Vector2i = _layout.floor.keys()[0]
	var _region:Variant = MapTools.flood(_layout, _start, 100000)
	check(_region is Array && (_region as Array).size() > 10, "flood finds the room's floor (%d)" % (_region as Array).size())
	var _look:Vector3i = _layout.floor[_start]
	var _metal:MapCatalogItem = _item(creator, &"floor_metal")
	var _undo_before:int = creator._undo.size()
	check(creator.tools.fill(_start, _metal), "fill a floor look")
	var _all:bool = true
	for _cell:Vector2i in _region:
		_all = _all && creator.layout.floor[_cell].x == _metal.floor_source
	check(_all, "every cell of the region has the new look")
	check(creator._undo.size() == _undo_before + 1, "fill is one undo step")
	creator.undo()
	check(creator.layout.floor[_start] == _look, "undo restores the look")
	check(!creator.tools.fill(Vector2i(200, 200), _metal), "an open empty area isn't filled")
	# a ring of floor around a 3x3 empty pocket
	var _base:MapCatalogItem = _item(creator, &"floor_base")
	creator.edit(func ()->void:
		for _y:int in range(150, 155):
			for _x:int in range(150, 155):
				if _x == 150 || _x == 154 || _y == 150 || _y == 154:
					creator._put(Vector2i(_x, _y), _base))
	check(creator.tools.fill(Vector2i(152, 152), _base), "an enclosed empty pocket fills")
	check(creator.layout.floor.has(Vector2i(151, 151)) && creator.layout.floor.has(Vector2i(153, 153)), "the pocket's cells got floor")
	check(!creator.tools.fill(_start, _item(creator, &"spawn")), "fill refuses entities")

func _check_line_mirror(creator:MapCreator)->void:
	var _line:Array[Vector2i] = MapTools.line(Vector2i(0, 0), Vector2i(5, 2))
	check(_line.size() == 6 && _line[0] == Vector2i.ZERO && _line[-1] == Vector2i(5, 2), "line cells end to end")
	var _connected:bool = true
	for _i:int in range(1, _line.size()):
		var _d:Vector2i = (_line[_i] - _line[_i - 1]).abs()
		_connected = _connected && _d.x <= 1 && _d.y <= 1
	check(_connected, "line cells touch")
	creator.set_tool(MapCreator.Tool.PAINT)
	creator.select_item(_item(creator, &"floor_base"))
	creator.set_brush(MapCreator.Brush.LINE)
	creator.begin_stroke(Vector2i(170, 170))
	creator._apply_brush(Vector2i(176, 173))
	creator.end_stroke()
	check(creator.layout.floor.has(Vector2i(170, 170)) && creator.layout.floor.has(Vector2i(176, 173)) && !creator.layout.floor.has(Vector2i(176, 170)), "line brush paints just the line")
	creator.set_brush(MapCreator.Brush.ONE)
	creator.tools.mirror_x = true
	var _sum:Vector2i = creator.tools._bounds_sum()
	var _cells:Array[Vector2i] = creator.tools.mirrored(Vector2i(160, 160))
	check(_cells.has(Vector2i(_sum.x - 160, 160)), "mirror x adds the mirrored cell")
	creator.tools.mirror_y = true
	check(creator.tools.mirrored(Vector2i(161, 162)).size() == 4, "mirror x+y: four cells")
	creator.tools.mirror_x = false
	creator.tools.mirror_y = false

func _check_scatter(creator:MapCreator)->void:
	var _base:MapCatalogItem = _item(creator, &"floor_base")
	check(!_base.variants.is_empty(), "floor_base has variants")
	creator.tools.scatter = false
	check(creator.tools.pick_variant(_base) == _base, "no scatter: the item itself")
	creator.tools.scatter = true
	var _seen:Dictionary = {}
	for _i:int in 200:
		_seen[creator.tools.pick_variant(_base)] = true
	check(_seen.size() > 1, "scatter picks several variants (%d)" % _seen.size())
	creator.tools.scatter = false

func _check_pick(creator:MapCreator)->void:
	var _spawn:LayoutEntity = creator.layout.entities_of(&"spawn")[0] if !creator.layout.entities_of(&"spawn").is_empty() else null
	check(_spawn != null, "room has a spawn")
	if _spawn == null:
		return
	creator.pick_at(_spawn.cell)
	check(creator.item != null && creator.item.id == &"spawn", "eyedropper picks the spawn")
	check(creator.picked_props.get("section") == _spawn.props.get("section"), "and its props")
	check(creator.new_props(creator.item).get("section") == _spawn.props.get("section"), "new spawns copy them")
	creator.select_item(_item(creator, &"floor_base"))
	check(creator.picked_props.is_empty(), "choosing an item drops picked props")

func _check_clipboard(creator:MapCreator)->void:
	var _spawn:LayoutEntity = creator.layout.entities_of(&"spawn")[0]
	var _floor_cell:Vector2i = _spawn.cell + Vector2i(1, 0)
	creator.selection.set_entries([{"cell": _spawn.cell, "type": &"spawn"}, {"cell": _floor_cell, "type": creator.selection.floor_type(creator.layout.floor[_floor_cell])}])
	check(creator.tools.copy_selection() && creator.settings.clipboard.size() == 2, "copy the selection")
	creator.selection.clear()
	check(creator.tools.paste(creator.settings.clipboard) && !creator.moving.is_empty(), "paste starts the ghost")
	var _origin:Vector2i = creator.moving.origin
	var _to:Vector2i = Vector2i(152, 152)
	creator.confirm_move(_to)
	var _pasted:LayoutEntity = creator.layout.entity_at(_to + (_spawn.cell - _origin))
	check(_pasted != null && _pasted.item_id == &"spawn" && _pasted.props == _spawn.props, "paste drops a copy with its props")
	check(creator.layout.entity_at(_spawn.cell) != null, "the original stays")

func _check_stamps(creator:MapCreator)->void:
	var _stamps:Dictionary = MapTools.stamps()
	check(_stamps.has("pillar_2x2") && _stamps.has("spawn_square"), "built-in stamps listed")
	var _floor:Vector2i = Vector2i(151, 150)
	creator.selection.set_entries([{"cell": _floor, "type": creator.selection.floor_type(creator.layout.floor[_floor])}])
	check(creator.tools.save_stamp("tools check stamp"), "save a stamp")
	var _path:String = MapTools.USER_STAMPS.path_join("tools_check_stamp.json")
	check(FileAccess.file_exists(_path) && MapTools.stamps().has("tools_check_stamp"), "the stamp is saved and listed")
	check(creator.tools.load_stamp(_path).size() == 1, "the stamp loads back")
	creator.selection.clear()
	check(creator.tools.place_stamp("pillar_2x2"), "place a stamp")
	creator.confirm_move(Vector2i(171, 171))
	check(creator.layout.wall_overrides.get(Vector2i(171, 171), false) && creator.layout.wall_overrides.get(Vector2i(172, 172), false), "the stamp's walls land")
	var _hostile:Array = MapTools.payload_from_data([{"type": "evil", "cell": [0, 0]}, {"type": "door", "cell": [0, 0], "props": {"tag": "a\"\n"}}, {"type": "wall", "cell": [99999, 0]}], creator.catalog)
	check(_hostile.size() == 1 && !String(_hostile[0].entity.props.tag).contains("\""), "stamp JSON is cleaned")
	DirAccess.remove_absolute(_path)

## Menu icons: floor tile, wall tile, entity sprite (not the shadow), marker via icon_scene,
## trigger none (swatch); categories fall back to an item's icon.
func _check_icons(creator:MapCreator)->void:
	var _floor:Texture2D = creator.icon_of(creator.catalog.item(&"floor_mossy"))
	check(_floor is AtlasTexture && (_floor as AtlasTexture).atlas == (creator.floor_layer.tile_set.get_source(10) as TileSetAtlasSource).texture, "icon: floor look is its tile")
	check(creator.icon_of(creator.catalog.item(&"wall")) != null, "icon: wall tile")
	var _shrine:Texture2D = creator.icon_of(creator.catalog.item(&"shrine"))
	check(_shrine is AtlasTexture && !(_shrine as AtlasTexture).atlas.resource_path.contains("shadow"), "icon: entity sprite frame, not shadow")
	check(creator.icon_of(creator.catalog.item(&"spawn")) != null, "icon: spawn via icon_scene")
	check(creator.icon_of(creator.catalog.item(&"trigger")) == null, "icon: trigger has none")
	check(creator.icon_of(creator.catalog.item(&"door")) == creator.icon_of(creator.catalog.item(&"door")), "icon: cached")
	for _category:MapCatalogCategory in creator.catalog.categories:
		check(creator.category_icon(_category) != null, "icon: category %s" % _category.id)
	var _ring:Array = creator.radial_slices(Vector2i(10, 10))
	check(_ring.back().get("glyph") == "+", "icon: More... glyph")
