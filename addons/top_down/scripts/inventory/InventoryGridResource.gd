## The inventory cell grid (one per player, run scoped like weapon_inventory).
## Currency amounts stay in their counters (ScoreResource): the grid only keeps
## where their stacks sit; relayout() follows the counters. Weapons beyond the
## quick slots live in cells here (the backpack).
## Cell entry: null, {"id": StringName, "n": int} or {"weapon": ItemResource}.
class_name InventoryGridResource
extends Resource

signal changed_cells
signal resized

## Weapons in cells are written "@Name" in saved layouts
const WEAPON_PREFIX:String = "@"

@export var database:InventoryDatabase
@export_range(1, 16, 1) var base_width:int = 6
@export_range(1, 16, 1) var base_height:int = 3
## Added by meta upgrades (PlayerInventory)
@export var extra_width:int
@export var extra_height:int

var cells:Array = []

func width()->int:
	return maxi(base_width + extra_width, 1)

func height()->int:
	return maxi(base_height + extra_height, 1)

func capacity()->int:
	return width() * height()

func _ensure()->void:
	if cells.size() != capacity():
		cells.resize(capacity())

## Grows / shrinks the grid, keeping what sits at each (x, y) where it still fits.
func set_extra(w:int, h:int)->void:
	if w == extra_width && h == extra_height && cells.size() == capacity():
		return
	var _old_w:int = width()
	var _old:Array = cells.duplicate()
	extra_width = maxi(w, 0)
	extra_height = maxi(h, 0)
	cells = []
	cells.resize(capacity())
	var _homeless:Array = []
	for _i:int in _old.size():
		if _old[_i] == null:
			continue
		var _x:int = _i % _old_w
		var _y:int = _i / _old_w
		if _x < width() && _y < height():
			cells[_y * width() + _x] = _old[_i]
		else:
			_homeless.append(_old[_i])
	for _entry:Variant in _homeless:
		var _free:int = first_free()
		if _free >= 0:
			cells[_free] = _entry
		elif (_entry as Dictionary).has("weapon"):
			push_warning("inventory: no room left for %s" % (_entry.weapon as ItemResource).resource_name)
	relayout(false)
	resized.emit()
	changed_cells.emit()

func clear()->void:
	cells = []
	cells.resize(capacity())
	relayout()

func reset_resource()->void:
	clear()

func get_cell(index:int)->Variant:
	_ensure()
	return cells[index] if index >= 0 && index < cells.size() else null

func first_free()->int:
	_ensure()
	for _i:int in cells.size():
		if cells[_i] == null:
			return _i
	return -1

func free_count()->int:
	_ensure()
	var _n:int = 0
	for _entry:Variant in cells:
		if _entry == null:
			_n += 1
	return _n

func cells_of(id:StringName)->Array[int]:
	var _out:Array[int] = []
	for _i:int in cells.size():
		var _entry:Variant = cells[_i]
		if _entry != null && (_entry as Dictionary).get("id") == id:
			_out.append(_i)
	return _out

## Currency stacks follow their counters: as many cells as the amount needs
## (new ones in the first free cells), full stacks first, the rest in the last.
## Without room the last stack holds the extra (nothing is ever lost).
func relayout(emit:bool = true)->void:
	_ensure()
	if database != null:
		for _def:InventoryItemDef in database.currencies():
			_layout_item(_def)
	if emit:
		changed_cells.emit()

func _layout_item(def:InventoryItemDef)->void:
	var _value:int = def.amount()
	var _need:int = def.stacks_for(_value)
	var _at:Array[int] = cells_of(def.id)
	while _at.size() > _need:
		cells[_at.pop_back()] = null
	while _at.size() < _need:
		var _free:int = first_free()
		if _free < 0:
			break
		cells[_free] = {"id": def.id, "n": 0}
		_at.append(_free)
	_at.sort()
	var _left:int = _value
	for _k:int in _at.size():
		var _n:int = _left if def.is_infinite() || _k == _at.size() - 1 else mini(_left, def.stack_size)
		cells[_at[_k]]["n"] = maxi(_n, 0)
		_left -= _n

