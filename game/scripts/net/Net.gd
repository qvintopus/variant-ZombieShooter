## Autoload: the co-op session. Host-authoritative: the host (or later a dedicated
## server) owns the world, guests send requests. Offline the default
## OfflineMultiplayerPeer makes this machine the authority, so gameplay code checks
## Net.is_authority() and works the same in single player.
##
## Joining: guest connects -> sends _hello {protocol, game version, profile} ->
## host checks version, free slot and that it is accepting (home base lobby) ->
## _welcome {slot, roster} or _rejected {reason}. Every roster change is
## broadcast with _roster.
##
## Security: object decoding stays off, guests only send plain values, and every
## any_peer RPC checks its sender and arguments on the host.
extends Node

const MAX_PLAYERS:int = PlayerRegistry.MAX_PLAYERS
const DEFAULT_PORT:int = 24565
## Bump whenever an RPC or message layout changes.
const PROTOCOL_VERSION:int = 4
const CONNECT_TIMEOUT:float = 8.0
const HELLO_TIMEOUT:float = 5.0
const MAX_NAME_LENGTH:int = 24
const REJECT_GRACE:float = 1.0

## GHOST: a guest gone to its own home base with "I will return". The link stays
## open (a faint copy of it walks the host's home base, the rejoin portal waits
## for the host), but this machine plays offline: its own world, its own saves.
enum State {OFFLINE, HOSTING, CONNECTING, JOINED, GHOST}

signal state_changed
## Host and guests: someone joined or left (RunSession.players already updated).
signal roster_changed
## Guest: the attempt failed or the host closed the session.
signal connection_failed(reason:String)
signal session_ended(reason:String)
## Host: addresses to share ([{"label", "address"}]), once UPnP/LAN lookup is done.
signal share_addresses_ready(addresses:Array)
## Ghost: the host moved to another room (ghost_host_room).
signal ghost_status_changed

var state:State = State.OFFLINE
var transport:NetTransport = ENetTransport.new()
var port:int = DEFAULT_PORT
## Host: guests may join right now (the home base lobby opens it).
var accepting:bool = true
var share_addresses:Array = []
## Seats in the session, this machine's included (--max-players on a server).
var max_players:int = MAX_PLAYERS
## Host: a guest that does nothing for this many minutes is dropped (0 = never;
## the dedicated server sets it, --idle-kick). A ghost gets IDLE_GHOST_FACTOR
## times as long to come back from its own home base. Its run waits for it, as
## for a guest of a continued run.
var idle_kick_min:float = 0.0
const IDLE_GHOST_FACTOR:float = 3.0
## Set when started with --server (DedicatedServer).
var server:DedicatedServer
## Guest: the session runs on a dedicated server (its hidden player is slot 0).
var host_is_server:bool
## Dedicated server: who becomes the main player, who wears the host's plumber
## (--main): "first" = the first player to join, "local" = the first to join
## from the server's own PC. The seat is kept for them while they're away.
const MAIN_MODES:PackedStringArray = ["first", "local"]
var main_mode:String = "first"
## Server: the main player's PlayerState.main_key ("" = not given yet).
var main_key:String
## Ghost: the room the host is in ("" = unknown).
var ghost_host_room:String
## Guest: the host's home base has Electrician Bay (its robot printer shows).
var host_bay:bool
## Guest: the host has New Game+ unlocked (its home base NG+ stairs show).
var host_ng_plus:bool
const CAMPAIGN_PATH:String = "res://game/resources/campaign_resource.tres"
## Guest: our tier hasn't been applied yet this session.
var _tier_unset:bool = true
## Guest: set while joined (the name we came with); the host's roster may rename us (Name#2),
## and leaving puts the profile's name back.
var _name_before:String = ""
## Player sync and room following (/root/Net/Players on every peer).
var players:NetPlayers
## Enemies, loot, shots and fights (/root/Net/Entities).
var entities:NetEntities
## The host's home base contraptions as guests see them (/root/Net/Home).
var home:NetHome
## Ping and link health per peer (/root/Net/Stats).
var stats:NetStats
## Short id the host makes per session; guests get it on welcome, so the host's
## and guests' playtest logs can be matched up.
var session_id:String

