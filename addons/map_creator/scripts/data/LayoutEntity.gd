## One placed thing in a RoomLayoutResource: a catalog item on a cell with its props.
class_name LayoutEntity
extends Resource

## MapCatalogItem.id
@export var item_id:StringName
@export var cell:Vector2i
## Per-entity values (section, tag, room, max_simultaneous, exports...).
@export var props:Dictionary = {}

static func make(id:StringName, at:Vector2i, values:Dictionary = {})->LayoutEntity:
	var _entity:LayoutEntity = LayoutEntity.new()
	_entity.item_id = id
	_entity.cell = at
	_entity.props = values.duplicate(true)
	return _entity

func copy()->LayoutEntity:
	return make(item_id, cell, props)