## Room for `amount` more of `id`? Unknown ids and unlimited stacks always fit.
func can_accept(id:StringName, amount:int = 1)->bool:
	if database == null:
		return true
	var _def:InventoryItemDef = database.def(id)
	if _def == null || _def.kind != InventoryItemDef.Kind.CURRENCY:
		return true
	_ensure()
	return _def.stacks_for(_def.amount() + amount) <= cells_of(id).size() + free_count()

## Swaps two cells. False when nothing moved.
func move(from:int, to:int)->bool:
	_ensure()
	if from == to || from < 0 || to < 0 || from >= cells.size() || to >= cells.size() || cells[from] == null:
		return false
	var _tmp:Variant = cells[to]
	cells[to] = cells[from]
	cells[from] = _tmp
	relayout()
	return true

## Weapon into a cell (first free by default). False when there's no room.
func put_weapon(item:ItemResource, cell:int = -1)->bool:
	_ensure()
	if item == null:
		return false
	if cell < 0:
		cell = first_free()
	if cell < 0 || cell >= cells.size() || cells[cell] != null:
		return false
	cells[cell] = {"weapon": item}
	changed_cells.emit()
	return true

func weapon_at(cell:int)->ItemResource:
	var _entry:Variant = get_cell(cell)
	return (_entry as Dictionary).get("weapon") as ItemResource if _entry != null else null

## Takes a weapon out of its cell; null when there's none.
func take_weapon(cell:int)->ItemResource:
	var _item:ItemResource = weapon_at(cell)
	if _item != null:
		cells[cell] = null
		changed_cells.emit()
	return _item

## Puts a weapon in a cell, handing back the one that was there (or null).
func replace_weapon(cell:int, item:ItemResource)->ItemResource:
	_ensure()
	var _old:ItemResource = weapon_at(cell)
	if cells[cell] != null && _old == null:
		return item
	cells[cell] = {"weapon": item} if item != null else null
	changed_cells.emit()
	return _old

func weapons()->Array[ItemResource]:
	var _out:Array[ItemResource] = []
	for _entry:Variant in cells:
		if _entry != null && (_entry as Dictionary).has("weapon"):
			_out.append(_entry.weapon)
	return _out

func weapon_names()->PackedStringArray:
	var _out:PackedStringArray = []
	for _item:ItemResource in weapons():
		_out.append(_item.resource_name)
	return _out

func clear_weapons()->void:
	for _i:int in cells.size():
		if cells[_i] != null && (cells[_i] as Dictionary).has("weapon"):
			cells[_i] = null
	changed_cells.emit()

## Saved form: one string per cell ("" empty, item id, or "@WeaponName").
func save_layout()->PackedStringArray:
	_ensure()
	var _out:PackedStringArray = []
	for _entry:Variant in cells:
		if _entry == null:
			_out.append("")
		elif (_entry as Dictionary).has("weapon"):
			_out.append(WEAPON_PREFIX + (_entry.weapon as ItemResource).resource_name)
		else:
			_out.append(String(_entry.id))
	return _out

## Restores a saved layout; weapons are looked up by name, cells that don't
## fit the current size go to the first free cell.
func load_layout(layout:PackedStringArray, weapon_database:ItemCollectionResource)->void:
	cells = []
	cells.resize(capacity())
	var _homeless:Array = []
	for _i:int in layout.size():
		var _text:String = layout[_i]
		var _entry:Variant = null
		if _text.begins_with(WEAPON_PREFIX):
			var _item:ItemResource = HomeBaseResource.find_item(weapon_database, _text.substr(1)) if weapon_database != null else null
			if _item != null:
				_entry = {"weapon": _item}
		elif !_text.is_empty() && database != null && database.def(StringName(_text)) != null:
			_entry = {"id": StringName(_text), "n": 0}
		if _entry == null:
			continue
		if _i < cells.size():
			cells[_i] = _entry
		else:
			_homeless.append(_entry)
	for _entry:Variant in _homeless:
		var _free:int = first_free()
		if _free >= 0:
			cells[_free] = _entry
	relayout()

## Weapon names from a saved layout.
static func layout_weapons(layout:PackedStringArray)->PackedStringArray:
	var _out:PackedStringArray = []
	for _text:String in layout:
		if _text.begins_with(WEAPON_PREFIX):
			_out.append(_text.substr(1))
	return _out
