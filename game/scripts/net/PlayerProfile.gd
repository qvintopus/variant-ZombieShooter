## Who this install is: a random id made on first boot (later the Steam id) and a
## display name. Run saves and co-op sessions match players by profile_id.
class_name PlayerProfile
extends SaveableResource

@export var profile_id:String
@export var display_name:String = "Player"
## The player typed this name themselves. Until then it follows default_name(): the
## virtual LAN name of this PC (LAN Party addon, kept separate), else "Player".
@export var name_set:bool

func _init()->void:
	resource_name = "Profile"

func ensure_id()->void:
	if !profile_id.is_empty():
		return
	profile_id = Crypto.new().generate_random_bytes(16).hex_encode()
	save_resource()

func prepare_save()->Resource:
	var _data:PlayerProfile = PlayerProfile.new()
	_data.profile_id = profile_id
	# an unpicked name is saved as the stock one, so it keeps following the default
	_data.display_name = display_name if name_set else DEFAULT_NAME
	_data.name_set = name_set
	return _data

func prepare_load(data:Resource)->void:
	profile_id = data.profile_id
	display_name = data.display_name
	# saves from before name_set: a name other than the stock one was typed in
	name_set = data.get("name_set") == true || data.display_name != DEFAULT_NAME

func reset_resource()->void:
	profile_id = ""
	display_name = DEFAULT_NAME
	name_set = false

const DEFAULT_NAME:String = "Player"

## The name used while the player hasn't picked one.
static func default_name()->String:
	var _vlan:String = LanPartyAddresses.vlan_name()
	return _vlan if !_vlan.is_empty() else DEFAULT_NAME

## A name not picked by the player follows the default (the virtual LAN name can be set while the
## game runs). True when it changed (the caller renames the local player).
func refresh_default()->bool:
	if name_set:
		return false
	var _name:String = default_name()
	if _name == display_name:
		return false
	display_name = _name
	return true
