## The home base chest: interact opens the inventory screen with the chest's
## cells beside the player's (InventoryScreen.open_with). Its cells are the
## home's (HomeBase loads / saves them); a co-op guest in the host's home base
## can't open it.
class_name HomeChest
extends Interactable

@export var chest_grid:InventoryGridResource
## Frame 0 shut, 1 open (while the screen shows it)
@export var sprite:Sprite2D
@export var title:String = "CHEST"
@export var prompt:String = "Chest"
@export var guest_prompt:String = "Host's chest"

func _can_use()->bool:
	var _screen:InventoryScreen = InventoryScreen.find(get_tree())
	return !Net.is_guest() && chest_grid != null && _screen != null && _screen.can_open()

func _use()->void:
	var _screen:InventoryScreen = InventoryScreen.find(get_tree())
	if _screen == null:
		return
	_screen.open_with(chest_grid, title)
	if sprite != null:
		sprite.frame = 1
	if !_screen.closed.is_connected(_on_closed):
		_screen.closed.connect(_on_closed, CONNECT_ONE_SHOT)

func _on_closed()->void:
	if sprite != null:
		sprite.frame = 0

func _prompt_text()->String:
	return guest_prompt if Net.is_guest() else prompt
