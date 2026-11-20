## Co-op shrines over real ENet: this process hosts, a net_client ("shrine") joins.
## One shared pool per shrine kept by the host: a guest syncs a count, takes a use,
## is refused once it's spent, and hears the host's own uses.
##   Godot --headless --path . res://game/tests/coop_shrine_check.tscn
extends Node

const PORT:int = 24597

var failures:int = 0
var checks:int = 0

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _ready()->void:
	var _state:RoomStateResource = load("res://addons/top_down/resources/global_resources/room_state_resource.tres")
	_state.reset_resource()
	_state.set_shrine_used("res://t.tscn:Pre", 1)
	check(Net.host(PORT) == OK, "host opens the port")
	var _client:Dictionary = _spawn_client("shrine")
	check(await _wait(func ()->bool: return RunSession.players.count() == 2, 10.0), "guest joined")
	check(await _wait(func ()->bool: return _read(_client).contains("NETCLIENT state res://t.tscn:Pre=1"), 8.0), "guest synced a shrine's count")
	check(await _wait(func ()->bool: return _read(_client).contains("NETCLIENT use2"), 8.0), "guest made two requests")
	var _log:String = _read(_client)
	check(_log.contains("NETCLIENT use1 true 1"), "first use granted")
	check(_log.contains("NETCLIENT use2 false 1"), "spent shrine refused")
	check(_state.shrine_used_count("res://t.tscn:One") == 1, "host counted the guest's use")
	# the host's own use reaches the guest
	_state.set_shrine_used("res://t.tscn:Host", 2)
	Net.shrines.broadcast("res://t.tscn:Host")
	check(await _wait(func ()->bool: return _read(_client).contains("NETCLIENT done"), 8.0), "guest heard the host's use")
	_state.reset_resource()
	Net.leave()
	await get_tree().create_timer(0.5).timeout
	OS.kill(_client.pid)
	print("coop_shrine_check: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		print(_read(_client))
	get_tree().quit(1 if failures > 0 else 0)

func _spawn_client(mode:String)->Dictionary:
	var _log:String = ProjectSettings.globalize_path("user://net_client_%s_%d.log" % [mode, Time.get_ticks_msec()])
	var _cmd:String = "'%s' --headless --path '%s' res://game/tests/net_client.tscn -- 127.0.0.1:%d %s > '%s' 2>&1" % [
		OS.get_executable_path(), ProjectSettings.globalize_path("res://"), PORT, mode, _log]
	return {"pid": OS.create_process("/bin/sh", ["-c", _cmd]), "log": _log}

func _read(client:Dictionary)->String:
	return FileAccess.get_file_as_string(client.log) if FileAccess.file_exists(client.log) else ""

func _wait(condition:Callable, seconds:float)->bool:
	var _end:int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < _end:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()
