# Multiplayer connection tech: how players get connected

This is a recipe for agents. It explains how this project (Godot 4.7, GDScript) connects
players for co-op: plain host/join over ENet, a self-hosted WireGuard virtual LAN for internet play
with no port forwarding, a headless dedicated server with a private control channel, and an in-game
dialog that drives all of it. Each layer is written as **problem → solution → code → gotchas**, so it
can be rebuilt in another Godot project without reading this repo's history.

Scope: **making and managing the connection**. Gameplay sync (player copies, enemies, loot, fights,
join tiers) lives in `addons/top_down/design_document/multiplayer.md` and is not repeated here. The
user-facing manual for the scripts is `tools/vlan/README.md`.

---

## 0. The picture

```
 ┌───────────── Player PC (guest) ─────────────┐          ┌──────────── Host PC ─────────────────────────────┐
 │ Godot game                                  │          │ Godot game (Host button)      OR                 │
 │  Net autoload ── ENet client ──┐            │          │ headless Godot  -- --server  (DedicatedServer)   │
 │  CoopDialog → VlanTool (thread)│            │          │  Net autoload ── ENet server UDP 24565           │
 │            → ServerProcess     │            │          │  ServerConsole ── TCP 127.0.0.1:<free>  ◄── token│
 └────────────────────────────────┼────────────┘          └──────────────────────────────▲─────────────────▲─┘
                                  │                                                     │                 │
       one of:                    │                                                     │                 │
       a) 127.0.0.1 / LAN IP ─────┤                                                     │       game's ServerProcess
       b) public IP (UPnP or forwarded port) ───────────────────────────────────────────┤       or tools/server.sh|.cmd
       c) zs-vlan: WireGuard 10.77.0.x ──── UDP 51820, hole-punched, IPv6 first ────────┘       (same control file)
          guest 10.77.0.N  ────────────────────────────────────────────►  host 10.77.0.1
```

| Layer | What it solves | Main files |
|---|---|---|
| 1. Session and transport | host/join, handshake, roster, security | `game/scripts/net/Net.gd`, `NetTransport.gd`, `ENetTransport.gd`, `GuestSandbox.gd` |
| 2. zs-vlan | internet play with no port forwarding, no accounts, no relay servers | `tools/vlan/vlan_auto.sh`, `lib.sh`, `vlan_auto.ps1`, `vlan_auto.cmd` |
| 3. Dedicated server | a headless host that outlives the game, plus a launcher menu | `game/scripts/net/DedicatedServer.gd`, `ServerConsole.gd`, `tools/server.sh`, `server.ps1`, `server.cmd` |
| 4. In-game control | the same, without a terminal: VLAN and server from the Main Menu | `game/scripts/net/VlanTool.gd`, `ServerProcess.gd`, `game/scripts/ui/CoopDialog.gd`, `CoopVlanTab.gd`, `CoopServerTab.gd`, `CoopTitleButton.gd`, `QuitPrompt.gd` |

Constants used everywhere:

| | value | where |
|---|---|---|
| game port (UDP) | `24565` | `Net.DEFAULT_PORT`, `lib.sh GAME_PORT`, `ServerProcess.DEFAULTS` |
| WireGuard port (UDP) | `51820` (`VLAN_PORT`) | `lib.sh PORT`, `vlan_auto.ps1` |
| VLAN subnet | `10.77.0.0/24`, host `.1`, guests `.2–.254` (max 7) | `ENetTransport.VLAN_PREFIX`, `lib.sh NET`, `MAX_GUESTS` |
| max players | 8, the dedicated server's hidden player not counted | `PlayerRegistry.MAX_PLAYERS` |
| name length | 24 | `Net.MAX_NAME_LENGTH`, `lib.sh NAME_MAX` |

---

## 1. Session and transport (`Net` autoload)

### Problem
Host-authoritative co-op where gameplay code doesn't care whether it's offline, hosting or joined,
and where a stranger's client can't crash or cheat the host through RPC arguments.

### Solution
- **One autoload, `Net`**, with a state: `OFFLINE, HOSTING, CONNECTING, JOINED, GHOST`.
- **Offline is still multiplayer:** the default `OfflineMultiplayerPeer` makes this machine the
  authority, so gameplay checks `Net.is_authority()` and runs the same in single player.
- **A transport interface** (`NetTransport`) hides how peers reach each other. Gameplay only ever sees
  the `MultiplayerPeer`. Today that's `ENetTransport` (direct IP); a Steam transport can slot in later.
- **An app-level handshake** on top of ENet's connect: `_hello` → `_welcome` or `_rejected`.
- **Security:** `allow_object_decoding = false`, guests send only plain values, and every
  `any_peer` RPC checks its sender and arguments on the host.

### Code

The transport interface (`NetTransport.gd`, an `@abstract` RefCounted):

