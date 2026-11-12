## Who wears what: the host (slot 0, or the single player) keeps the plumber,
## every co-op guest is an electrician. Same 16x16, 8-frame strip layout, so only
## the texture changes. On a dedicated server slot 0 is the hidden player, and the
## plumber goes to its main player (PlayerState.main, Net.main_mode).
class_name PlayerSkin
extends RefCounted

const HOST_TEXTURE:Texture2D = preload("res://addons/top_down/assets/images/characters/plumber_16x16_strip8.png")
const GUEST_TEXTURE:Texture2D = preload("res://addons/top_down/assets/images/characters/electrician_16x16_strip8.png")
const SPRITE_PATH:NodePath = ^"Body/Stretch/Sprite2D"

## The plumber: the host's own player, or a dedicated server's main player.
static func is_plumber(state:PlayerState)->bool:
	if state == null || state.hidden:
		return false
	if Net.is_server() || Net.host_is_server:
		return state.main
	return state.slot == 0

static func texture_for(state:PlayerState)->Texture2D:
	return HOST_TEXTURE if is_plumber(state) else GUEST_TEXTURE

## Dresses a player body (local or puppet) for its state; the body remembers
## which one it wears (meta "plumber") so a change of main can be seen.
static func apply(body:Node, state:PlayerState)->void:
	if body == null || !is_instance_valid(body):
		return
	body.set_meta(&"plumber", is_plumber(state))
	var _sprite:Sprite2D = body.get_node_or_null(SPRITE_PATH) as Sprite2D
	if _sprite != null:
		_sprite.texture = texture_for(state)

## The body wears another skin than its state calls for now.
static func outdated(body:Node, state:PlayerState)->bool:
	return body != null && is_instance_valid(body) && body.get_meta(&"plumber", null) != is_plumber(state)

## A sprite on an effect copied from the local player (the corpse).
static func apply_to_sprites(node:Node, state:PlayerState)->void:
	var _texture:Texture2D = texture_for(state)
	for _child:Node in node.find_children("*", "Sprite2D", true, false):
		if (_child as Sprite2D).texture == HOST_TEXTURE:
			(_child as Sprite2D).texture = _texture
	if node is Sprite2D && (node as Sprite2D).texture == HOST_TEXTURE:
		(node as Sprite2D).texture = _texture
