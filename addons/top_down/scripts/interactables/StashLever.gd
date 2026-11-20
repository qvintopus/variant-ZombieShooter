## Lever by the home chest, built by the "stash_lever" meta upgrade: while on,
## a new run puts the auto_stash items (InventoryItemDef) into the chest first
## (InventoryCarry, FreshStart). Hidden and solid-less until it's built.
class_name StashLever
extends Interactable

@export var home_base_resource:HomeBaseResource
@export var meta_upgrade_resource:MetaUpgradeResource
## Frame 0 off, 1 on
@export var sprite:Sprite2D
@export var value_label:Label
## Its solid part, off while it isn't built
@export var body:CollisionObject2D
@export var on_text:String = "STASH"
@export var off_text:String = "KEEP"

var _body_layer:int

func _ready()->void:
	super._ready()
	if body != null:
		_body_layer = body.collision_layer
	if meta_upgrade_resource != null:
		meta_upgrade_resource.updated.connect(_refresh)
	_refresh()

func _exit_tree()->void:
	super._exit_tree()
	if meta_upgrade_resource != null && meta_upgrade_resource.updated.is_connected(_refresh):
		meta_upgrade_resource.updated.disconnect(_refresh)

func is_built()->bool:
	return InventoryCarry.lever_built(meta_upgrade_resource)

func is_on()->bool:
	return home_base_resource != null && home_base_resource.auto_stash

func _refresh()->void:
	var _built:bool = is_built()
	visible = _built
	area.set_deferred("monitoring", _built)
	if body != null:
		body.set_deferred("collision_layer", _body_layer if _built else 0)
	if sprite != null:
		sprite.frame = int(is_on())
	if value_label != null:
		value_label.text = on_text if is_on() else off_text

func _can_use()->bool:
	return is_built() && home_base_resource != null && !Net.is_guest()

func _use()->void:
	home_base_resource.auto_stash = !home_base_resource.auto_stash
	home_base_resource.save_resource()
	_refresh()

func _prompt_text()->String:
	return "Auto-stash meat & slime: %s" % ("ON" if is_on() else "OFF")
