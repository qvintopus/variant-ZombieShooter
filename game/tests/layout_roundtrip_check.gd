## Every room layout bakes (to user://layout_roundtrip/) into exactly the committed
## game/scenes/room_<key>.tscn, with no baker problems, and every catalog item is valid
## (unique id, scene/script files exist, entities only use known items, on floor cells).
##   Godot --headless --path . res://game/tests/layout_roundtrip_check.tscn
extends Node

const BAKER:String = "res://game/resources/map_creator/layout_baker.tres"
const OUT:String = "user://layout_roundtrip/"

var failures:int = 0
var checks:int = 0

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	var _baker:GameLayoutBaker = load(BAKER)
	_check_catalog(_baker.catalog)
	DirAccess.make_dir_recursive_absolute(OUT)
	_baker.write_dir = OUT
	_baker.problems = 0
	var _layouts:Dictionary = _baker.load_layouts()
	check(_layouts.size() >= 30, "layouts found (%d)" % _layouts.size())
	for _key:String in _layouts:
		var _layout:RoomLayoutResource = _layouts[_key]
		for _entity:LayoutEntity in _layout.entities:
			check(_baker.catalog.item(_entity.item_id) != null, "%s: entity '%s' is a catalog item" % [_key, _entity.item_id])
			check(_layout.floor.has(_entity.cell), "%s: %s at %s stands on floor" % [_key, _entity.item_id, _entity.cell])
		_baker.bake(_layout)
		var _baked:String = FileAccess.get_file_as_string(OUT + "room_%s.tscn" % _key)
		var _committed:String = FileAccess.get_file_as_string(_baker.scene_path(_key))
		check(!_baked.is_empty() && _baked == _committed, "room_%s.tscn matches its layout (rebuild with build_rooms.tscn)" % _key)
	_baker.write_dir = ""
	check(_baker.problems == 0, "baker problems: %d" % _baker.problems)
	print("layout_roundtrip_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _check_catalog(catalog:MapCatalog)->void:
	check(catalog != null && !catalog.categories.is_empty(), "the baker has a catalog")
	var _ids:Dictionary = {}
	for _category:MapCatalogCategory in catalog.categories:
		check(!_category.items.is_empty(), "category %s has items" % _category.id)
		check(!_category.operations.is_empty(), "category %s has operations" % _category.id)
	for _item:MapCatalogItem in catalog.all_items():
		check(!_ids.has(_item.id), "catalog id %s is unique" % _item.id)
		_ids[_item.id] = true
		if !_item.scene_path.is_empty():
			check(ResourceLoader.exists(_item.scene_path), "%s scene exists" % _item.id)
		if !_item.script_path.is_empty():
			check(ResourceLoader.exists(_item.script_path), "%s script exists" % _item.id)
