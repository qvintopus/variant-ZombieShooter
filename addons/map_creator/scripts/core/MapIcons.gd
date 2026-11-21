## Icon of a catalog item for menus: its own `icon`, else its `icon_scene`'s sprite, else derived from the asset it puts in
## the room: a floor look's tile from the floor tileset, a wall / hole tile from that
## layer, an entity's sprite frame (first Sprite2D / AnimatedSprite2D of its scene that
## isn't a shadow). Null when there's nothing to show (markers): callers draw a swatch.
class_name MapIcons
extends RefCounted

## Sprite nodes skipped when looking for an entity's look.
const SKIP_NAMES:PackedStringArray = ["Shadow", "Outline", "Highlight"]

var _cache:Dictionary = {}

func clear()->void:
	_cache.clear()

func of(item:MapCatalogItem, creator:MapCreator)->Texture2D:
	if item == null:
		return null
	if item.icon != null:
		return item.icon
	if _cache.has(item.id):
		return _cache[item.id]
	var _icon:Texture2D = null
	match item.kind:
		MapCatalogItem.Kind.FLOOR:
			if creator.floor_layer != null:
				_icon = tile(creator.floor_layer.tile_set, item.floor_source, item.floor_atlas)
		MapCatalogItem.Kind.WALL:
			_icon = layer_tile(creator.walls_layer)
		MapCatalogItem.Kind.HOLE:
			_icon = layer_tile(creator.holes_layer)
		_:
			_icon = scene_sprite(item.icon_scene if !item.icon_scene.is_empty() else item.scene_path)
	_cache[item.id] = _icon
	return _icon

## Atlas region of one tile.
static func tile(tile_set:TileSet, source_id:int, atlas:Vector2i)->Texture2D:
	if tile_set == null || !tile_set.has_source(source_id):
		return null
	var _source:TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
	if _source == null || _source.texture == null || !_source.has_tile(atlas):
		return null
	var _icon:AtlasTexture = AtlasTexture.new()
	_icon.atlas = _source.texture
	_icon.region = _source.get_tile_texture_region(atlas)
	return _icon

## A tile the layer uses (the most common one: a plain middle piece, not an edge).
static func layer_tile(layer:TileMapLayer)->Texture2D:
	if layer == null:
		return null
	var _counts:Dictionary = {}
	for _cell:Vector2i in layer.get_used_cells():
		var _key:Vector3i = Vector3i(layer.get_cell_source_id(_cell), layer.get_cell_atlas_coords(_cell).x, layer.get_cell_atlas_coords(_cell).y)
		_counts[_key] = int(_counts.get(_key, 0)) + 1
	var _best:Vector3i = Vector3i(-1, 0, 0)
	for _key:Vector3i in _counts:
		if _best.x == -1 || _counts[_key] > _counts[_best]:
			_best = _key
	return tile(layer.tile_set, _best.x, Vector2i(_best.y, _best.z)) if _best.x != -1 else null

## The entity scene's sprite frame (instantiated off-tree, then freed).
static func scene_sprite(path:String)->Texture2D:
	if path.is_empty() || !ResourceLoader.exists(path):
		return null
	var _scene:PackedScene = load(path) as PackedScene
	if _scene == null:
		return null
	var _root:Node = _scene.instantiate()
	var _icon:Texture2D = _find_sprite(_root)
	_root.free()
	return _icon

static func _find_sprite(node:Node)->Texture2D:
	if !SKIP_NAMES.has(String(node.name)):
		if node is Sprite2D && (node as Sprite2D).texture != null:
			return sprite_frame(node)
		if node is AnimatedSprite2D:
			var _sprite:AnimatedSprite2D = node
			if _sprite.sprite_frames != null && _sprite.sprite_frames.has_animation(_sprite.animation) && _sprite.sprite_frames.get_frame_count(_sprite.animation) > 0:
				return _sprite.sprite_frames.get_frame_texture(_sprite.animation, clampi(_sprite.frame, 0, _sprite.sprite_frames.get_frame_count(_sprite.animation) - 1))
	for _child:Node in node.get_children():
		var _icon:Texture2D = _find_sprite(_child)
		if _icon != null:
			return _icon
	return null

## Region / hframes / frame of a Sprite2D as its own texture.
static func sprite_frame(sprite:Sprite2D)->Texture2D:
	var _rect:Rect2 = sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, sprite.texture.get_size())
	if sprite.hframes > 1 || sprite.vframes > 1:
		var _cell:Vector2 = _rect.size / Vector2(sprite.hframes, sprite.vframes)
		_rect = Rect2(_rect.position + _cell * Vector2(sprite.frame % sprite.hframes, sprite.frame / sprite.hframes), _cell)
	if _rect.position == Vector2.ZERO && _rect.size == sprite.texture.get_size():
		return sprite.texture
	var _icon:AtlasTexture = AtlasTexture.new()
	_icon.atlas = sprite.texture
	_icon.region = _rect
	return _icon
