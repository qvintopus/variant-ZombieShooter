## Home base workbench: interact opens the meta-upgrade tree over the paused room
## (MetaTreeScreen.open_overlay); the home base is saved first. Shown once
## upgrades are unlocked (a boss crystal was ever picked up, like the title's
## Upgrades button). A co-op guest in the host's home base can't use it.
class_name MetaWorkbench
extends Interactable

@export var boss_crystal_resource:ScoreResource
@export var meta_upgrade_resource:MetaUpgradeResource
## Saved before the tree opens; found in the room when not set
@export var home_base:HomeBase
## Frame 0 idle, frame 1 while the tree is open
@export var sprite:Sprite2D
@export var prompt:String = "Upgrades"
@export var locked_prompt:String = "Needs a boss crystal"
@export var guest_prompt:String = "Host's workbench"

var _screen:MetaTreeScreen

func _ready()->void:
	super()
	# crystals and upgrades are loaded at boot (PersistentData)
	if home_base == null:
		home_base = _find_home_base()

func _find_home_base()->HomeBase:
	var _node:Node = get_parent()
	while _node != null:
		var _base:HomeBase = _node.get_node_or_null("HomeBase") as HomeBase
		if _base != null:
			return _base
		_node = _node.get_parent()
	return null

func is_unlocked()->bool:
	return MetaUpgradesEntry.is_unlocked(boss_crystal_resource, meta_upgrade_resource)

func _can_use()->bool:
	return !Net.is_guest() && is_unlocked() && !is_instance_valid(_screen)

func _use()->void:
	open_upgrades()

func open_upgrades()->MetaTreeScreen:
	if home_base != null:
		home_base.save_state()
	_screen = MetaTreeScreen.open_overlay(self)
	if sprite != null:
		sprite.frame = 1
	_screen.closed.connect(_on_closed, CONNECT_ONE_SHOT)
	return _screen

func _on_closed()->void:
	if sprite != null && is_instance_valid(sprite):
		sprite.frame = 0

func _exit_tree()->void:
	super()
	# leaving the room with the tree open (shouldn't happen: the room is paused)
	if is_instance_valid(_screen):
		get_tree().paused = false
		_screen.get_parent().queue_free()

func _prompt_text()->String:
	if Net.is_guest():
		return guest_prompt
	return prompt if is_unlocked() else locked_prompt
