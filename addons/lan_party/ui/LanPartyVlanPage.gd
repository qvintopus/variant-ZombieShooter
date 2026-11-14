## The virtual LAN page: tools/vlan/vlan_auto from the game (LanPartyVlan), as numbered steps.
## - Not set up: two cards, Host for friends (Create virtual LAN) or Join a friend (paste the
##   host's invite).
## - Hosting: 1 share the invite (one for everyone), 2 add each friend's reply, 3 guests.
## - Joined: 1 send your reply, 2 wait for the host, 3 join the host's game at <vlan_net>.1.
## - Off: Start again. Always: Turn off, and Remove / Leave (press twice), which is `stop`.
## Status is asked when the page is shown and every POLL seconds while it is (no admin
## prompt on Windows); everything else asks for admin there (UAC) or root for ufw on Linux.
## On Windows a failed admin run offers "Open in a window" (LanPartyVlan.open_window): the same
## command in a PowerShell window that shows everything; the status poll picks up the result.
## The game is reached through a LanPartyHost (join, the player's name, can it join now).
class_name LanPartyVlanPage
extends ScrollContainer

const POLL:float = 15.0
## Poll sooner while a command runs in its own window.
const WINDOW_POLL:float = 4.0
## Lines of vlan_auto's own text shown after a command that failed.
const ERROR_LINES:int = 4

var host:LanPartyHost
var _tool:LanPartyVlan = LanPartyVlan.new()
## The last whole status from vlan_auto (role, state, ...), {} before the first.
var status:Dictionary = {}
var _head:HBoxContainer
var _body:VBoxContainer
var _note:VBoxContainer
var _poll_left:float
var _remove_armed:bool
## A command waiting: shown as "working..." and refreshed after.
var _working:String = ""
var _dots:float
var _working_label:Label
## The last command that failed on Windows (to run again in a window), [] when none.
var _failed_args:PackedStringArray = []
## Seconds left polling fast after "Open in a window".
var _window_left:float
## The arguments of the last command that showed "working...".
var _last_args:PackedStringArray = []

func _init(with_host:LanPartyHost = null)->void:
	host = with_host if with_host != null else LanPartyHost.new()

func _ready()->void:
	name = "VLAN"
	host.vlan_page = self
	host.session_changed.connect(func ()->void:
		if is_inside_tree() && _working.is_empty():
			_build())
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var _box:VBoxContainer = VBoxContainer.new()
	_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_box.add_theme_constant_override(&"separation", 6)
	add_child(_box)
	_head = HBoxContainer.new()
	_box.add_child(_head)
	_note = VBoxContainer.new()
	_box.add_child(_note)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 6)
	_box.add_child(_body)
	_tool.finished.connect(_on_finished)
	if !LanPartyVlan.supported():
		_body.add_child(LanPartyStyle.banner("The virtual LAN needs its scripts (addons/lan_party/tools/vlan) and Linux or Windows.", LanPartyStyle.Tone.WARN))
		return
	_build()

func _process(delta:float)->void:
	if _working_label != null && is_instance_valid(_working_label):
		_dots += delta
		_working_label.text = _working + ".".repeat(1 + int(_dots * 3.0) % 3)
	if !LanPartyVlan.supported() || !is_visible_in_tree():
		_poll_left = 0.0
		return
	_window_left -= delta
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = WINDOW_POLL if _window_left > 0.0 else POLL
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

func _player_name()->String:
	return host.player_name()

