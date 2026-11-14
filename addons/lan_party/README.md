# LAN Party

Online co-op for Godot 4 games without port forwarding, accounts or relay servers:

- **A virtual LAN** for friends in different places: a direct, self-hosted WireGuard tunnel between
  the host and each guest (UDP hole punching, IPv6 first). Players swap two short codes in chat,
  then join the host at a fixed address as if on a LAN. Linux (NetworkManager) and Windows (the
  official WireGuard client); one script per OS, `vlan_auto`.
- **A dedicated server**: your game itself, run headless with `-- --server`. A launcher menu
  (`server.sh` / `server.cmd`) starts it in the background, shows its status and players, follows
  its log and sends it console commands over a private, token-guarded control channel.
- **In-game pages** for both (`LanPartyVlanPage`, `LanPartyServerPage`) and a quit prompt, so
  players never need a terminal.

It doesn't do your game's networking: you keep your own `MultiplayerPeer` (ENet works as-is, the
virtual LAN is just another IP). LAN Party gets the players connected and runs the server.

The player/operator manual is [tools/vlan/README.md](tools/vlan/README.md).

## Install

1. Copy `addons/lan_party` into your project (or install it from the Asset Library). Enabling the
   plugin is optional: everything is plain `class_name` scripts.
2. Create `lan_party.cfg` **next to `project.godot`** with your game's names (keys you leave out keep
   the defaults from `addons/lan_party/lan_party.cfg`; don't edit that one, updates replace it):

   ```ini
   prefix=mygame          # folders, firewall group: mygame-vlan, mygame-server, ...
   vlan_name=mygamevlan   # WireGuard interface / NetworkManager connection / Windows service (max 15 chars)
   vlan_net=10.91.0       # pick a /24 nobody else uses; the host is .1
   game_port=27015
   code_prefix=mg         # invites mgi2.…, replies mgr2.…
   game_title=My Game
   extra_settings=        # e.g. difficulty:normal,hard  (passed to your server as --difficulty normal)
   ```

   Two games with the same names on one PC would share a tunnel and a server folder, so make them yours.
3. Exported games: add `addons/lan_party/tools/*, lan_party.cfg` to every export preset's
   **Resources > Filters to export non-resource files**. The game then copies the scripts out of the
   .pck to a local folder before running them. To ship the launcher menus too, put a copy of
   `addons/lan_party/tools` next to the executable and tell players to set `GODOT` to it.

## The virtual LAN page

```gdscript
var host := LanPartyHost.new()            # or your own subclass, see below
$Tabs.add_child(LanPartyVlanPage.new(host))
$Tabs.add_child(LanPartyServerPage.new(host))
```

`LanPartyHost` is how the pages reach your game. Override what you have:

| method | default | what for |
|---|---|---|
| `join(address)` | nothing | Join buttons ("10.91.0.1", "127.0.0.1:27015") |
| `can_join()` | `true` | false while hosting or joined: Join and Start are disabled |
| `player_name()` | `""` | the name given to `vlan_auto --name` ("" = the PC's name) |
| `default_port()`, `max_players()` | from `lan_party.cfg` | |
| `place_text(place)` | `place` with `_` as spaces | the server's `room` info in words |
| `server_note()` | a generic line | the note under the Server page |
| `log_event(what, data)` | nothing | your analytics/playtest log |

Emit `host.session_changed` when your network state changes. `host.vlan_changed` is emitted by the
VLAN page; `host.vlan_hosting()` says whether this PC hosts a virtual LAN that is up.

`LanPartyStyle` is the look (a dark card, one amber accent, every button kind visibly boxed). Set
`LanPartyStyle.base_theme_path` to your theme (for its font) and `LanPartyStyle.font_scale` for a
viewport bigger than 480x270, before the first page is built. Your own dialogs can use its builders
(`card`, `button`, `copy_row`, `paste_row`, `step`, `banner`, `chip`).

Where your game quits (window close, its Quit button):

```gdscript
func _notification(what:int)->void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		LanPartyQuitPrompt.request(func ()->void: get_tree().quit())
```

It quits at once unless a server or the virtual LAN still runs; then it asks Stop all / Keep running / Cancel.
Turn off `get_tree().auto_accept_quit` for that to work.

## The dedicated server

Extend `LanPartyServer` and add it from an autoload when the game was started as a server:

```gdscript
# autoload
func _ready()->void:
	if MyServer.enabled():               # "--server" among the user args
		add_child(MyServer.new())
```

```gdscript
class_name MyServer
extends LanPartyServer

func _server_ready()->void:              # before the console starts; port, server_name, max_players,
	console.register_command("kick", "kick <id>              drop a player", _kick)   # idle_kick_min are set
	get_tree().change_scene_to_file.call_deferred("res://lobby.tscn")

func open_lobby()->void:                 # call when the game is ready for players
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players - 1)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	report_hosting(err)                  # prints "hosting on port N - OK": the launchers wait for it

func players()->int: return multiplayer.get_peers().size()
func is_hosting()->bool: return multiplayer.multiplayer_peer is ENetMultiplayerPeer
func place()->String: return "lobby"
func info_fields()->Dictionary: return {"wave": 3}     # more "info" fields (no spaces)
func shutdown()->void:                   # "stop": save, tell the players, close; may await
	multiplayer.multiplayer_peer.close()

func _kick(words:PackedStringArray)->void:
	console.say("kicked " + words[1])
```

- `LanPartyServer.save_dir()` is `--save-dir` (`user://server` by default): point your saves there
  **before any is read**, so a server never touches the player's own saves on the same PC.
- `option("name")` reads any option; `register_option("--seed", true)` adds one of yours.
  `extra_settings` from `lan_party.cfg` are registered already.
- Built-in console commands: `help`, `info`, `stop`, and for the virtual LAN `invite`, `add <reply>`
  (or a pasted reply code), `guests`, `revoke <N>`. `console.say(text)` prints and also answers a
  control-channel request.
- The console reads stdin only in a real `--server` process. Ctrl+C ends Godot without running any
  shutdown code, so save checkpoints as the game goes; `stop` is the clean way.

From the game, `LanPartyServerProcess` starts the same server in the background (this executable,
`--headless`, its own process that outlives the game) and talks to it:

```gdscript
var settings := LanPartyServerProcess.load_settings()   # the launchers' saved settings
var pid := LanPartyServerProcess.start(settings)
var problem: String = await LanPartyServerProcess.wait_ready(pid)   # "" = hosting
var info: Dictionary = await LanPartyServerProcess.info()            # {room, players, port, ..., name}
var answer: String = await LanPartyServerProcess.request("kick 2")
await LanPartyServerProcess.stop()
```

`LanPartyServerProcess.forced_args` sets extra settings for a server started from the game
(this game passes `{"main": "local"}`).

## Other pieces

- `LanPartyVlan`: runs `vlan_auto … --machine` on a thread (`start(args, name)`, then the `finished`
  signal with exit code, human lines and the parsed result line). It handles UAC on Windows (an
  elevated PowerShell with output through a file, or `open_window()` as a fallback) and pkexec on
  Linux. `parse_result`, `parse_guests`, `exit_text` are static.
- `LanPartyAddresses`: `vlan_address()`, `vlan_host()`, `lan_addresses()`, `vlan_name()` (the PC's
  name on the virtual LAN, a good default player name), `share_list(port)` (everything to tell a
  friend, with a UPnP mapping attempt; blocking, use a thread) and `join_text(ip, port)`.
- `LanPartyConfig`: the merged settings (`get_value("game_title")`, `game_port()`, `vlan_host()`,
  `extra_settings()`, `clean_name()`).

## Tests

```
godot --headless --path . res://addons/lan_party/tests/lan_party_check.tscn
```

Settings and their override, code prefixes, result parsing, the script copy for exported games,
server options, and the console with its control channel, answered in-process. It changes nothing
on the network (the only script it runs is a read-only `vlan_auto status`).

## Limits

- Linux and Windows. The virtual LAN is a star: guests reach the host only, so the game or the
  server runs on the host's PC. No IPv6 on one side plus CGNAT or a strict NAT on the other can't
  connect without a relay.
- The Windows paths (UAC, the firewall fix, `server.ps1`) haven't been verified on real hardware yet.
- No macOS.

## License

MIT, see [LICENSE](LICENSE).