```gdscript
@abstract func create_host(port:int, max_clients:int)->MultiplayerPeer   # max_clients excludes the host
@abstract func create_client(address:String, port:int)->MultiplayerPeer
func share_addresses(_port:int)->Array: return []          # [{label, address}], may block: call on a thread
func tune_peer(_peer:MultiplayerPeer, _peer_id:int)->void: pass   # called on every peer_connected
func close()->void: pass                                   # undo port mappings
```

ENet (`ENetTransport.gd`): three channels (0 reliable RPCs, 1 unreliable snapshots, 2 link probes).

```gdscript
const CHANNELS:int = 3
func create_host(port:int, max_clients:int)->MultiplayerPeer:
	var _peer := ENetMultiplayerPeer.new()
	if _peer.create_server(port, max_clients, CHANNELS) != OK: return null
	return _peer

## ENet's packet throttle drops unreliable packets at random once it decides the link is congested,
## and frame-timing jitter alone convinces it. Small steady traffic: send everything.
func tune_peer(peer:MultiplayerPeer, peer_id:int)->void:
	var _packet:ENetPacketPeer = (peer as ENetMultiplayerPeer).get_peer(peer_id)
	if _packet != null:
		_packet.throttle_configure(5000, 32, 0)   # ENet's interval/scale defaults, deceleration 0
```

> **Gotcha (measured):** with ENet's default throttle about 50% of unreliable snapshots were dropped
> *even on loopback*. Call `tune_peer` on both sides: the host in `peer_connected`, the guest in
> `connected_to_server` (peer id 1).

Host and join (`Net.gd`, trimmed):

```gdscript
func host(at_port:int = DEFAULT_PORT)->Error:
	var _peer := transport.create_host(at_port, max_players - 1)
	if _peer == null: return ERR_CANT_CREATE
	multiplayer.multiplayer_peer = _peer
	_set_state(State.HOSTING)
	_lookup_share_addresses()          # UPnP + LAN list on a Thread, result via call_deferred
	return OK

func join(address:String)->Error:      # "host" or "host:port"
	var _target := parse_address(address)            # rfind(":") so "ip:port" works; default port otherwise
	multiplayer.multiplayer_peer = transport.create_client(_target.host, _target.port)
	_connect_time_left = CONNECT_TIMEOUT   # 8 s, counted down in _process
	_set_state(State.CONNECTING)
	return OK
```

Handshake:

```gdscript
# guest, on connected_to_server
_hello.rpc_id(1, {
	"protocol": PROTOCOL_VERSION,        # bump on any RPC/message layout change
	"game_version": ProjectSettings "application/config/version",
	"profile_id": ...,                   # random id per install (PlayerProfile, user://Profile.tres)
	"name": ...,
	"machine": GuestSandbox.machine_id(),      # sha256(OS.get_unique_id() + salt)
	"data_dir": GuestSandbox.data_dir_id(),    # sha256(save folder + salt)
	"shell": ...,                              # game-specific
})

@rpc("any_peer", "call_remote", "reliable")
func _hello(info:Dictionary)->void:
	if !is_host(): return
	var _peer := multiplayer.get_remote_sender_id()
	if !_pending_hello.has(_peer): return        # only once, only from a fresh peer
	_pending_hello.erase(_peer)
	var _reason := _check_hello(info)             # version+protocol, accepting, profile id 8..64 chars, free slot
	if !_reason.is_empty():
		_rejected.rpc_id(_peer, _reason)
		_drop_peer_later(_peer)                   # REJECT_GRACE 1 s so the reason arrives first
		return
	# ... build the PlayerState, unique name, then:
	_welcome.rpc_id(_peer, _slot, _roster(), _fresh, session_id)
	_broadcast_roster()                           # _roster_update to every guest

@rpc("authority", "call_remote", "reliable") func _welcome(slot:int, roster:Array, fresh:bool, session:String)
@rpc("authority", "call_remote", "reliable") func _roster_update(roster:Array)
@rpc("authority", "call_remote", "reliable") func _rejected(reason:String)
```

Host-side rules worth copying:
- **Hello timeout:** `peer_connected` puts the peer in `_pending_hello` with 5 s (`HELLO_TIMEOUT`). `_process`
  counts down and `disconnect_peer`s anyone silent.
- **Lobby gate:** `Net.accepting` is true only while the host is in a joinable place (here, the home
  base). A join elsewhere is rejected with a reason, not left hanging.
- **Unique names:** `Net.unique_name(name, taken)` turns a taken name (any case) into `Name#2`, `#3`…
  within 24 characters. The VLAN scripts use the same rule (`unique_name` in `lib.sh`). The guest
  adopts the roster's name and gets its own back on leaving.
