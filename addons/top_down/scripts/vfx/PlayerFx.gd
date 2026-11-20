## Co-op: visual effects a player node plays and its copies on other machines
## replay (pickup blink, hole fall, ...). NetPlayers sets send_hook.
## A node on the player scene that wants replays has `fx_kind:StringName` and
## `play_remote_fx(args:Array)`.
class_name PlayerFx

## (kind:StringName, args:Array) -> sent to the other machines
static var send_hook:Callable

static func send(kind:StringName, args:Array)->void:
	if send_hook.is_valid():
		send_hook.call(kind, args)

## True on a teammate's copy (RemotePlayer puppet).
static func is_remote(node:Node)->bool:
	var _owner:Node = node.owner if node.owner != null else node.get_parent()
	return _owner != null && _owner.is_in_group(&"remote_player")

## Replays `kind` on the copy `body` (its direct child nodes with that fx_kind).
static func dispatch(body:Node, kind:StringName, args:Array)->void:
	for _child:Node in body.get_children():
		if _child.has_method(&"play_remote_fx") && _child.get(&"fx_kind") == kind:
			_child.play_remote_fx(args)