## `quiet`: a status poll, no "working..." and no message.
func _run(args:PackedStringArray, what:String, quiet:bool = false)->void:
	var _name:String = _player_name()
	if !_tool.start(args, _name if args[0] in ["host", "join"] else ""):
		if !quiet:
			_say("Busy with the last command" if _tool.busy() else "The virtual LAN isn't available here", LanPartyStyle.Tone.WARN)
		return
	if quiet:
		return
	_working = what
	_dots = 0.0
	_failed_args = []
	_say("", LanPartyStyle.Tone.INFO)
	if LanPartyVlan.needs_admin(args):
		_say("Approve the Windows admin prompt (it can be behind the game window: check the taskbar).", LanPartyStyle.Tone.WARN)
	_last_args = args
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
			_say(_what + ": " + _done_text(result), LanPartyStyle.Tone.OK)
		else:
			# its own words say best what to fix
			var _said:PackedStringArray = []
			for _line:String in lines:
				if !_line.strip_edges().is_empty():
					_said.append(_line.strip_edges())
			var _text:String = "%s: %s" % [_what, LanPartyVlan.exit_text(code)]
			if !_said.is_empty() && code != LanPartyVlan.EXIT_DECLINED:
				_text += "\n" + "\n".join(_said.slice(maxi(_said.size() - ERROR_LINES, 0)))
			_say(_text, LanPartyStyle.Tone.ERROR)
			if OS.get_name() == "Windows" && LanPartyVlan.needs_admin(_last_args):
				_failed_args = _last_args
				_note.add_child(_window_offer(_last_args, "Run it in a PowerShell window instead: it asks for admin itself and you see every step."))
		host.log_event("vlan", {"command": _what, "exit": code, "state": str(result.get("state", "")), "silent": _tool.silent})
	if !_full && code == 0 && !_what.is_empty():
		# added / removed / off: show the whole picture again
		_run(["status"], "", true)
	_build()
	host.vlan_changed.emit()

func _done_text(result:Dictionary)->String:
	match str(result.get("state", "")):
		"added":
			return "%s added as %s%s%s" % [result.get("name", "guest"), LanPartyConfig.vlan_prefix(), result.get("slot", "?"), " (online)" if result.get("online", "") == "yes" else ""]
		"removed":
			return "guest %s%s removed" % [LanPartyConfig.vlan_prefix(), result.get("slot", "?")]
		"off":
			return "turned off (Start again brings it back)"
		"up":
			return "on"
		"down":
			return "removed" if role() == "none" else "down"
	return "done"

## A message above the steps; "" clears it.
func _say(text:String, tone:int)->void:
	LanPartyStyle.clear(_note)
	if !text.is_empty():
		_note.add_child(LanPartyStyle.banner(text, tone))

## "Open in a window": the Windows fallback for `args`.
func _window_offer(args:PackedStringArray, text:String)->HBoxContainer:
	var _label:Label = LanPartyStyle.label(text, &"SmallLabel", true)
	var _b:Button = LanPartyStyle.button("Open in a window", func ()->void: _open_window(args))
	_b.name = "OpenWindow"
	return LanPartyStyle.row([_label, _b])

func _open_window(args:PackedStringArray)->void:
	if LanPartyVlan.open_window(args, _player_name() if !args.is_empty() && args[0] in ["host", "join"] else ""):
		_window_left = 300.0
		_poll_left = WINDOW_POLL
		_say("Finish in the PowerShell window (approve its admin prompt). This page updates by itself.", LanPartyStyle.Tone.INFO)
	else:
		_say("Couldn't open PowerShell. Run vlan_auto.cmd (in the game's tools\\vlan folder) yourself.", LanPartyStyle.Tone.ERROR)

## Rebuild the controls for the current status.
func _build()->void:
	LanPartyStyle.clear(_body)
	_working_label = null
	_build_head()
	if !_working.is_empty():
		_working_label = LanPartyStyle.label(_working + "...", &"HeadingLabel")
		_body.add_child(_working_label)
		_body.add_child(LanPartyStyle.label("This can take up to a minute (installing, starting the tunnel, waiting for the other PC).", &"MutedLabel", true))
		return
	if status.is_empty():
		_body.add_child(LanPartyStyle.label("Checking this PC...", &"MutedLabel"))
		return
	match role():
		"none":
			_build_none()
		"host":
			if state() == "up":
				_build_host_up()
			else:
				_build_off("Your virtual LAN is turned off. Your guests and their codes are kept.")
		"guest":
			if state() == "up":
				_build_guest_up()
			else:
				_build_off("You're in %s's virtual LAN, turned off." % status.get("host_name", "the host"))
	if OS.get_name() == "Windows" && _failed_args.is_empty() && role() == "none":
		# the guided script in a window of its own: the way through when the admin prompt
		# from the game doesn't work on this PC
		_body.add_child(_window_offer(PackedStringArray(), "Changes here ask Windows for admin rights. Trouble? Set it up step by step in a PowerShell window."))

