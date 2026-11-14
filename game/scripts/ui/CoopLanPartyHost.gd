## The LAN Party pages (virtual LAN, dedicated server) in the Co-op dialog: what they need from
## this game. Joining goes through the dialog's Play page (CoopDialog.join_address), so a join
## from the title or a mission takes the same way as typing the address.
class_name CoopLanPartyHost
extends LanPartyHost

var dialog:CoopDialog

func _init(for_dialog:CoopDialog)->void:
	dialog = for_dialog

## The in-game name once the player picked one, or while this PC has a virtual LAN name (they match).
func player_name()->String:
	return RunSession.profile.display_name if RunSession.profile.name_set || !LanPartyAddresses.vlan_name().is_empty() else ""

func can_join()->bool:
	return Net.state == Net.State.OFFLINE

func join(address:String)->void:
	if is_instance_valid(dialog):
		dialog.join_address(address)

func default_port()->int:
	return Net.DEFAULT_PORT

func max_players()->int:
	return Net.MAX_PLAYERS

func log_event(what:String, data:Dictionary)->void:
	PlaytestLog.event(what, data)

func place_text(place:String)->String:
	return "home base" if place == "home_base" else super(place)

func server_note()->String:
	return super() + " You are its main player (the plumber)."
