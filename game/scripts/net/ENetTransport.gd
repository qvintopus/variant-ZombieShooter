## Direct IP over ENet. The host is reached at ip:port; behind a router that needs
## a forwarded UDP port, which share_addresses() tries to map with UPnP (LanPartyAddresses).
class_name ENetTransport
extends NetTransport

## Channels: 0 reliable control/RPC, 1 unreliable snapshots, 2 link probes (NetStats).
const CHANNELS:int = 3
## ENet's defaults (ENET_PEER_PACKET_THROTTLE_INTERVAL / _SCALE).
const THROTTLE_INTERVAL_MS:int = 5000
const THROTTLE_SCALE:int = 32

var _upnp_mapped:UPNP
var _mapped_port:int = -1

func create_host(port:int, max_clients:int)->MultiplayerPeer:
	var _peer:ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if _peer.create_server(port, max_clients, CHANNELS) != OK:
		return null
	return _peer

func create_client(address:String, port:int)->MultiplayerPeer:
	var _peer:ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if _peer.create_client(address, port, CHANNELS) != OK:
		return null
	return _peer

## The virtual LAN, the public address when UPnP mapping works, the LAN, this PC
## (LanPartyAddresses). Blocking (UPnP discovery takes seconds): run it on a thread.
func share_addresses(port:int)->Array:
	var _upnp:Array = []
	var _list:Array = LanPartyAddresses.share_list(port, _upnp)
	if !_upnp.is_empty():
		_upnp_mapped = _upnp[0]
		_mapped_port = port
	return _list

## ENet's packet throttle drops unreliable packets (snapshots, probes) at random
## once it decides the link is congested, and it decides that from round trip
## swings frame timing alone causes. Our traffic is small and steady: send it all.
func tune_peer(peer:MultiplayerPeer, peer_id:int)->void:
	if !(peer is ENetMultiplayerPeer):
		return
	var _packet:ENetPacketPeer = (peer as ENetMultiplayerPeer).get_peer(peer_id)
	if _packet != null:
		# full throttle from the start and never slowed down
		_packet.throttle_configure(THROTTLE_INTERVAL_MS, THROTTLE_SCALE, 0)

func close()->void:
	LanPartyAddresses.close_upnp(_upnp_mapped, _mapped_port)
	_upnp_mapped = null
	_mapped_port = -1