## The line under the page: what this PC is in the virtual LAN.
func _build_head()->void:
	LanPartyStyle.clear(_head)
	_head.add_child(LanPartyStyle.label("Virtual LAN", &"HeadingLabel"))
	if status.is_empty():
		return
	match role():
		"none": _head.add_child(LanPartyStyle.chip("NOT SET UP", LanPartyStyle.Tone.MUTED))
		"host": _head.add_child(LanPartyStyle.chip("HOSTING", LanPartyStyle.Tone.WARN))
		"guest": _head.add_child(LanPartyStyle.chip("JOINED", LanPartyStyle.Tone.INFO))
	if role() != "none":
		match state():
			"up": _head.add_child(LanPartyStyle.chip("ON", LanPartyStyle.Tone.OK))
			"off": _head.add_child(LanPartyStyle.chip("OFF", LanPartyStyle.Tone.MUTED))
			_: _head.add_child(LanPartyStyle.chip("BROKEN", LanPartyStyle.Tone.ERROR))
	_head.add_child(LanPartyStyle.spacer())
	var _ip:String = str(status.get("ip", ""))
	if !_ip.is_empty() && _ip != "-":
		_head.add_child(LanPartyStyle.label("this PC " + _ip, &"MutedLabel"))

func _build_none()->void:
	_body.add_child(LanPartyStyle.label("Play with friends anywhere, without opening router ports. One PC hosts, the others join with a code.", &"MutedLabel", true))
	var _cards:HBoxContainer = HBoxContainer.new()
	_cards.add_theme_constant_override(&"separation", 6)
	_body.add_child(_cards)
	var _host:VBoxContainer = LanPartyStyle.card(_cards, "Host for friends", "You get one invite code to send to everyone.")
	_host.add_child(LanPartyStyle.vspacer())
	_host.add_child(LanPartyStyle.button("Create virtual LAN", func ()->void: _run(["host"], "Creating the virtual LAN"), LanPartyStyle.PRIMARY))
	var _invite:String = LanPartyConfig.invite_prefix() + "2."
	var _join:VBoxContainer = LanPartyStyle.card(_cards, "Join a friend", "Paste the invite (%s..) they sent you." % _invite)
	_join.add_child(LanPartyStyle.paste_row(_invite + " ...", "Join", _join_invite))

func _build_host_up()->void:
	var _guests:Array[Dictionary] = LanPartyVlan.parse_guests(str(status.get("guests", "-")))
	if status.get("moved", "") == "yes":
		_body.add_child(LanPartyStyle.banner("Your public address changed: send the invite to your guests again.", LanPartyStyle.Tone.WARN))
	# 1 the invite
	var _one:VBoxContainer = LanPartyStyle.card(_body)
	_one.add_child(LanPartyStyle.step(1, "Send this invite to your friends (the same one for everyone)", LanPartyStyle.Step.DONE if !_guests.is_empty() else LanPartyStyle.Step.ACTIVE))
	var _code:String = str(status.get("code", "-"))
	if _code != "-" && !_code.is_empty():
		_one.add_child(LanPartyStyle.copy_row(_code, func (_t:String)->void: _say("Invite copied: paste it to your friends", LanPartyStyle.Tone.OK)))
	elif status.get("light", "") != "1":
		_one.add_child(LanPartyStyle.label("All guest places are used; remove a guest for a new one.", &"MutedLabel", true))
	else:
		_one.add_child(LanPartyStyle.button("Show the invite", func ()->void: _run(["host"], "Getting the invite")))
	# 2 replies
	var _two:VBoxContainer = LanPartyStyle.card(_body)
	var _reply:String = LanPartyConfig.reply_prefix() + "2."
	_two.add_child(LanPartyStyle.step(2, "Each friend sends back a reply (%s..): add it here" % _reply, LanPartyStyle.Step.ACTIVE))
	_two.add_child(LanPartyStyle.paste_row(_reply + " ...", "Add", _add_reply))
	# 3 guests
	var _three:VBoxContainer = LanPartyStyle.card(_body)
	_three.add_child(LanPartyStyle.step(3, "Guests: they join your game at %s" % LanPartyConfig.vlan_host() if !_guests.is_empty() else "Guests: none yet",
		LanPartyStyle.Step.DONE if !_guests.is_empty() else LanPartyStyle.Step.TODO))
	for _guest:Dictionary in _guests:
		var _slot:int = _guest.slot
		var _online:bool = _guest.online
		_three.add_child(LanPartyStyle.row([
			LanPartyStyle.dot(LanPartyStyle.GREEN if _online else LanPartyStyle.MUTED),
			LanPartyStyle.label(_guest.name),
			LanPartyStyle.label("%s%d  %s" % [LanPartyConfig.vlan_prefix(), _slot, "online" if _online else "no reply"], &"MutedLabel"),
			LanPartyStyle.spacer(),
			LanPartyStyle.button("Remove", func ()->void: _run(["host", "remove", str(_slot)], "Removing %s%d" % [LanPartyConfig.vlan_prefix(), _slot]), LanPartyStyle.GHOST)]))
	_body.add_child(_actions([LanPartyStyle.button("Turn off (keeps guests)", func ()->void: _run(["off"], "Turning off"))]))