## Host: peer_id -> seconds left to say hello before being dropped.
var _pending_hello:Dictionary = {}
var _connect_time_left:float
## Guest: the host address of the last join (for the failure hint).
var _join_host:String
var _share_thread:Thread

func _ready()->void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_secure(multiplayer)
	players = NetPlayers.new()
	players.name = "Players"
	add_child(players)
	entities = NetEntities.new()
	entities.name = "Entities"
	add_child(entities)
	home = NetHome.new()
	home.name = "Home"
	add_child(home)
	stats = NetStats.new()
	stats.name = "Stats"
	add_child(stats)
	if DedicatedServer.enabled():
		_start_server()

const SERVER_PLAYER_SCENE:String = "res://game/scenes/actors/server_player.tscn"
const PLAYER_INSTANCE_PATH:String = "res://addons/top_down/resources/InstanceResources/actors/player_instance_resource.tres"

## --server: the hidden server player replaces the regular one in every room.
func _start_server()->void:
	var _player_instance:InstanceResource = load(PLAYER_INSTANCE_PATH)
	_player_instance.scene_path = SERVER_PLAYER_SCENE
	_player_instance.scene = null
	server = DedicatedServer.new()
	server.name = "Server"
	add_child(server)

func is_server()->bool:
	return server != null

func _secure(api:MultiplayerAPI)->void:
	if api is SceneMultiplayer:
		(api as SceneMultiplayer).allow_object_decoding = false

func is_online()->bool:
	return state == State.HOSTING || state == State.JOINED

## This machine decides what happens in the world (offline, host or server).
func is_authority()->bool:
	return state != State.JOINED && state != State.CONNECTING

func is_host()->bool:
	return state == State.HOSTING

func is_guest()->bool:
	return state == State.JOINED

func is_ghost()->bool:
	return state == State.GHOST

## A connection is open (hosting, joined or a ghost).
func is_linked()->bool:
	return state == State.HOSTING || state == State.JOINED || state == State.GHOST

func local_peer_id()->int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1

# --- Host -------------------------------------------------------------------

func host(at_port:int = DEFAULT_PORT)->Error:
	if state != State.OFFLINE:
		return ERR_ALREADY_IN_USE
	var _peer:MultiplayerPeer = transport.create_host(at_port, max_players - 1)
	if _peer == null:
		return ERR_CANT_CREATE
	port = at_port
	multiplayer.multiplayer_peer = _peer
	var _local:PlayerState = RunSession.local_player()
	_local.peer_id = 1
	session_id = "%08x" % (randi() ^ Time.get_ticks_usec())
	_set_state(State.HOSTING)
	_lookup_share_addresses()
	roster_changed.emit()
	return OK

func _lookup_share_addresses()->void:
	share_addresses = []
	_share_thread = Thread.new()
	_share_thread.start(func ()->void:
		var _list:Array = transport.share_addresses(port)
		_publish_addresses.call_deferred(_list))

func _publish_addresses(list:Array)->void:
	if _share_thread != null:
		_share_thread.wait_to_finish()
		_share_thread = null
	if state != State.HOSTING:
		return
	share_addresses = list
	share_addresses_ready.emit(list)

func kick(slot:int, reason:String = "Kicked by host")->void:
	if !is_host():
		return
	var _state:PlayerState = RunSession.players.get_state(slot)
	if _state == null || _state.is_local:
		return
	PlaytestLog.event("net", {"kick": _state.display_name, "slot": slot, "reason": reason})
	_rejected.rpc_id(_state.peer_id, reason)
	_drop_peer_later(_state.peer_id)

## Lets the reliable _rejected reason reach the guest first; a well-behaved guest
## closes on its own, this catches the rest.
func _drop_peer_later(peer_id:int)->void:
	get_tree().create_timer(REJECT_GRACE).timeout.connect(_drop_peer.bind(peer_id))

func _drop_peer(peer_id:int)->void:
	if !is_host() || !multiplayer.get_peers().has(peer_id):
		return
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var _enet:ENetMultiplayerPeer = multiplayer.multiplayer_peer
		_enet.disconnect_peer(peer_id)

func _on_peer_connected(peer_id:int)->void:
	transport.tune_peer(multiplayer.multiplayer_peer, peer_id)
	if is_host():
		_pending_hello[peer_id] = HELLO_TIMEOUT