- **A second copy of the game on the same PC** (`GuestSandbox`): when the peer address is local and both
  `machine` and `data_dir` match the host's, the guest becomes a blank guest (`fresh=true`). It locks
  saving (`SaveableResource.persist_locked`) because the two copies share `user://`.
- **Guests dropping mid-run** keep their run data on the host (`RunSession.waiting_guests[profile_id]`),
  so a rejoin restores it. Kicks (`Net.kick`) send `_rejected(reason)`, then disconnect after the grace.
- **Failure hints:** a join to `10.77.0.x` that times out appends "Is the host's game running? A Windows
  host may need: vlan_auto.cmd firewall" (`Net._unreachable`). That's the most common real failure.

Addresses to share (`ENetTransport.share_addresses`, run on a thread), best first:
1. the VLAN address, found **by IP prefix `10.77.0.`, not by interface name** (Windows names adapters
   its own way);
2. the public address if UPnP mapped the port (`UPNP.discover(2000, 2)`, `add_port_mapping(port, port, "...", "UDP")`,
   removed again in `close()`);
3. LAN IPv4s of real network cards. Skip loopback, link-local, `10.77.0.*` and virtual interfaces by
   prefix: `lo docker br- veth virbr vmnet vboxnet tun tap wg tailscale zt cni flannel podman lxc lxd vethernet`;
4. `127.0.0.1` (same computer).

---

## 2. zs-vlan: internet play without port forwarding

### Problem
Most players can't or won't forward ports, many are behind CGNAT on IPv4, and we don't want to run
or pay for relay servers or accounts.

### Solution
A **direct WireGuard tunnel** between the host and each guest, set up by one script per OS
(`vlan_auto`). Codes are exchanged in chat once. Both ends know each other's public endpoint and
send at the same time with `PersistentKeepalive = 25`, so each router sees outgoing traffic and lets
the other side's packets in (**UDP hole punching**). The game then just joins `10.77.0.1:24565`
as if on a LAN.

- **IPv6 first:** used when both sides have a public IPv6 (no NAT, nearly always works).
  `my_v6` = the kernel's source address toward `2606:4700:4700::1111`, skipping `fe80/fc/fd`. No lookup.
- **IPv4 fallback:** `curl -s4 https://api.ipify.org` (overridable: `VLAN_IPV4=addr|none`). It only works
  when both routers keep the UDP source port unchanged. It never works through CGNAT.
- **Topology is a star:** guests reach only the host (`AllowedIPs = 10.77.0.1/32` on guests). The game or
  dedicated server must run on the VLAN host.
- **What can't work:** no IPv6 on one side combined with a strict or CGNAT IPv4 router. These players
  need a relay (the planned Steam transport, or any TURN-like relay).

### The code exchange (one invite for everyone)

Codes are `<prefix>.<base64 of space-separated fields>`. They hold only public keys, addresses and a name,
so they're safe for chat. The name is the last field and may hold spaces.

| code | fields | made by |
|---|---|---|
| invite `zsi2.` | `host_pubkey wg_port slot host_v6 host_v4 host_name`; `slot=0` means "open invite: the guest picks its address"; `-` = no address | `enc zsi2 "$hpub $PORT 0 $v6 $v4 $me"` |
| reply `zsr2.` | `guest_slot guest_pubkey wg_port guest_v6 guest_v4 guest_name` | `enc zsr2 "$slot $pub $PORT $v6 $v4 $me"` |

Flow:
1. **Host** `vlan_auto host`: generates a key, creates the interface at `10.77.0.1/24` listening on 51820,
   and prints the invite (one for all guests).
2. **Guest** `vlan_auto <invite>`: picks a random slot 2–254 (kept for rejoins), generates its key, sets up
   the tunnel to the host's endpoint, and prints its reply.
3. **Host** `vlan_auto <reply>`: adds a `[Peer]` for that guest, with a unique name (`Name#2`), then waits up
   to 60 s (20 s with `--machine`) for a ping. A slot already taken by a different key gives exit 3 "ask
   them to run `vlan_auto newaddress`"; the same key at a new slot moves.
4. Both sides are now online. The guest joins the game at `10.77.0.1`.

Keys without wireguard-tools on Linux (openssl X25519, raw 32 bytes, base64):

```bash
genpriv() { openssl genpkey -algorithm X25519 -outform DER | tail -c 32 | base64; }
pubkey()  { base64 -d <<<"$1" | cat <(printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x6e\x04\x22\x04\x20') - \
            | openssl pkey -inform DER -pubout -outform DER | tail -c 32 | base64; }
```

