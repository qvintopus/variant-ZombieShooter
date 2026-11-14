## Addresses to tell a friend: the virtual LAN's, the LAN's, and the public one through UPnP.
## The virtual LAN (tools/vlan) is <vlan_net>.0/24 from lan_party.cfg: its host is .1, guests .2-.254.
class_name LanPartyAddresses
extends RefCounted

const VIRTUAL_PREFIXES:PackedStringArray = ["lo", "docker", "br-", "veth", "virbr", "vmnet", "vboxnet", "tun", "tap", "wg", "tailscale", "zt", "cni", "flannel", "podman", "lxc", "lxd", "vethernet"]

## "10.77.0." for the game's virtual LAN.
static func vlan_prefix()->String:
	return LanPartyConfig.vlan_prefix()

## The virtual LAN host's address, where guests join the game.
static func vlan_host()->String:
	return LanPartyConfig.vlan_host()

## This PC's address on the virtual LAN, "" when it isn't in one. Found by address, not by
## interface name (Windows names the adapter its own way).
static func vlan_address()->String:
	var _prefix:String = vlan_prefix()
	for _ip:String in IP.get_local_addresses():
		if _ip.begins_with(_prefix):
			return _ip
	return ""

## An address on the virtual LAN (with or without ":port").
static func is_vlan_address(address:String)->bool:
	return address.begins_with(vlan_prefix())

## IPv4 addresses of real network cards: loopback, link-local, the virtual LAN and virtual
## interfaces (Docker, VMs, VPN tunnels) are left out, a friend can't reach those.
static func lan_addresses()->PackedStringArray:
	var _list:PackedStringArray = []
	var _vlan:String = vlan_prefix()
	for _interface:Dictionary in IP.get_local_interfaces():
		var _name:String = str(_interface.get("name", "")).to_lower()
		if is_virtual_interface(_name):
			continue
		for _ip:String in _interface.get("addresses", []):
			if _ip.contains(":") || _ip.begins_with("127.") || _ip.begins_with("169.254.") || _ip.begins_with(_vlan):
				continue
			if !_list.has(_ip):
				_list.append(_ip)
	return _list

static func is_virtual_interface(interface_name:String)->bool:
	for _prefix:String in VIRTUAL_PREFIXES:
		if interface_name.begins_with(_prefix):
			return true
	return false

## "ip" or "ip:port" when port isn't the default.
static func join_text(ip:String, port:int, default_port:int = -1)->String:
	if default_port < 0:
		default_port = LanPartyConfig.game_port()
	return ip if port == default_port else "%s:%d" % [ip, port]

## Tests point this at a file of their own ("" = where vlan_auto keeps it).
static var vlan_name_file:String = ""

## Where vlan_auto keeps this PC's name on the virtual LAN (outside its admin/private state
## folders, so the game can read it): <state>/<prefix>-vlan-name, %ProgramData% on Windows.
static func vlan_name_path()->String:
	if !vlan_name_file.is_empty():
		return vlan_name_file
	var _file:String = LanPartyConfig.vlan_brand() + "-name"
	if OS.get_name() == "Windows":
		return OS.get_environment("ProgramData").path_join(_file)
	return LanPartyConfig.state_home().path_join(_file)

## This PC's name on the virtual LAN ("" when vlan_auto never set one).
static func vlan_name()->String:
	var _path:String = vlan_name_path()
	if _path.is_empty() || !FileAccess.file_exists(_path):
		return ""
	return FileAccess.get_file_as_string(_path).strip_edges().replace("\n", " ").left(LanPartyConfig.MAX_NAME_LENGTH).strip_edges()

## Maps `port` (UDP) on the router with UPnP. Blocking (discovery takes seconds): call it from a
## thread. Returns [upnp, public address]; [null, ""] when it didn't work. Undo with close_upnp.
static func open_upnp(port:int)->Array:
	var _upnp:UPNP = UPNP.new()
	if _upnp.discover(2000, 2) != UPNP.UPNP_RESULT_SUCCESS:
		return [null, ""]
	var _gateway:UPNPDevice = _upnp.get_gateway()
	if _gateway == null || !_gateway.is_valid_gateway():
		return [null, ""]
	if _upnp.add_port_mapping(port, port, LanPartyConfig.get_value("game_title"), "UDP") != UPNP.UPNP_RESULT_SUCCESS:
		return [null, ""]
	return [_upnp, _upnp.query_external_address()]

static func close_upnp(upnp:UPNP, port:int)->void:
	if upnp != null && port > 0:
		upnp.delete_port_mapping(port, "UDP")

## Everything to share, best first, as [{"label", "address"}]. Blocking (UPnP): call from a thread.
## upnp_out gets the UPnP object when a port was mapped (pass it to close_upnp later).
static func share_list(port:int, upnp_out:Array = [])->Array:
	var _list:Array = []
	var _vlan:String = vlan_address()
	if !_vlan.is_empty():
		_list.append({"label": "Virtual LAN (%s)" % LanPartyConfig.vlan_brand(), "address": "%s:%d" % [_vlan, port]})
	var _mapped:Array = open_upnp(port)
	if _mapped[0] != null:
		upnp_out.append(_mapped[0])
		if !str(_mapped[1]).is_empty():
			_list.append({"label": "Over the internet", "address": "%s:%d" % [_mapped[1], port]})
	for _ip:String in lan_addresses():
		_list.append({"label": "Same network", "address": "%s:%d" % [_ip, port]})
	_list.append({"label": "Same computer", "address": "127.0.0.1:%d" % port})
	return _list