func _on_peer_disconnected(peer_id:int)->void:
	_pending_hello.erase(peer_id)
	for _state:PlayerState in RunSession.players.all():
		if !_state.is_local && _state.peer_id == peer_id:
			# gone mid-run (left, crashed, lost the link): its run waits for it, like a ghost's
			if is_host() && RunSession.active && (!_state.ghost || _state.parked) && _state.guest_run_data != null && !RunSession.waiting_guests.has(_state.profile_id):
				RunSession.waiting_guests[_state.profile_id] = _state.capture()
			RunSession.players.remove(_state.slot)
	if is_server() && !main_key.is_empty() && _real_players() == 0:
		# everyone has left: the next player to join is the first one again
		main_key = ""
		PlaytestLog.event("net", {"main": "free (everyone left)"})
		print("DedicatedServer [INFO]: everyone has left; the main player is the next to join")
	if is_host():
		_broadcast_roster()
	roster_changed.emit()

func _real_players()->int:
	var _count:int = 0
	for _state:PlayerState in RunSession.players.all():
		if !_state.is_local:
			_count += 1
	return _count

## Guest -> host, once, right after connecting.
@rpc("any_peer", "call_remote", "reliable")
func _hello(info:Dictionary)->void:
	if !is_host():
		return
	var _peer:int = multiplayer.get_remote_sender_id()
	if !_pending_hello.has(_peer):
		return
	_pending_hello.erase(_peer)
	var _reason:String = _check_hello(info)
	if !_reason.is_empty():
		PlaytestLog.event("net", {"rejected": _peer, "reason": _reason, "their_version": str(info.get("game_version", "")), "their_protocol": str(info.get("protocol", ""))})
		_rejected.rpc_id(_peer, _reason)
		_drop_peer_later(_peer)
		return
	var _slot:int = RunSession.players.free_slot()
	var _profile:String = str(info.profile_id)
	var _name:String = _clean_name(str(info.name))
	# A second copy of the game on this very computer: a blank guest that keeps
	# nothing (GuestSandbox). A copied save from elsewhere keeps its progress but
	# is keyed apart so the run save can tell the two back apart.
	var _fresh:bool = GuestSandbox.is_same_install(peer_address(_peer), str(info.get("machine", "")), str(info.get("data_dir", "")))
	if _fresh:
		# by slot, so a continued co-op run still hands the same seat back
		_profile = "guest-local-%d" % _slot
		_name = "Guest %d" % (_slot + 1)
	elif RunSession.players.find_profile(_profile) != null:
		_profile = "%s#%d" % [_profile, _slot]
	# a name already in the session (any case) becomes Name#2, Name#3, ...
	var _taken:Array = []
	for _state:PlayerState in RunSession.players.all():
		_taken.append(_state.display_name)
	_name = unique_name(_name, _taken)
	var _guest:PlayerState = PlayerState.create_remote(_profile, _name, _slot)
	_guest.peer_id = _peer
	# a blank copy of our own install has no shell of its own
	_guest.electrician = GuestTier.decide(bool(info.get("shell", false)) && !_fresh)
	if is_server():
		_guest.main_key = "%s|%s" % [str(info.profile_id), str(info.get("machine", ""))]
		_guest.main = _claim_main(_guest, str(info.get("machine", "")))
	RunSession.players.add(_guest)
	PlaytestLog.event("net", {"welcome": _name, "slot": _slot, "peer": _peer, "address": peer_address(_peer), "fresh": _fresh, "main": _guest.main})
	if is_server():
		print("DedicatedServer [INFO]: %s joined (slot %d, %s)%s" % [_name, _slot, peer_address(_peer), ", main player (plumber)" if _guest.main else ""])
	_welcome.rpc_id(_peer, _slot, _roster(), _fresh, session_id)
	_broadcast_roster()
	roster_changed.emit()

## Server: is this joining guest the main player? The seat goes to the first one
## main_mode allows and stays theirs (main_key) when they leave and come back.
func _claim_main(guest:PlayerState, machine:String)->bool:
	if main_key.is_empty():
		if main_mode == "local" && machine != GuestSandbox.machine_id():
			return false
		main_key = guest.main_key
		return true
	if main_key != guest.main_key:
		return false
	# a second copy of the same player (same profile and PC) doesn't get it twice
	for _state:PlayerState in RunSession.players.all():
		if _state.main:
			return false
	return true

