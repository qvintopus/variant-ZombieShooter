## Everything the map creator offers, by category. Shared by the editor UI, the live
## applier and LayoutBaker.
class_name MapCatalog
extends Resource

@export var categories:Array[MapCatalogCategory] = []

var _by_id:Dictionary = {}
var _category_of:Dictionary = {}

func item(id:StringName)->MapCatalogItem:
	_index()
	return _by_id.get(id, null)

func category_of(id:StringName)->MapCatalogCategory:
	_index()
	return _category_of.get(id, null)

## Every item and variant.
func all_items()->Array[MapCatalogItem]:
	_index()
	var _list:Array[MapCatalogItem] = []
	for _item:MapCatalogItem in _by_id.values():
		_list.append(_item)
	return _list

func operations_of(id:StringName)->Array[MapCatalogOperation]:
	var _item:MapCatalogItem = item(id)
	if _item != null && !_item.operations.is_empty():
		return _item.operations
	var _category:MapCatalogCategory = category_of(id)
	if _category != null:
		return _category.operations
	return []

## First item of a kind (the default wall/hole).
func first_of_kind(kind:MapCatalogItem.Kind)->MapCatalogItem:
	for _item:MapCatalogItem in all_items():
		if _item.kind == kind:
			return _item
	return null

## FLOOR item painting this tileset source (and atlas, when one matches exactly).
func floor_item(source:int, atlas:Vector2i = Vector2i(-1, -1))->MapCatalogItem:
	var _found:MapCatalogItem = null
	for _item:MapCatalogItem in all_items():
		if _item.kind != MapCatalogItem.Kind.FLOOR || _item.floor_source != source:
			continue
		if _item.floor_atlas == atlas:
			return _item
		if _found == null:
			_found = _item
	return _found

func _index()->void:
	if !_by_id.is_empty():
		return
	for _category:MapCatalogCategory in categories:
		for _item:MapCatalogItem in _category.items:
			_add(_item, _category)

func _add(entry:MapCatalogItem, category:MapCatalogCategory)->void:
	if entry == null || _by_id.has(entry.id):
		return
	_by_id[entry.id] = entry
	_category_of[entry.id] = category
	for _variant:MapCatalogItem in entry.variants:
		_add(_variant, category)