func _build_guest_up()->void:
	var _online:bool = status.get("host", "") == "online"
	var _host:String = str(status.get("host_name", "the host"))
	var _code:String = str(status.get("code", "-"))
	var _one:VBoxContainer = LanPartyStyle.card(_body)
	_one.add_child(LanPartyStyle.step(1, "Send your reply to %s" % _host, LanPartyStyle.Step.DONE if _online else LanPartyStyle.Step.ACTIVE))
	if _code != "-" && !_code.is_empty():
		_one.add_child(LanPartyStyle.copy_row(_code, func (_t:String)->void: _say("Reply copied: send it to " + _host, LanPartyStyle.Tone.OK)))
	elif status.get("light", "") == "1":
		_one.add_child(LanPartyStyle.button("Show my reply", func ()->void: _run(["start"], "Getting the reply")))
	var _two:VBoxContainer = LanPartyStyle.card(_body)
	_two.add_child(LanPartyStyle.step(2, "%s is online" % _host if _online else "Waiting for %s to add your reply..." % _host,
		LanPartyStyle.Step.DONE if _online else LanPartyStyle.Step.TODO))
	var _three:VBoxContainer = LanPartyStyle.card(_body)
	_three.add_child(LanPartyStyle.step(3, "Join the game", LanPartyStyle.Step.ACTIVE if _online else LanPartyStyle.Step.TODO))
	var _join:Button = LanPartyStyle.button("Join %s's game (%s)" % [_host, LanPartyConfig.vlan_host()], func ()->void:
		host.join(LanPartyConfig.vlan_host()), LanPartyStyle.PRIMARY)
	_join.disabled = !_online || !host.can_join()
	_three.add_child(_join)
	_body.add_child(_actions([
		LanPartyStyle.button("New address", func ()->void: _run(["newaddress"], "Picking a new address")),
		LanPartyStyle.button("Turn off", func ()->void: _run(["off"], "Turning off"))]))

func _build_off(text:String)->void:
	if state() == "down":
		text = "Its tunnel is gone. Remove it and set it up again."
	var _card:VBoxContainer = LanPartyStyle.card(_body, "", text)
	if state() != "down":
		_card.add_child(LanPartyStyle.button("Start again", func ()->void: _run(["start"], "Starting"), LanPartyStyle.PRIMARY))
	_body.add_child(_actions([]))

## The row at the bottom: `buttons`, then Remove / Leave (press twice: it drops the keys,
## a host's guests need a new invite).
func _actions(buttons:Array)->HBoxContainer:
	var _text:String = "Press again to remove" if _remove_armed else ("Remove virtual LAN" if role() == "host" else "Leave virtual LAN")
	var _remove:Button = LanPartyStyle.button(_text, func ()->void:
		if !_remove_armed:
			_remove_armed = true
			_build()
			return
		_remove_armed = false
		_run(["stop"], "Removing"), LanPartyStyle.DANGER)
	_remove.name = "Remove"
	var _row:HBoxContainer = LanPartyStyle.row(buttons)
	_row.add_child(LanPartyStyle.spacer())
	_row.add_child(_remove)
	return _row

func _join_invite(invite:String)->void:
	var _code:String = invite.strip_edges().replace(" ", "")
	if !LanPartyConfig.is_invite_code(_code):
		_say("That isn't an invite (invites start with %s2.)" % LanPartyConfig.invite_prefix(), LanPartyStyle.Tone.ERROR)
		return
	_run(["join", _code], "Joining")

func _add_reply(reply:String)->void:
	var _code:String = reply.strip_edges().replace(" ", "")
	if !LanPartyConfig.is_reply_code(_code):
		_say("That isn't a reply (replies start with %s2.)" % LanPartyConfig.reply_prefix(), LanPartyStyle.Tone.ERROR)
		return
	_run(["host", "add", _code], "Adding the guest")
