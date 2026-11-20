## Co-op shrines: one shared pool of uses per shrine, kept by the host.
## Lives under the Net autoload as /root/Net/Shrines.
##
## A guest asks the host for a use (by shrine key, so the host needn't be in that
## room); the host counts it, grants it back (the guest heals its own player) and
## tells every guest the new count. A guest's shrine asks for the count when it
## loads, so late arrivals see what's left.
class_name NetShrines
extends Node

const ROOM_STATE_PATH:String = "res://addons/top_down/resources/global_resources/room_state_resource.tres"
const MAX_KEY:int = 200
## A shrine has at most this many uses (guests send their own max_uses).
const MAX_USES:int = 9

## Guest: key -> callback(granted:bool) waiting on the host's answer.
var _waiting:Dictionary = {}
var _room_state:RoomStateResource

func net()->Node:
	return get_parent()

func _ready()->void:
	_room_state = load(ROOM_STATE_PATH)

func _valid_key(key:String)->bool:
	return !key.is_empty() && key.length() <= MAX_KEY && key.begins_with("res://") && !key.contains("..")

# --- Guest -------------------------------------------------------------------

## Guest: ask the host for one use; `done(granted)` runs on its answer.
func request_use(key:String, max_uses:int, done:Callable)->void:
	_waiting[key] = done
	_use_request.rpc_id(1, key, max_uses)

## Guest: ask for the current count of a shrine.
func request_sync(key:String)->void:
	_sync_request.rpc_id(1, key)

@rpc("authority", "call_remote", "reliable")
func _use_answer(key:String, granted:bool, used:int)->void:
	if !net().is_guest() || multiplayer.get_remote_sender_id() != 1 || !_valid_key(key):
		return
	_room_state.set_shrine_used(key, clampi(used, 0, MAX_USES))
	var _done:Variant = _waiting.get(key)
	_waiting.erase(key)
	if _done is Callable && (_done as Callable).is_valid():
		(_done as Callable).call(granted)

@rpc("authority", "call_remote", "reliable")
func _state(key:String, used:int)->void:
	if !net().is_guest() || multiplayer.get_remote_sender_id() != 1 || !_valid_key(key):
		return
	_room_state.set_shrine_used(key, clampi(used, 0, MAX_USES))

# --- Host --------------------------------------------------------------------

## Host: its own use was counted; tell every guest.
func broadcast(key:String)->void:
	if net().is_host():
		_state.rpc(key, _room_state.shrine_used_count(key))

func _from_player(peer:int)->bool:
	for _candidate:PlayerState in RunSession.players.all():
		if !_candidate.is_local && _candidate.peer_id == peer && !_candidate.ghost:
			return true
	return false

@rpc("any_peer", "call_remote", "reliable")
func _use_request(key:String, max_uses:int)->void:
	if !net().is_authority() || !_valid_key(key):
		return
	var _peer:int = multiplayer.get_remote_sender_id()
	if !_from_player(_peer) || !net().home._take_token(_peer):
		return
	var _used:int = _room_state.shrine_used_count(key)
	var _granted:bool = _used < clampi(max_uses, 1, MAX_USES)
	if _granted:
		_used += 1
		_room_state.set_shrine_used(key, _used)
	_use_answer.rpc_id(_peer, key, _granted, _used)
	if _granted:
		broadcast(key)

@rpc("any_peer", "call_remote", "reliable")
func _sync_request(key:String)->void:
	if !net().is_authority() || !_valid_key(key):
		return
	var _peer:int = multiplayer.get_remote_sender_id()
	if !_from_player(_peer) || !net().home._take_token(_peer):
		return
	_state.rpc_id(_peer, key, _room_state.shrine_used_count(key))
