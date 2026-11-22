class_name ItemCollectionResource
extends SaveableResource

signal updated
signal removed(value:ItemResource, is_dropped:bool)
signal selected_changed

@export var list:Array[ItemResource]

@export var selected:int

@export var max_items:int

## Empties the collection for a new run; max_items is kept (set from balance.json).
func reset_resource()->void:
	list.clear()
	selected = 0
	updated.emit()
	selected_changed.emit()

func set_list(value:Array[ItemResource])->void:
	list = value
	updated.emit()

func set_selected(value:int)->void:
	if list.is_empty():
		selected = 0
	else:
		selected = abs(value + list.size()) % list.size()
	selected_changed.emit()

func append(value:ItemResource)->void:
	list.append(value)
	updated.emit()

func swap(value:ItemResource, is_dropped:bool = true)->ItemResource:
	var _item:ItemResource = list[selected]
	list[selected] = value
	updated.emit()
	removed.emit(_item, is_dropped)
	return _item

func drop()->ItemResource:
	if list.is_empty():
		return null
	var _item:ItemResource = list[selected]
	list[selected] = null
	
	list = list.filter(filter_empty)
	set_selected(min(selected, list.size() -1))
	
	updated.emit()
	removed.emit(_item, true)
	return _item

func take()->ItemResource:
	if list.is_empty():
		return null
	var _item:ItemResource = list[selected]
	list[selected] = null
	
	list = list.filter(filter_empty)
	set_selected(min(selected, list.size() -1))
	
	updated.emit()
	removed.emit(_item, false)
	return _item

## Inventory screen edits (list stays packed, `selected` stays valid).
func insert_at(index:int, value:ItemResource)->void:
	if value == null:
		return
	list.insert(clampi(index, 0, list.size()), value)
	_clamp_selected()
	updated.emit()

## Takes the item at index out (not dropped: it moves elsewhere).
func remove_at(index:int)->ItemResource:
	if index < 0 || index >= list.size():
		return null
	var _item:ItemResource = list[index]
	list.remove_at(index)
	_clamp_selected()
	updated.emit()
	removed.emit(_item, false)
	return _item

## Puts value at index, handing back what was there.
func replace_at(index:int, value:ItemResource)->ItemResource:
	if index < 0 || index >= list.size():
		insert_at(index, value)
		return null
	var _item:ItemResource = list[index]
	list[index] = value
	updated.emit()
	if _item != null && _item != value:
		removed.emit(_item, false)
	return _item

## Swaps two slots
func move(from:int, to:int)->void:
	if from < 0 || to < 0 || from >= list.size() || to >= list.size() || from == to:
		return
	var _tmp:ItemResource = list[to]
	list[to] = list[from]
	list[from] = _tmp
	if selected == from:
		selected = to
	elif selected == to:
		selected = from
	updated.emit()
	selected_changed.emit()

func _clamp_selected()->void:
	var _before:int = selected
	selected = clampi(selected, 0, maxi(list.size() - 1, 0))
	if selected != _before:
		selected_changed.emit()

func filter_empty(value:ItemResource)->bool:
	return value != null
