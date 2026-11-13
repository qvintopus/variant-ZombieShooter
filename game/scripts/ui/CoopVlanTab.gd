## Co-op dialog, "VLAN" tab: the zs-vlan virtual LAN from the game (tools/vlan/vlan_auto via
## VlanTool). Host one (one shared invite, a reply from each guest) or join one (paste the
## host's invite, send back the reply), see who is online, turn it off or remove it.
## Status is asked when the tab is shown and every POLL seconds while it is (no admin
## prompt on Windows); everything else asks for admin there (UAC) or root for ufw on Linux.
extends ScrollContainer

const POLL:float = 15.0
## Lines of vlan_auto's own text shown after a command that failed.
const ERROR_LINES:int = 4

var dialog:CoopDialog
var _tool:VlanTool = VlanTool.new()
## The last whole status from vlan_auto (role, state, ...), {} before the first.
var status:Dictionary = {}
var _state_label:Label
var _body:VBoxContainer
var _note:Label
var _poll_left:float
var _remove_armed:bool
## A command waiting: shown as "working..." and refreshed after.
var _working:String = ""

func _ready()->void:
	name = "VLAN"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	custom_minimum_size = Vector2(0, 130)
	var _box:VBoxContainer = VBoxContainer.new()
	_box.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(_box)
	_state_label = CoopDialog.make_label("")
	_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_state_label)
	_body = VBoxContainer.new()
	_box.add_child(_body)
	_note = CoopDialog.make_label("")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_note)
	_tool.finished.connect(_on_finished)
	if !VlanTool.supported():
		_state_label.text = "The virtual LAN needs tools/vlan next to the game, on Linux or Windows."
		return
	_build()

func _process(delta:float)->void:
	if !VlanTool.supported() || !is_visible_in_tree():
		_poll_left = 0.0
		return
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = POLL
		if !_tool.busy():
			_run(["status"], "", true)

func _exit_tree()->void:
	_tool.wait()

## Role "host" / "guest" / "none"; state "up" / "off" / "down".
func role()->String:
	return str(status.get("role", "none"))

func state()->String:
	return str(status.get("state", "down"))

## Hosting a virtual LAN that is up (the dedicated server can use it).
func hosting_up()->bool:
	return role() == "host" && state() == "up"

## `quiet`: a status poll, no "working..." and no message.
func _run(args:PackedStringArray, what:String, quiet:bool = false)->void:
	var _name:String = RunSession.profile.display_name if RunSession.profile.name_set || !ENetTransport.vlan_name().is_empty() else ""
	if !_tool.start(args, _name if args[0] in ["host", "join"] else ""):
		if !quiet:
			_note.text = "Busy with the last command" if _tool.busy() else "The virtual LAN isn't available here"
		return
	if quiet:
		return
	_working = what
	_note.text = what + "..." + ("\nWindows asks for admin rights." if VlanTool.needs_admin(args) else "")
	_build()

func _on_finished(code:int, lines:PackedStringArray, result:Dictionary)->void:
	if !is_inside_tree():
		return
	var _what:String = _working
	_working = ""
	var _full:bool = str(result.get("state", "")) in ["up", "off", "down"] && result.has("role")
	if _full:
		status = result
	if !_what.is_empty():
		if code == 0:
			_note.text = _what + ": " + _done_text(result)
		else:
			# its own words say best what to fix
			var _said:PackedStringArray = []
			for _line:String in lines:
				if !_line.strip_edges().is_empty():
					_said.append(_line.strip_edges())
			_note.text = "%s: %s" % [_what, VlanTool.exit_text(code)]
			if !_said.is_empty() && code != VlanTool.EXIT_DECLINED:
				_note.text += "\n" + "\n".join(_said.slice(maxi(_said.size() - ERROR_LINES, 0)))
		PlaytestLog.event("vlan", {"command": _what, "exit": code, "state": str(result.get("state", ""))})
	if !_full && code == 0 && !_what.is_empty():
		# added / removed / off: show the whole picture again
		_run(["status"], "", true)
	_build()
	if dialog != null:
		dialog.vlan_changed()

func _done_text(result:Dictionary)->String:
	match str(result.get("state", "")):
		"added":
			return "%s added as 10.77.0.%s%s" % [result.get("name", "guest"), result.get("slot", "?"), " (online)" if result.get("online", "") == "yes" else ""]
		"removed":
			return "guest 10.77.0.%s removed" % result.get("slot", "?")
		"off":
			return "turned off (Start again brings it back)"
		"up":
			return "on"
		"down":
			return "removed" if role() == "none" else "down"
	return "done"

## Rebuild the controls for the current status.
func _build()->void:
	for _child:Node in _body.get_children():
		_child.queue_free()
	_state_label.text = _state_text()
	if !_working.is_empty():
		return
	match role():
		"none":
			_body.add_child(CoopDialog.make_button("Host a virtual LAN", func ()->void: _run(["host"], "Hosting")))
			_body.add_child(CoopDialog.make_label("Or join one: paste the host's invite"))
			var _invite:LineEdit = _code_edit("", "zsi2. ...")
			_body.add_child(_row([_invite,
				CoopDialog.make_button("Paste", func ()->void: _invite.text = DisplayServer.clipboard_get().strip_edges()),
				CoopDialog.make_button("Join", func ()->void: _join(_invite.text))]))
		"host":
			if state() == "up":
				_build_host_up()
			else:
				_body.add_child(CoopDialog.make_button("Start again", func ()->void: _run(["start"], "Starting")))
			_build_remove()
		"guest":
			if state() == "up":
				_build_guest_up()
			else:
				_body.add_child(CoopDialog.make_button("Start again", func ()->void: _run(["start"], "Starting")))
			_build_remove()