## Server: hand the main seat to the player in this slot (-1: free it; it then
## goes to the next player to join that main_mode allows).
func set_main(slot:int)->bool:
	var _to:PlayerState = RunSession.players.get_state(slot) if slot >= 0 else null
	if slot >= 0 && (_to == null || _to.is_local || _to.hidden):
		return false
	main_key = _to.main_key if _to != null else ""
	for _state:PlayerState in RunSession.players.all():
		_state.main = _to != null && _state == _to
	_broadcast_roster()
	roster_changed.emit()
	return true

## Server: the main player in the session, null when nobody is or they're away.
func main_player()->PlayerState:
	for _state:PlayerState in RunSession.players.all():
		if _state.main:
			return _state
	return null

## Host: the guest's IP as ENet sees it ("" when unknown).
func peer_address(peer_id:int)->String:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var _packet:ENetPacketPeer = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(peer_id)
		if _packet != null:
			return _packet.get_remote_address()
	return ""

func _check_hello(info:Dictionary)->String:
	if int(info.get("protocol", -1)) != PROTOCOL_VERSION || str(info.get("game_version", "")) != _game_version():
		return "Different game version (host has %s)" % _game_version()
	if !accepting:
		return "The host isn't in the home base"
	var _id:String = str(info.get("profile_id", ""))
	if _id.length() < 8 || _id.length() > 64:
		return "Bad profile"
	if RunSession.players.free_slot() < 0 || RunSession.players.count() >= max_players:
		return "Session is full (%d players)" % (max_players - (1 if is_server() else 0))
	return ""

## Host: our campaign has New Game+ (sent to guests for the NG+ stairs).
func _ng_plus_unlocked()->bool:
	return (load(CAMPAIGN_PATH) as CampaignResource).ng_plus_unlocked

func _roster()->Array:
	var _list:Array = []
	for _state:PlayerState in RunSession.players.all():
		_list.append({"slot": _state.slot, "peer_id": _state.peer_id, "profile_id": _state.profile_id, "name": _state.display_name, "hidden": _state.hidden, "electrician": _state.electrician, "main": _state.main, "bay": _state.is_local && GuestTier.host_grants_electricians(), "ng_plus": _state.is_local && _ng_plus_unlocked()})
	return _list

func _broadcast_roster()->void:
	var _list:Array = _roster()
	for _state:PlayerState in RunSession.players.all():
		if !_state.is_local:
			_roster_update.rpc_id(_state.peer_id, _list)

# --- Guest ------------------------------------------------------------------

## address: "host" or "host:port"
func join(address:String)->Error:
	if state != State.OFFLINE:
		return ERR_ALREADY_IN_USE
	var _target:Dictionary = parse_address(address)
	if _target.is_empty():
		return ERR_INVALID_PARAMETER
	var _peer:MultiplayerPeer = transport.create_client(_target.host, _target.port)
	if _peer == null:
		return ERR_CANT_CONNECT
	port = _target.port
	_join_host = _target.host
	multiplayer.multiplayer_peer = _peer
	_connect_time_left = CONNECT_TIMEOUT
	_set_state(State.CONNECTING)
	return OK

## {"host", "port"} or {} when the text isn't an address.
static func parse_address(text:String)->Dictionary:
	var _text:String = text.strip_edges()
	if _text.is_empty() || _text.contains(" "):
		return {}
	var _host:String = _text
	var _port:int = DEFAULT_PORT
	var _colon:int = _text.rfind(":")
	if _colon > 0:
		var _port_text:String = _text.substr(_colon + 1)
		if !_port_text.is_valid_int():
			return {}
		_port = int(_port_text)
		_host = _text.substr(0, _colon)
	if _port < 1 || _port > 65535 || _host.is_empty():
		return {}
	return {"host": _host, "port": _port}

func _on_connected_to_server()->void:
	transport.tune_peer(multiplayer.multiplayer_peer, 1)
	_hello.rpc_id(1, {
		"protocol": PROTOCOL_VERSION,
		"game_version": _game_version(),
		"profile_id": RunSession.profile.profile_id,
		"name": RunSession.profile.display_name,
		"shell": GuestTier.has_shell() && GuestTier.can_print_shell(),
		"machine": GuestSandbox.machine_id(),
		"data_dir": GuestSandbox.data_dir_id(),
	})

