class_name ItemTransmission
extends TransmissionResource

@export var item_resource:ItemResource

## Should result with a state change
func process(resource_node:ResourceNode)->void:
	match item_resource.type:
		ItemResource.ItemType.WEAPON:
			_weapon(resource_node)

func _weapon(resource_node:ResourceNode)->void:
	var _weapon_inventory:ItemCollectionResource = resource_node.get_resource("weapons")
	if _weapon_inventory.list.size() >= _weapon_inventory.max_items:
		# quick slots full: into the backpack (inventory grid) when there's room
		var _inventory:PlayerInventory = resource_node.get_parent().get_node_or_null(^"PlayerInventory") as PlayerInventory if resource_node.get_parent() != null else null
		if _inventory != null && _inventory.enabled && _inventory.stash_weapon(item_resource):
			success()
			return
		failed()
		return
	
	_weapon_inventory.append(item_resource)
	success()
