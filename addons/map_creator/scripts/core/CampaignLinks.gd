## How rooms' stairs / portals pair up: an exit leads to room `room` and arrives at the
## exit there tagged `connect_tag` (its partner). Stairs go both ways, so a stairs'
## partner stairs should lead back to it. Used by the campaign graph / preview (link
## lines, problems), the room's live checks and the save message.
class_name CampaignLinks
extends RefCounted

const LINKED:StringName = &"ok"
## No target room.
const NOWHERE:StringName = &"nowhere"
## Target room doesn't exist.
const MISSING:StringName = &"missing"
## Target room has no exit tagged connect_tag.
const BAD_TAG:StringName = &"bad_tag"
## Stairs arrive at stairs that don't lead back to them.
const ONE_WAY:StringName = &"one_way"
## Two exits of a room share a tag (arrivals are ambiguous).
const DUPLICATE:StringName = &"duplicate"
## Target is a hand-made scene: tags can't be checked.
const UNKNOWN:StringName = &"unknown"

static func target(entity:LayoutEntity)->String:
	return String(entity.props.get("room", "")).trim_prefix("room_")

static func is_link(entity:LayoutEntity)->bool:
	return entity.item_id == &"door" || entity.item_id == &"portal"

## Index of the exit in `layout` tagged `tag` (doors / portals), -1 = none.
static func tagged(layout:RoomLayoutResource, tag:String)->int:
	if layout == null || tag.is_empty():
		return -1
	for _i:int in layout.entities.size():
		var _entity:LayoutEntity = layout.entities[_i]
		if is_link(_entity) && String(_entity.props.get("tag", "")) == tag:
			return _i
	return -1

## Index of the exit entity `index` of room `key` arrives at, -1 = none.
static func partner(layouts:Dictionary, key:String, index:int)->int:
	var _entity:LayoutEntity = layouts[key].entities[index]
	return tagged(layouts.get(target(_entity), null), String(_entity.props.get("connect_tag", "")))

## LINKED / NOWHERE / MISSING / BAD_TAG / ONE_WAY / UNKNOWN of exit `index` of room `key`;
## `exists` (key -> bool) says whether a room without a layout has a scene.
static func state(layouts:Dictionary, key:String, index:int, exists:Callable = Callable())->StringName:
	var _entity:LayoutEntity = layouts[key].entities[index]
	var _to:String = target(_entity)
	if _to.is_empty():
		return NOWHERE
	if !layouts.has(_to):
		return UNKNOWN if exists.is_valid() && exists.call(_to) else MISSING
	var _p:int = partner(layouts, key, index)
	if _p < 0:
		return BAD_TAG
	var _back:LayoutEntity = layouts[_to].entities[_p]
	if _entity.item_id == &"door" && _back.item_id == &"door" \
			&& (target(_back) != key || String(_back.props.get("connect_tag", "")) != String(_entity.props.get("tag", ""))):
		return ONE_WAY
	return LINKED

## Problems of rooms `keys`: [{key, index, cell, kind, text}]. Portals arriving at a
## missing tag are the game baker's (_validate), so they're left out here.
static func problems(layouts:Dictionary, keys:Array, exists:Callable = Callable())->Array[Dictionary]:
	var _out:Array[Dictionary] = []
	for _key:String in keys:
		var _layout:RoomLayoutResource = layouts.get(_key, null)
		if _layout == null:
			continue
		var _tags:Dictionary = {}
		for _i:int in _layout.entities.size():
			var _entity:LayoutEntity = _layout.entities[_i]
			if !is_link(_entity):
				continue
			var _tag:String = String(_entity.props.get("tag", ""))
			if !_tag.is_empty():
				if _tags.has(_tag):
					_out.append(_problem(_key, _i, _entity, DUPLICATE, "%s at %s has tag '%s' like another exit" % [_entity.item_id, _entity.cell, _tag]))
				_tags[_tag] = true
			var _state:StringName = state(layouts, _key, _i, exists)
			var _to:String = target(_entity)
			var _arrive:String = String(_entity.props.get("connect_tag", ""))
			match _state:
				NOWHERE:
					_out.append(_problem(_key, _i, _entity, _state, "%s at %s leads nowhere" % [_entity.item_id, _entity.cell]))
				MISSING:
					_out.append(_problem(_key, _i, _entity, _state, "%s at %s leads to missing room_%s" % [_entity.item_id, _entity.cell, _to]))
				BAD_TAG:
					if _entity.item_id == &"door":
						_out.append(_problem(_key, _i, _entity, _state, "stairs at %s arrive at '%s', which room_%s doesn't have" % [_entity.cell, _arrive, _to]))
				ONE_WAY:
					var _back:LayoutEntity = layouts[_to].entities[partner(layouts, _key, _i)]
					var _where:String = "nowhere" if target(_back).is_empty() else "room_%s '%s'" % [target(_back), _back.props.get("connect_tag", "")]
					_out.append(_problem(_key, _i, _entity, _state, "stairs at %s -> room_%s '%s', which leads back to %s" % [_entity.cell, _to, _arrive, _where]))
	return _out

static func _problem(key:String, index:int, entity:LayoutEntity, kind:StringName, text:String)->Dictionary:
	return {"key": key, "index": index, "cell": entity.cell, "kind": kind, "text": text}
