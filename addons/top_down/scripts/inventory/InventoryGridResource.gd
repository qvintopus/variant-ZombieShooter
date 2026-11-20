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

## Currency stacks follow their counters. Each stack keeps its own amount (so
## stacks can be split); a counter going up fills stacks that have room, then
## new ones in the first free cells; going down empties the last stacks first.
## Without room the last stack holds the extra (nothing is ever lost).
func relayout(emit:bool = true)->void:
	_ensure()
	if database != null:
		for _def:InventoryItemDef in database.currencies():
			_layout_item(_def)
	if emit:
		changed_cells.emit()

func amount_at(index:int)->int:
	var _entry:Variant = get_cell(index)
	return int((_entry as Dictionary).get("n", 0)) if _entry != null else 0

func _total(at:Array[int])->int:
	var _sum:int = 0
	for _i:int in at:
		_sum += int(cells[_i].n)
	return _sum

func _layout_item(def:InventoryItemDef)->void:
	var _value:int = maxi(def.amount(), 0)
	var _at:Array[int] = cells_of(def.id)
	if def.is_infinite():
		# one cell holds it all
		while _at.size() > 1:
			cells[_at.pop_back()] = null
		if _at.is_empty() && def.stacks_for(_value) > 0:
			var _free:int = first_free()
			if _free >= 0:
				cells[_free] = {"id": def.id, "n": 0}
				_at.append(_free)
		if !_at.is_empty():
			if def.stacks_for(_value) == 0:
				cells[_at[0]] = null
			else:
				cells[_at[0]]["n"] = _value
		return
	var _diff:int = _value - _total(_at)
	# more: top up stacks with room, then new stacks
	for _i:int in _at:
		if _diff <= 0:
			break
		var _room:int = maxi(def.stack_size - int(cells[_i].n), 0)
		var _add:int = mini(_room, _diff)
		cells[_i]["n"] = int(cells[_i].n) + _add
		_diff -= _add
	while _diff > 0:
		var _free:int = first_free()
		if _free < 0:
			break
		var _add:int = mini(_diff, def.stack_size)
		cells[_free] = {"id": def.id, "n": _add}
		_at.append(_free)
		_diff -= _add
	if _diff > 0 && !_at.is_empty():
		var _last:int = _at.max()
		cells[_last]["n"] = int(cells[_last].n) + _diff
		_diff = 0
	# less: take from the last stacks first
	while _diff < 0 && !_at.is_empty():
		var _i:int = _at.max()
		var _take:int = mini(int(cells[_i].n), -_diff)
		cells[_i]["n"] = int(cells[_i].n) - _take
		_diff += _take
		if int(cells[_i].n) <= 0:
			cells[_i] = null
			_at.erase(_i)
	# empty stacks left from older layouts
	for _i:int in _at.duplicate():
		if int(cells[_i].n) <= 0:
			cells[_i] = null
			_at.erase(_i)
	if _at.is_empty() && def.show_when_zero:
		var _free:int = first_free()
		if _free >= 0:
			cells[_free] = {"id": def.id, "n": 0}

## Room for `amount` more of `id`? Unknown ids and unlimited stacks always fit.
func can_accept(id:StringName, amount:int = 1)->bool:
	if database == null:
		return true
	var _def:InventoryItemDef = database.def(id)
	if _def == null || _def.kind != InventoryItemDef.Kind.CURRENCY || _def.is_infinite():
		return true
	_ensure()
	var _room:int = free_count() * _def.stack_size
	for _i:int in cells_of(id):
		_room += maxi(_def.stack_size - int(cells[_i].n), 0)
	return _room >= amount

func _def_at(index:int)->InventoryItemDef:
	var _entry:Variant = get_cell(index)
	if _entry == null || !(_entry as Dictionary).has("id") || database == null:
		return null
	return database.def(_entry.id)

## Moves a cell onto another: the same item merges (up to a full stack, the
## rest stays), anything else swaps. False when nothing moved.
func move(from:int, to:int)->bool:
	_ensure()
	if from == to || from < 0 || to < 0 || from >= cells.size() || to >= cells.size() || cells[from] == null:
		return false
	var _def:InventoryItemDef = _def_at(from)
	if _def != null && !_def.is_infinite() && _def_at(to) == _def:
		var _room:int = maxi(_def.stack_size - amount_at(to), 0)
		if _room > 0:
			_shift(from, to, mini(_room, amount_at(from)))
			changed_cells.emit()
			return true
	var _tmp:Variant = cells[to]
	cells[to] = cells[from]
	cells[from] = _tmp
	relayout()
	return true

## How much of a stack a split takes (the bigger half).
func half_of(index:int)->int:
	return ceili(amount_at(index) / 2.0)

## Can `from` be split onto `to` (empty cell or the same item with room)?
func can_split(from:int, to:int)->bool:
	var _def:InventoryItemDef = _def_at(from)
	if _def == null || _def.is_infinite() || from == to || amount_at(from) < 2:
		return false
	var _target:Variant = get_cell(to)
	if _target == null:
		return to >= 0 && to < cells.size()
	return _def_at(to) == _def && amount_at(to) < _def.stack_size

## Moves `amount` (default: half) of a stack into an empty cell or onto the
## same item. False when nothing moved.
func split(from:int, to:int, amount:int = -1)->bool:
	_ensure()
	if !can_split(from, to):
		return false
	var _def:InventoryItemDef = _def_at(from)
	if amount < 0:
		amount = half_of(from)
	amount = mini(amount, amount_at(from))
	if cells[to] == null:
		cells[to] = {"id": _def.id, "n": 0}
	amount = mini(amount, maxi(_def.stack_size - amount_at(to), 0))
	if amount <= 0:
		return false
	_shift(from, to, amount)
	changed_cells.emit()
	return true

func _shift(from:int, to:int, amount:int)->void:
	cells[to]["n"] = amount_at(to) + amount
	cells[from]["n"] = amount_at(from) - amount
	if amount_at(from) <= 0:
		cells[from] = null

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

## Saved form: one string per cell ("" empty, "id:amount", or "@WeaponName").
func save_layout()->PackedStringArray:
	_ensure()
	var _out:PackedStringArray = []
	for _entry:Variant in cells:
		if _entry == null:
			_out.append("")
		elif (_entry as Dictionary).has("weapon"):
			_out.append(WEAPON_PREFIX + (_entry.weapon as ItemResource).resource_name)
		else:
			_out.append("%s:%d" % [_entry.id, int(_entry.get("n", 0))])
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
		elif !_text.is_empty() && database != null:
			var _parts:PackedStringArray = _text.split(":")
			if database.def(StringName(_parts[0])) != null:
				_entry = {"id": StringName(_parts[0]), "n": maxi(_parts[1].to_int(), 0) if _parts.size() > 1 else 0}
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