@rpc("authority", "call_remote", "reliable")
func _welcome(slot:int, roster:Array, fresh:bool, session:String)->void:
	if state != State.CONNECTING:
		return
	session_id = session.left(16)
	var _local:PlayerState = RunSession.local_player()
	_name_before = _local.display_name
	if fresh:
		for _entry:Variant in roster:
			if _entry is Dictionary && int(_entry.get("slot", -1)) == slot:
				GuestSandbox.enter(str(_entry.get("profile_id", "")), _clean_name(str(_entry.get("name", ""))))
	RunSession.players.states.erase(RunSession.players.local_slot)
	_local.slot = slot
	_local.peer_id = local_peer_id()
	RunSession.players.local_slot = slot
	RunSession.players.add(_local)
	players.on_joined()
	_set_state(State.JOINED)
	_roster_update(roster)

@rpc("authority", "call_remote", "reliable")
func _roster_update(roster:Array)->void:
	if state != State.JOINED:
		return
	var _seen:Dictionary = {}
	for _entry:Variant in roster:
		if !(_entry is Dictionary):
			continue
		var _slot:int = int(_entry.get("slot", -1))
		if _slot < 0 || _slot >= MAX_PLAYERS:
			continue
		if int(_entry.get("slot", -1)) == 0:
			host_bay = bool(_entry.get("bay", false))
			host_ng_plus = bool(_entry.get("ng_plus", false))
		if bool(_entry.get("hidden", false)):
			# the dedicated server's own player: nobody to show
			host_is_server = true
			continue
		_seen[_slot] = true
		var _electrician:bool = bool(_entry.get("electrician", false))
		if _slot == RunSession.players.local_slot:
			# the host may have renamed us (the name was taken): show what everyone else sees
			var _given:String = _clean_name(str(_entry.get("name", "")))
			if !_name_before.is_empty() && !_given.is_empty():
				RunSession.local_player().display_name = _given
			var _main:bool = bool(_entry.get("main", false))
			var _main_changed:bool = RunSession.local_player().main != _main
			RunSession.local_player().main = _main
			if RunSession.local_player().electrician != _electrician || _main_changed || _tier_unset:
				_tier_unset = false
				GuestTier.enter(_electrician)
			continue
		var _state:PlayerState = RunSession.players.get_state(_slot)
		if _state == null:
			_state = PlayerState.create_remote(str(_entry.get("profile_id", "")), _clean_name(str(_entry.get("name", ""))), _slot)
			_state.peer_id = int(_entry.get("peer_id", 0))
			RunSession.players.add(_state)
		_state.electrician = _electrician
		_state.main = bool(_entry.get("main", false))
	for _state:PlayerState in RunSession.players.all():
		if !_state.is_local && !_seen.has(_state.slot):
			RunSession.players.remove(_state.slot)
	roster_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _rejected(reason:String)->void:
	var _was:State = state
	_close("")
	if _was == State.CONNECTING:
		connection_failed.emit(reason)
	else:
		session_ended.emit(reason)

func _on_connection_failed()->void:
	_close("")
	connection_failed.emit(_unreachable("Couldn't reach the host"))

func _on_server_disconnected()->void:
	var _was:State = state
	_close("")
	if _was == State.CONNECTING:
		connection_failed.emit("The host closed the connection")
	else:
		session_ended.emit("The host left")

# --- Both -------------------------------------------------------------------

# --- Ghost --------------------------------------------------------------------

## Guest: off to our own home base, keeping the seat ("I will return"). With
## `parked` (left mid-run) the host keeps our run state for when we're back.
func go_ghost(parked:bool)->void:
	if !is_guest():
		return
	players.send_going_ghost(parked)
	for _state:PlayerState in RunSession.players.all():
		if !_state.is_local:
			RunSession.players.remove(_state.slot)
	ghost_host_room = players.host_room()
	GuestTier.leave()
	_set_state(State.GHOST)
	roster_changed.emit()

## Ghost: back into the host's game, wherever it is now (the rejoin portal).
func return_from_ghost()->void:
	if !is_ghost():
		return
	_set_state(State.JOINED)
	GuestTier.enter(RunSession.local_player().electrician)
	players.request_return()