func _state_text()->String:
	if status.is_empty():
		return "Virtual LAN: checking..." if VlanTool.supported() else ""
	var _ip:String = str(status.get("ip", ""))
	match role():
		"host":
			match state():
				"up": return "Virtual LAN: you host it, this PC is %s. Friends join the game at 10.77.0.1" % _ip
				"off": return "Virtual LAN: yours (%s), turned off" % _ip
			return "Virtual LAN: yours, but its tunnel is gone. Remove it and host again."
		"guest":
			var _host:String = str(status.get("host_name", "the host"))
			match state():
				"up":
					if status.get("host", "") == "online":
						return "Virtual LAN: joined %s, this PC is %s. %s is online." % [_host, _ip, _host]
					return "Virtual LAN: joined %s as %s, waiting for the host to add your reply." % [_host, _ip]
				"off": return "Virtual LAN: joined %s (%s), turned off" % [_host, _ip]
			return "Virtual LAN: joined, but its tunnel is gone. Remove it and join again."
	return "Virtual LAN: none. Play over the internet without opening router ports."

func _build_host_up()->void:
	var _code:String = str(status.get("code", "-"))
	if _code != "-" && !_code.is_empty():
		_body.add_child(CoopDialog.make_label("Invite, the same one for every friend:"))
		_body.add_child(_row([_code_edit(_code, ""), _copy_button(_code, "invite")]))
	elif status.get("light", "") != "1":
		_body.add_child(CoopDialog.make_label("All guest places are used; remove one for a new guest."))
	else:
		_body.add_child(CoopDialog.make_button("Show the invite", func ()->void: _run(["host"], "Getting the invite")))
	if status.get("moved", "") == "yes":
		var _moved:Label = CoopDialog.make_label("Your public address changed: send the invite to your guests again.")
		_moved.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(_moved)
	_body.add_child(CoopDialog.make_label("Paste each friend's reply:"))
	var _reply:LineEdit = _code_edit("", "zsr2. ...")
	_body.add_child(_row([_reply,
		CoopDialog.make_button("Paste", func ()->void: _reply.text = DisplayServer.clipboard_get().strip_edges()),
		CoopDialog.make_button("Add", func ()->void: _add(_reply.text))]))
	var _guests:Array[Dictionary] = VlanTool.parse_guests(str(status.get("guests", "-")))
	_body.add_child(CoopDialog.make_label("Guests: none yet" if _guests.is_empty() else "Guests:"))
	for _guest:Dictionary in _guests:
		var _slot:int = _guest.slot
		var _text:Label = CoopDialog.make_label("10.77.0.%d  %s  (%s)" % [_slot, _guest.name, "online" if _guest.online else "no reply"])
		_text.size_flags_horizontal = SIZE_EXPAND_FILL
		_body.add_child(_row([_text, CoopDialog.make_button("Remove", func ()->void:
			_run(["host", "remove", str(_slot)], "Removing 10.77.0.%d" % _slot))]))
	_body.add_child(CoopDialog.make_button("Turn off (keeps guests)", func ()->void: _run(["off"], "Turning off")))

func _build_guest_up()->void:
	if status.get("host", "") == "online":
		_body.add_child(CoopDialog.make_button("Join the host's game at 10.77.0.1", func ()->void:
			if dialog != null:
				dialog.join_address(ENetTransport.VLAN_HOST)))
	var _code:String = str(status.get("code", "-"))
	if _code != "-" && !_code.is_empty():
		_body.add_child(CoopDialog.make_label("Your reply, send it to the host:" if status.get("host", "") != "online" else "Your reply (the host has it):"))
		_body.add_child(_row([_code_edit(_code, ""), _copy_button(_code, "reply")]))
	elif status.get("light", "") == "1":
		_body.add_child(CoopDialog.make_button("Show my reply", func ()->void: _run(["start"], "Getting the reply")))
	_body.add_child(_row([
		CoopDialog.make_button("New address", func ()->void: _run(["newaddress"], "Picking a new address")),
		CoopDialog.make_button("Turn off", func ()->void: _run(["off"], "Turning off"))]))

## Remove takes two presses: it drops the keys (a host's guests need a new invite).
func _build_remove()->void:
	var _text:String = "Sure? Press again to remove" if _remove_armed else ("Remove the virtual LAN" if role() == "host" else "Leave the virtual LAN")
	var _button:Button = CoopDialog.make_button(_text, func ()->void:
		if !_remove_armed:
			_remove_armed = true
			_build()
			return
		_remove_armed = false
		_run(["stop"], "Removing"))
	_body.add_child(_button)

func _join(invite:String)->void:
	var _code:String = invite.strip_edges().replace(" ", "")
	if !(_code.begins_with("zsi1.") || _code.begins_with("zsi2.")):
		_note.text = "That isn't an invite (invites start with zsi2.)"
		return
	_run(["join", _code], "Joining")

func _add(reply:String)->void:
	var _code:String = reply.strip_edges().replace(" ", "")
	if !(_code.begins_with("zsr1.") || _code.begins_with("zsr2.")):
		_note.text = "That isn't a reply (replies start with zsr2.)"
		return
	_run(["host", "add", _code], "Adding the guest")

func _code_edit(text:String, placeholder:String)->LineEdit:
	var _edit:LineEdit = CoopDialog.make_edit(text, placeholder)
	if !text.is_empty():
		_edit.editable = false
		_edit.selecting_enabled = true
	return _edit

func _copy_button(text:String, what:String)->Button:
	return CoopDialog.make_button("Copy", func ()->void:
		DisplayServer.clipboard_set(text)
		_note.text = "Copied the %s" % what)

func _row(children:Array)->HBoxContainer:
	var _row_box:HBoxContainer = HBoxContainer.new()
	for _child:Control in children:
		_row_box.add_child(_child)
	return _row_box