(Windows uses `wireguard.exe`'s bundled `wg pubkey`.)

WireGuard configs it writes:

```ini
# host
[Interface]
PrivateKey = <host key>
Address = 10.77.0.1/24
ListenPort = 51820
[Peer]                              # one per guest
PublicKey = <guest pub>
AllowedIPs = 10.77.0.<slot>/32
Endpoint = [<guest v6>]:51820       # or <guest v4>:51820 when either side has no IPv6
PersistentKeepalive = 25

# guest
[Interface]
PrivateKey = <guest key>
Address = 10.77.0.<slot>/24
ListenPort = 51820
[Peer]
PublicKey = <host pub>
AllowedIPs = 10.77.0.1/32
Endpoint = [<host v6>]:51820
PersistentKeepalive = 25
```

Endpoint choice (`pick_ep`): `[v6]:port` if both the peer and this PC have IPv6, else `v4:port`, else
fail with exit 3 "no usable address".

### Applying it per OS

**Linux (NetworkManager, no packages to install):**
```bash
nmcli connection import type wireguard file "$STATE/zsvlan.conf"   # NM names the connection after the file
rm "$STATE/zsvlan.conf"                                             # private key now in NM's root-only store
nmcli connection modify zsvlan ipv6.method disabled
nmcli connection modify zsvlan connection.autoconnect no            # never up at boot
nmcli connection up zsvlan
```
Adding a guest re-imports the full config. No sudo is needed for nmcli on a desktop session (polkit).
**ufw** is the only root step, and only if ufw is active: `allow 51820/udp` and
`allow in on zsvlan to any port 24565 proto udp`, commented `zs-vlan`. Only the rules the script added are
recorded and later removed. Root goes through `${ZS_SUDO:-sudo}`; the game sets `ZS_SUDO=pkexec` for a desktop
password prompt, and `--machine` without it uses `sudo -n`.

**Windows (official WireGuard client):**
- `winget install --id WireGuard.WireGuard -e --silent ...` if missing; `stop` uninstalls it only if
  the script installed it.
- `wireguard.exe /installtunnelservice <dir>\zsvlan.conf` → a service `WireGuardTunnel$zsvlan`, then
  `Set-Service -StartupType Manual` (never at boot).
- Firewall group `zs-vlan`: inbound UDP 51820, game UDP 24565 and ping from `10.77.0.0/24`, and one rule per
  allowed game exe (`--allow EXE`).
- **The Windows firewall gotcha (cost us a day):** the first time Godot listens, Windows asks "allow access".
  It adds Allow for the ticked profiles (Private) and a **Block** rule for the unticked ones (Public).
  Windows treats the WireGuard adapter as an unidentified **Public** network, and a Block beats an Allow. So
  guests could ping the host but never reach the game, while the host's own PC joined fine. Fix
  (`vlan_auto firewall`, also done by `host`): disable those Godot Block rules (recorded in
  `C:\ProgramData\zs-vlan-fw` and re-enabled by `stop`), and allow the Godot exe from `10.77.0.0/24` only.
- State folders are admin/SYSTEM-only (`C:\ProgramData\zs-vlan-host` / `zs-vlan`). The name file
  `C:\ProgramData\zs-vlan-name` and the last status `C:\ProgramData\zs-vlan-last` (public info) are readable
  by everyone, so `status` and the game work without admin.

### Lifecycle: nothing stays on by itself
- **Off after a reboot:** autoconnect off on Linux, service Manual on Windows.
- **Idle watchdog:** started with the tunnel. Linux uses `systemd-run --user --unit zsvlan-idle`, with a
  `setsid nohup` fallback and a `flock` lock; Windows uses a hidden PowerShell. Every 30 s it reads the
  interface's rx+tx bytes. 5 minutes (`VLAN_IDLE_MIN`) with less than 2 KB per check → tunnel down, and the
  reason is saved for `status`. **Something listening on UDP 24565 counts as activity** (`ss -Hlun` /
  `Get-NetUDPEndpoint`), so a waiting server keeps its VLAN.
- **Start again** = run `vlan_auto` (or `start`). It first compares the current public addresses with the
  ones saved when the codes were made (`$STATE/public`):
  - unchanged → the same tunnel, no new codes;
  - the host's changed → a new invite (`moved=yes`), and guests paste it;
  - a guest's changed → a new reply, and the host pastes it.
- `off` = tunnel down, everything kept. `stop` = remove everything zs-vlan made.

### The program interface (what the game and the server parse)
- `--machine`: no prompts, no clipboard, short waits, and the **last line** is `ZSVLAN key=value ...`.
  Values have no spaces; names are `%20`/`%25` escaped.
- `--name NAME`: no name prompt. `--allow EXE` (Windows): firewall rule for that exe. `--out FILE` (Windows):
  everything shown is also appended to FILE (UTF-8), done by shadowing `Write-Host` at script top.

```
ZSVLAN role=host state=up ip=10.77.0.1 name=Big%20Bob game=10.77.0.1:24565 next=open code=zsi2.… guests=3:online:Ann,4:no-reply:Cy moved=
ZSVLAN role=host state=added slot=3 name=Ann online=yes
ZSVLAN role=guest state=up ip=10.77.0.57 name=Ann host_name=Big%20Bob game=10.77.0.1:24565 host=online code=zsr2.…
ZSVLAN role=none state=down
ZSVLAN state=error exit=3
```

| exit | meaning |
|---|---|
| 0 | ok |
| 1 | usage, or a broken code |
| 2 | something this PC needs is missing (the message names the install command) |
| 3 | wrong state (not set up, or the other role) |
| 4 | timed out waiting for the other PC |
| 5 | (game side only) Windows UAC prompt declined |

`preflight` checks everything up front and prints one `problem: X -> fix` line each, then exits 2.
On Linux it checks nmcli and a running NetworkManager, kernel WireGuard (5.6+), openssl, curl, ip,
ping and flock. Distro-specific install hints come from `/etc/os-release`.

---

## 3. The dedicated server

### Problem
A host that keeps running when nobody (or not the host player) is playing, which a friend can leave
on a PC and control without a GUI, and which the game can start and stop too.

### Solution
The **same game binary**, run headless with user args after `--`:

```
godot --headless --path <project> -- --server [--port 24565] [--max-players 2..8] [--save-dir user://server]
      [--name Server] [--status SECONDS] [--control FILE] [--vlan] [--idle-kick MIN(5)] [--main first|local]
```

- `DedicatedServer.enabled()` = `OS.get_cmdline_user_args()` has `--server`. `Net._ready` then swaps the
  player scene for a **hidden server player** (no layers, invisible, no input or camera), which sits in slot 0
  marked `hidden` in the roster, so clients show no copy of it.
- `DedicatedServer.configure_early()` runs **before any save is read** and points
  `SaveableResource.save_dir` to `--save-dir`. The server never touches the player's own saves, and a
  player on the same PC isn't treated as a "second copy" (its `data_dir_id` differs).
- It skips the title, goes to the lobby scene, calls `Net.host(port)` and prints the ready line
  **`DedicatedServer [INFO]: hosting on port N - OK`**, then the join addresses (VLAN, LAN, 127.0.0.1).
  Audio is muted; `Transition.instant = true`.
- Afterwards it follows the players: their copies trigger its doors. Victory, game over, or everyone
  leaving mid-run (after a checkpoint) take it back to the lobby.
- **Idle kick** (host only): `PlayerState.idle_time` grows each frame and resets on movement or aim. Over
  the limit, the run data is parked and the player is kicked with "Idle for N minutes". Ghosts (players
  temporarily at their own base) get 3×.
- **Main player** (who wears the host's character on a server): the seat key is `profile_id|machine`.
  `--main first` gives it to the first joiner; `--main local` to the first joiner whose `machine` equals
  the server's `GuestSandbox.machine_id()`, over any address. The seat waits while its owner is away, and
  is freed when the last real player disconnects. It travels in the roster as `main`.

### Console and control channel (`ServerConsole`)
- **stdin console:** a reader thread on `OS.read_string_from_stdin`. A console blocks until Enter. **A closed
  pipe returns "" forever**, so the thread ends after 20 empty reads (`EOF_READS`).
- **Ctrl+C** kills Godot without running any shutdown code. Write checkpoints as the game goes. `stop` is
  the clean path: checkpoint, kick everyone with "The server stopped", wait half a grace, `Net.leave()`,
  quit.
- **Control channel (`--control FILE`)** lets a launcher or the game talk to a background server:

```gdscript
# server
_control = TCPServer.new()
_control.listen(0, "127.0.0.1")                       # loopback only, any free port
_token = Crypto.new().generate_random_bytes(16).hex_encode()
# FILE, in a user-only folder:
#   pid=1234\ncontrol_port=40123\ntoken=<hex>\nport=24565\nstarted=<unix>\nname=Server\n
# each frame: take connections, read until 2 "\n", check line 0 == "TOKEN <token>",
# run line 1 as a console command while _say() collects its output, send it, disconnect.
# A client older than 5 s (CONTROL_TIMEOUT) is dropped. The file is removed on a clean exit.
```

```
request:  TOKEN 3f9c…\ninfo\n
answer:   INFO room=room_H00 players=2 active=2 up=754 port=24565 max=8 idle_kick=5.0 vlan=10.77.0.1 main=local:1 hosting=1 name=My Server
          (then the server closes; "name" is last because it may hold spaces)
```

Commands: `status`, `info`, `players`, `main [<slot>|free|mode first|local]`, `kick <slot> [reason]`,
`home`, `stop`, and the VLAN ones `invite`, `add <reply>` (or a bare `zsr2.…`), `guests`, `revoke <N>`.
The VLAN commands run `vlan_auto … --machine` on a worker thread. The control reply is held until that
finishes.

### Launcher scripts (`tools/server.sh`, `server.ps1` via `server.cmd`)
A menu (start/stop/restart/status/players/follow the log/console/settings), and each item is also a
subcommand (`server.sh start`, `send kick 2`, …).
- **State folder:** `${XDG_STATE_HOME:-~/.local/state}/zs-server` or `%LOCALAPPDATA%\zs-server`,
  holding `control`, `server.log` (the previous one as `.1`), and `settings` (`key=value`: port, name,
  max_players, idle_kick, vlan, main).
- **Background start:** Linux `setsid nohup "$GODOT" --headless --path . -- --server --control "$CONTROL" … >"$LOG" 2>&1 </dev/null &`.
  Windows: a hidden window.
- **Stale control file:** if the pid in it is gone, delete it.
- **Godot lookup:** `$GODOT`, then `godot` on PATH, then `Godot_v*_linux.x86_64`/`godot`/`godot.x86_64`
  (on Windows, `Godot_v*_win64_console.exe`/`godot_console.exe` **with the plain exe of the same name beside
  it**) in the project, its parent, `tools/`, or a `Godot*` folder inside those. When nothing matches, print the
  exact names wanted and the near-misses seen. Beware Explorer's hidden extensions (`godot.exe.exe`).
- **Fresh checkout:** run an import first (`--headless --import`) so `.godot/` exists.
- **`--vlan`:** the launcher runs `vlan_auto host` **before** Godot. Any sudo or UAC prompt happens in the
  launcher, never inside the headless server. On Windows the menu re-opens itself elevated.
- **Windows log lock (bug we hit):** a `cmd /c … > server.log` redirect holds the log so readers fail. Read
  it with `FileStream(..., FileShare.ReadWrite | FileShare.Delete)`. When the game starts the server, there
  is no shell: Godot writes it via `--log-file`.

---

## 4. Driving it from the game (no terminal)

### Problem
Players shouldn't need a terminal. But `vlan_auto` takes 5–60 s, needs admin on Windows and root for
ufw on Linux, and the server has to outlive the game.

### Running vlan_auto (`VlanTool.gd`)
- **Find it:** the project's `tools/vlan`, else `tools/vlan` next to the executable (exported builds must ship
  that folder beside the exe).
- **Command:** Linux `bash vlan_auto.sh <args> --machine`; Windows `powershell -NoProfile -ExecutionPolicy Bypass -File vlan_auto.ps1 <args> --machine`.
- **Never block a frame:** `OS.execute` on a `Thread`, then `_done.call_deferred(code, output)`, which emits
  `finished(code, human_lines, result_dict)`. One command at a time (`busy()`).
- **Linux root:** if a display (`WAYLAND_DISPLAY`/`DISPLAY`) and `pkexec` exist, set `ZS_SUDO=pkexec` in the
  environment before executing. The child inherits it.
- **Windows admin, per action (UAC), with output back:** an elevated process can't be piped, so the inner
  run writes to an `--out` file. The arguments travel in an env var to avoid `-Command` quoting hell:

```gdscript
# ZS_VLAN_ARGS = -NoProfile -ExecutionPolicy Bypass -File "<dir>\vlan_auto.ps1" "host" "--name" "Bob"
#                "--allow" "<game exe>" --machine --out "<user dir>\vlan_out_123.txt"
var script := ("try { $p = Start-Process powershell -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList $env:ZS_VLAN_ARGS; "
	+ "$null = $p.Handle; $p.WaitForExit(); exit $p.ExitCode } "
	+ "catch { $e = $_.Exception; $m = $e.Message; while ($e) { if ($e.NativeErrorCode -eq 1223) { exit 5 }; $e = $e.InnerException }; "
	+ "Write-Output ('ZS_LAUNCH ' + $m); exit 6 }")
OS.execute(powershell_full_path, ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], output, true)
# then read and delete the --out file; a declined UAC prompt (Win32 error 1223) -> 5, any other launch failure -> 6
```
  - **Run a local copy:** an elevated process doesn't see `subst` or mapped drives of the user's session, so a
    game on such a drive fails before the script starts. Copy `vlan_auto.ps1` to `%LOCALAPPDATA%\zs-vlan-game`
    (only when its md5 changed), run it and put `--out` there; resolve the exe passed to `--allow` through `subst`.
  - **Say why:** a script-level `trap` writes any unhandled error (message and line) to `--out` with a
    `ZSVLAN state=error` line. A nonzero exit with an empty `--out` means the admin window never ran the script.
  - **Fallback:** "Open in a window" runs the same command with `OS.create_process(powershell, [-File, script, …], true)`
    (a visible console, no `--machine`). The script elevates itself into a `-NoExit` admin window, and the page's
    `status` poll (every 4 s for 5 min) picks up the result.
  - `$null = $p.Handle` before `WaitForExit()` is needed, or `ExitCode` comes back empty.
  - `WaitForExit` waits for vlan_auto itself, not for the idle watchdog it leaves running.
  - `status` needs no admin. The admin check sits below the read-only dispatch, and status reads the
    service state plus `zs-vlan-last`.

### Starting the server (`ServerProcess.gd`)
- **Same folder and files as the launcher scripts**, so each sees a server the other started
  (`ZS_SERVER_DIR` overrides it, for tests).
- **Arguments:** `OS.get_executable_path()` with `--headless`, `--path <project>` unless
  `OS.has_feature("template")`, `--log-file <log>` on Windows, then
  `-- --server --control <file> --port --name --max-players --idle-kick --main local [--vlan] [--save-dir]`.
- **Spawn:**
  - Windows: `OS.create_process(exe, args, false)`. The child survives the game.
  - Linux: `OS.create_process("/bin/sh", ["-c", 'log=$1; shift; exec "$@" >"$log" 2>&1 </dev/null', "sh", log, exe, …])`.
    Because of `exec`, the returned pid **is** the server. Godot already starts children in their own session, so
    **don't add `setsid`**: it forks, and the pid you hold would be setsid's, which ends at once.
- **Ready:** poll every 0.5 s for up to 45 s: the control file appears, then `info` answers `hosting=1`. If the
  process dies, show the log tail. If the log's `hosting on port` line isn't `- OK`, kill it and report
  "couldn't open its port".
- **Alive:** check the pid from the control file. On Linux use `/proc/<pid>`; for our own child,
  `OS.is_process_running`. On Windows, a server the scripts started can't be checked cheaply: trust the file,
  and a dead one just won't answer.
- **Client side of the control channel:** `StreamPeerTCP` to `127.0.0.1:control_port`, polled with `await process_frame`
  (2 s to connect, 8 s for the answer), then send `TOKEN t\n<cmd>\n` and read until the server closes.
- **Stop:** send `stop`, then wait up to 15 s for the control file **and** the process to be gone.
  `stop_now()` = `OS.kill` (only for a server that never came up).
- **Joining your own server:** after a successful start, join `127.0.0.1[:port]`. Because the game passes
  `--main local`, this PC's player gets the main seat.

### UI wiring
- `CoopDialog.open_layer()`: one shared opener (a CanvasLayer, one at a time). The in-world terminal and the
  **Main Menu's Co-op button** (`CoopTitleButton`) both use it. The title's other buttons lose focus while
  it's open.
- Pages (a left rail over a `TabContainer` with `tabs_visible = false`; `CoopStyle` gives every button kind a
  visible box, because this game's theme draws none): **Play / Session**, plus **VLAN** (`CoopVlanTab`: host/join/paste/add/remove/turn off/start
  again/remove all; `status` is polled every 15 s while shown) and **Server** (`CoopServerTab`: settings, Start
  and join, Join it, Stop, Log; `info` is polled every 3 s while shown).
- **Hosting from the title:** this game ends a host's session when it arrives at the title. So Host from the
  title calls `NetPlayers.mark_scene_seen()`, then changes scene to the lobby (home base). A join from the
  title just follows the host's room broadcast.
- **Quit prompt** (`QuitPrompt.request(quit)`, from window close and the title's Quit). If
  `ServerProcess.alive()` or this PC has a `10.77.0.x` address, it asks: **Stop all** (`ServerProcess.stop()`,
  then `vlan_auto off`, which on Windows means a UAC prompt), **Keep running**, or **Cancel**. Otherwise it quits
  at once. A headless server never asks.

---

## 5. Porting this to another Godot project

**Reusable almost as-is:**
- `NetTransport.gd`, `ENetTransport.gd` (rename the UPnP description and the VLAN constants);
- the `Net.gd` session skeleton: states, host/join, the handshake, hello timeout, kick and grace,
  `parse_address`, `unique_name`, `_secure`;
- `GuestSandbox.machine_id()`/`data_dir_id()`/`is_local_address()`;
- the whole of `tools/vlan/`;
- `ServerConsole`'s control channel and stdin reader, `ServerProcess`, `VlanTool`, `QuitPrompt`;
- `tools/server.sh`, `server.ps1`, `server.cmd`.

**Game-specific, so replace:**
- the lobby rule (`Net.accepting` = "in the home base");
- the hidden server player and `ServerAnchor`, which keeps it on the party leader;
- join tiers (`GuestTier`), skins and the "main player = plumber";
- `RunSession`/`PlayerState`, waiting guests, and checkpoints;
- `DedicatedServer`'s scene list (home, victory, game over).

**Rename, or two games on one PC will collide:**

| thing | here | where |
|---|---|---|
| game port | 24565 | `Net.DEFAULT_PORT`, `lib.sh GAME_PORT`, ps1 `$GamePort`, `ServerProcess.DEFAULTS` |
| VLAN subnet | 10.77.0.0/24 | `ENetTransport.VLAN_PREFIX/VLAN_HOST`, `lib.sh NET`, ps1 |
| WireGuard interface / NM connection / Windows service | `zsvlan` / `WireGuardTunnel$zsvlan` | `lib.sh NAME`, ps1 `$Name` |
| WireGuard port | 51820 | `VLAN_PORT` |
| code prefixes | `zsi2.` / `zsr2.` | `enc`/`dec` in both scripts |
| state folders | `zs-vlan`, `zs-vlan-guest`, `zs-vlan-host`, `zs-vlan-name`, `zs-vlan-last`, `zs-vlan-fw`, `zs-server` | `lib.sh`, ps1, `ENetTransport.vlan_name_path`, `ServerProcess.state_dir` |
| firewall group/comment | `zs-vlan` | ufw comment, Windows `-Group` |
| systemd user unit | `zsvlan-idle` | `lib.sh watch_start` |
| result line tag | `ZSVLAN` | scripts, `VlanTool.parse_result` |
| machine-id salt | `zs-coop` | `GuestSandbox.SALT` |

---

## 6. Build order (replication checklist)

1. **Transport and session:** `NetTransport` + `ENetTransport` (with `tune_peer`), a `Net` autoload with states,
   `OfflineMultiplayerPeer` offline, `_secure`, the handshake, the hello timeout and the roster. Gate gameplay on
   `Net.is_authority()`.
2. **Loopback test:** a headless test that starts a second Godot process (`OS.create_process` of
   `net_client.tscn`) and joins `127.0.0.1`. Cover welcome, rejection (version, full, not accepting) and kick.
   See `game/tests/net_loopback_check.gd`.
3. **A dialog:** Host (port) / Join (address, recent hosts) / Session (roster, the address list with Copy, Leave).
4. **Dedicated server:** parse `--server` user args, `configure_early` before saves load, a hidden player, host
   on reaching the lobby, print the ready line. Test it by starting it as a process and joining
   (`dedicated_server_check`).
5. **Console and control channel:** the stdin thread with EOF handling, then `--control FILE` with token and
   loopback. Make `info` one parseable line.
6. **Launcher scripts:** the state folder, settings, background start, stale pid cleanup, Godot lookup, and
   shared-read log reading on Windows.
7. **zs-vlan scripts:** preflight, keys, invite/reply codes, the configs, per-OS apply, the firewall (including
   the Windows Block-rule fix), the idle watchdog, public-address change detection, and `--machine` + exit codes.
   Test the code flow in scratch state dirs (`XDG_STATE_HOME=…`) before touching real interfaces.
8. **In-game wrappers:** `VlanTool` (thread, pkexec, UAC + `--out`), `ServerProcess` (same folder as the scripts,
   spawn, wait_ready, request, stop), the VLAN and Server tabs, a Main Menu entry, and the quit prompt.
   See `server_process_check`.
9. **Docs:** a user README per script folder, with the exit-code table and a "what gets changed and what `stop`
   removes" section. Players and testers need it to trust scripts that change their network.

## 7. Tests here

Run any of them with:
```
<godot> --headless --path . res://game/tests/<name>.tscn
```

| test | covers |
|---|---|
| `net_loopback_check` | a real ENet session with a second process: join, reject, lobby gate, kick, blank same-PC guest, link stats |
| `dedicated_server_check` | a real `--server` process: hosting, joining, the console, the main seat (first/local, free, hand over) |
| `server_process_check` | `VlanTool` parsing plus a real read-only `status`; `ServerProcess` start in a temp `XDG_STATE_HOME`, `server.sh status` seeing it, joining as main, stop; the title's Co-op button and Host from the title |
| `coop_terminal_check` | the dialog, the input freeze, Escape |
| `coop_world_check` | two real games playing together (gameplay sync) |

Testing gotchas:
- Point state folders at temp dirs (`XDG_STATE_HOME`, `ZS_SERVER_DIR`).
- Give the test client `GuestSandbox.install_override`, so the same PC doesn't count as the same install.
- Re-register input actions in tests that skip the boot screen.

## 8. Known limits and open items
- **No relay:** the no-IPv6 + CGNAT/strict NAT case can't connect. Plan: a Steam transport behind `NetTransport`.
- **Star topology:** guests reach only the VLAN host, so the game server must run there.
- **IPv6 privacy addresses** rotate about daily, so the next start counts as an address change and asks for new codes.
- **Windows in-game path not yet verified on real hardware:** UAC elevation, `--out`, status without admin,
  `off`, `--log-file`, the server surviving `create_process`, the quit prompt. A game-started server on
  Windows isn't elevated, so its console's VLAN commands fail; use the game's VLAN tab or the launcher instead.
- **Exported builds** must ship `tools/vlan` (and the server scripts) next to the exe. There's no export preset yet.