func leave()->void:
	if state == State.OFFLINE:
		return
	_close("You left")
	session_ended.emit("You left")

func _close(_reason:String)->void:
	if multiplayer.multiplayer_peer != null && !(multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	transport.close()
	_pending_hello.clear()
	share_addresses = []
	host_is_server = false
	RunSession.local_player().main = false
	ghost_host_room = ""
	_tier_unset = true
	host_bay = false
	host_ng_plus = false
	session_id = ""
	GuestTier.leave()
	RunSession.local_player().electrician = false
	# back to a lone local player in slot 0
	var _local:PlayerState = RunSession.local_player()
	for _state:PlayerState in RunSession.players.all():
		if !_state.is_local:
			RunSession.players.remove(_state.slot)
	RunSession.players.states.clear()
	_local.slot = 0
	_local.peer_id = 1
	RunSession.players.local_slot = 0
	RunSession.players.states[0] = _local
	if !_name_before.is_empty():
		# our own name again (it may have been changed in the dialog meanwhile)
		_local.display_name = RunSession.profile.display_name
		_name_before = ""
	_set_state(State.OFFLINE)
	roster_changed.emit()

func _process(delta:float)->void:
	if state == State.CONNECTING:
		_connect_time_left -= delta
		if _connect_time_left <= 0.0:
			_close("")
			connection_failed.emit(_unreachable("Timed out connecting"))
	if is_host() && idle_kick_min > 0.0:
		_kick_idle(delta)
	if is_host() && !_pending_hello.is_empty():
		for _peer:int in _pending_hello.keys():
			_pending_hello[_peer] -= delta
			if _pending_hello[_peer] <= 0.0:
				_pending_hello.erase(_peer)
				_drop_peer(_peer)

func _kick_idle(delta:float)->void:
	for _state:PlayerState in RunSession.players.all():
		if _state.is_local:
			continue
		_state.idle_time += delta
		var _minutes:float = idle_kick_min * (IDLE_GHOST_FACTOR if _state.ghost else 1.0)
		if _state.idle_time < _minutes * 60.0:
			continue
		_state.idle_time = -60.0   # once: the kick takes REJECT_GRACE
		if RunSession.active && (!_state.ghost || _state.parked) && _state.guest_run_data != null:
			RunSession.waiting_guests[_state.profile_id] = _state.capture()
		kick(_state.slot, ("Idle for %d minutes" % roundi(_minutes)) if _minutes >= 1.0 else ("Idle for %d seconds" % roundi(_minutes * 60.0)))

## A join over the zs-vlan virtual LAN that got no answer: say what usually causes it.
func _unreachable(reason:String)->String:
	if !_join_host.begins_with("10.77.0."):
		return reason
	return reason + ". Is the host's game running (Host, or the dedicated server)? A Windows host may need: vlan_auto.cmd firewall"

func _set_state(value:State)->void:
	if state == value:
		return
	state = value
	state_changed.emit()

func _game_version()->String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))

## name, unless one of taken already is it (any case): then Name#2, Name#3, ... within
## MAX_NAME_LENGTH. A name ending in #N counts from its base (Player#2 taken -> Player#3).
## The same rule as tools/vlan (unique_name in lib.sh).
static func unique_name(name:String, taken:Array)->String:
	var _lower:Dictionary = {}
	for _taken:Variant in taken:
		_lower[str(_taken).to_lower()] = true
	if !_lower.has(name.to_lower()):
		return name
	var _base:String = name
	var _hash:int = name.rfind("#")
	if _hash > 0 && name.substr(_hash + 1).is_valid_int():
		_base = name.left(_hash)
	var _n:int = 2
	while true:
		var _suffix:String = "#%d" % _n
		var _candidate:String = _base.left(MAX_NAME_LENGTH - _suffix.length()).strip_edges() + _suffix
		if !_lower.has(_candidate.to_lower()):
			return _candidate
		_n += 1
	return name

static func _clean_name(text:String)->String:
	var _name:String = text.strip_edges().replace("\n", " ").left(MAX_NAME_LENGTH)
	return _name if !_name.is_empty() else "Player"

func _exit_tree()->void:
	if _share_thread != null:
		_share_thread.wait_to_finish()
