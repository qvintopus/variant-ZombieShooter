## What the LAN Party pages need from the game. Extend it, override what your game has, and give
## the same object to both pages:
##   var host := MyLanPartyHost.new()
##   var vlan := LanPartyVlanPage.new(host)
##   var server := LanPartyServerPage.new(host)
## Emit session_changed when joining becomes possible or not (e.g. on your network state change).
class_name LanPartyHost
extends RefCounted

## The game's session changed: the pages refresh their Join / Start buttons.
signal session_changed
## The VLAN page finished a command (it's on, off, a guest was added...).
signal vlan_changed

## Set by the VLAN page itself.
var vlan_page:LanPartyVlanPage

## The player's name for the virtual LAN (vlan_auto --name); "" lets the script pick the PC's name.
func player_name()->String:
	return ""

## The game can join a session now (not already hosting or joined).
func can_join()->bool:
	return true

## Join the game at `address` ("ip" or "ip:port").
func join(_address:String)->void:
	pass

## The game's own port (the address of a server on the default port leaves it out).
func default_port()->int:
	return LanPartyConfig.game_port()

## Seats on the dedicated server, at most.
func max_players()->int:
	return LanPartyConfig.max_players()

## A playtest/analytics event, if the game keeps such a log.
func log_event(_what:String, _data:Dictionary)->void:
	pass

## The server's place (its "room" info field) in words.
func place_text(place:String)->String:
	return "starting" if place.is_empty() else place.replace("_", " ")

## Shown under the Server page.
func server_note()->String:
	return "It runs hidden in the background on this PC and keeps running when the game closes (quitting asks). You join it like a friend does."

## This PC hosts a virtual LAN that is up (the server can use it).
func vlan_hosting()->bool:
	return vlan_page != null && is_instance_valid(vlan_page) && vlan_page.hosting_up()
