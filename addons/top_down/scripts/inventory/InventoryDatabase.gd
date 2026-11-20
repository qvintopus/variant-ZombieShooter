## Every item kind the inventory grid knows.
class_name InventoryDatabase
extends Resource

@export var items:Array[InventoryItemDef]
## Used for weapons (icon comes from the weapon itself)
@export var weapon_def:InventoryItemDef

func def(id:StringName)->InventoryItemDef:
	for _item:InventoryItemDef in items:
		if _item != null && _item.id == id:
			return _item
	return null

## Currency defs in placing order
func currencies()->Array[InventoryItemDef]:
	var _out:Array[InventoryItemDef] = []
	for _item:InventoryItemDef in items:
		if _item != null && _item.kind == InventoryItemDef.Kind.CURRENCY:
			_out.append(_item)
	_out.sort_custom(func (a:InventoryItemDef, b:InventoryItemDef)->bool: return a.sort_order < b.sort_order)
	return _out
