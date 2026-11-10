# zs-vlan: a virtual LAN for co-op over the internet

A direct WireGuard tunnel between the host and each guest. It needs **no port forwarding, no accounts and no servers**, and it is free. One script per OS, `vlan_auto`, does both hosting and joining and says what to do at each step.

| | address | game |
|---|---|---|
| host | `10.77.0.1` | hosts on port `24565` |
| guests | `10.77.0.2` – `10.77.0.8` | join `10.77.0.1` |

## Quick start

| | Linux | Windows |
|---|---|---|
| run | `tools/vlan/vlan_auto.sh` | double-click `tools\vlan\vlan_auto.cmd` |

It asks **host or join**, then guides you:

| step | host | guest |
|---|---|---|
| 1 | Pick **host**. It prints an **invite** (`zsi1.…`, copied to the clipboard). Send it to the friend. | |
| 2 | | Pick **join** and paste the invite. It prints a **reply** (`zsr1.…`, copied). Send it back. |
| 3 | Paste the reply when it asks (or run `vlan_auto <reply>` later). It waits until the guest is online. | It waits for the host, then says **online** and copies `10.77.0.1`. |
| play | **Comms Terminal → Host → Open to friends** (its invite list shows the *Virtual LAN* address with Copy), or run the dedicated server. | **Comms Terminal → Join →** paste `10.77.0.1` (or press the *Virtual LAN host* button). |

Each further guest repeats steps 1–3. The host's `vlan_auto` prints the next invite every time.

Codes hold only public keys and addresses, so they are safe to send in chat. Linux and Windows PCs mix freely, either as host or as guest.

**Nothing stays on by itself.** The tunnel doesn't start when the PC boots, and it switches off after 5 minutes without a game on it (see [Off after a restart or when idle](#off-after-a-restart-or-when-idle)). The next time, just run `vlan_auto` again on each PC. It starts the same tunnel, with the same codes and slots.

Done for good: `vlan_auto stop` on each PC removes everything it made.

## Commands

The same on both OSes: `tools/vlan/vlan_auto.sh …` on Linux, `tools\vlan\vlan_auto.cmd …` on Windows.

| command | does |
|---|---|
| *(none)* | Guided: host or join, then the next step. Rerun it any time to see the status. |
| `<code>` | Paste whatever you got: an invite joins, a reply adds that guest. |
| `host` | Creates the virtual LAN, or shows it: guests online and the next invite. |
| `host add <reply>` | Adds a guest, or updates one with the same key. |
| `host remove <N>` | Removes guest `10.77.0.N`. |
| `join <invite>` | Joins and prints the reply to send back. |
| `start` | Starts the last tunnel again, with no prompts (running `vlan_auto` alone does the same and keeps guiding). |
| `status` | What this PC is, who is online, and the code to send. It never starts anything. |
| `stop` | Removes everything zs-vlan made on this PC. |
| `--machine` (with any command) | For programs: no prompts, no clipboard, short waits, and a last line `ZSVLAN key=value …`. |

Exit codes: 0 ok, 1 usage or broken code, 2 something this PC needs is missing (the message says how to fix it), 3 wrong state (not set up, or this PC already has the other role), 4 timed out waiting.

The old script names still work as aliases: `vlan_up.sh` (= `host`), `vlan_connect.sh`/`.ps1` (= `join`), `vlan_down.sh`, `vlan_disconnect.sh`/`.ps1` (= `stop`).

## Dedicated server

| | Linux | Windows |
|---|---|---|
| start | `tools/server.sh [options]` | `tools\server.cmd [options]` (double-click works too) |
| with the virtual LAN | `tools/server.sh --vlan` | `tools\server.cmd --vlan` (asks for admin) |

- **Godot:** `$GODOT`, then `godot` on the PATH, then a Godot binary next to the project folder. On Linux that's `Godot_v*_linux.x86_64`. On Windows it's `Godot_v*_win64_console.exe`, the console build from the same zip, which the server needs for its console.
- **`--vlan`:** the launcher runs `vlan_auto host` first and prints the first invite. Guests are then handled from the server's console.
- **Console:** type into the server window. `help` lists the commands.

| command | does |
|---|---|
| `status` | Room, players, hidden player. |
| `players` | Everyone connected: slot, name, state, address. |
| `kick <slot> [reason]` | Drops a player. |
| `home` | Saves the run and goes back to the home base. |
| `stop` | Saves, tells the players and quits. Ctrl+C quits at once instead; the run keeps its last checkpoint. |
| `invite` | The invite for the next VLAN guest. |
| `add <reply>` / paste a bare `zsr1.…` | Adds a VLAN guest. |
| `guests` | VLAN guests and whether they are online. |
| `revoke <N>` | Removes VLAN guest `10.77.0.N`. |

- Once hosting, the server prints where to join: the virtual LAN address, the LAN addresses, and `127.0.0.1` for a player on the same PC.
- **Options:** `--port N` (24565), `--max-players 2..8` (8), `--save-dir PATH` (`user://server`), `--name NAME`, `--status SECONDS`, `--idle-kick MIN` (5).
- **Idle players:** a player who does nothing (no moving, no aiming) for 5 minutes is dropped with "Idle for 5 minutes". A ghost (someone who went to their own home base with "I will return") gets 15 minutes to come back. A dropped player's run waits for them, so rejoining picks it up again. `--idle-kick 0` keeps everyone. `players` shows how long each one has been idle.
- **While the server runs, its virtual LAN stays on** (it's hosting, see below). Stop the server and the VLAN goes off 5 minutes later.
- Its saves are its own, so a player on the server's PC keeps their own progress.
- More detail: `addons/top_down/design_document/multiplayer.md`, *Dedicated server*.

## How it works

Both sides know each other's public address (that's why there are two codes) and send to each other at the same time, with a keepalive every 25 s. Each router sees outgoing traffic, so it lets the other side's packets back in. This is UDP hole punching.

- **IPv6 is the default.** It is used whenever both sides have a public IPv6. There is no address translation, so it works almost always.
- **IPv4 is the fallback.** It works only if both routers keep the UDP port number unchanged. It never works behind CGNAT. Finding your own public IPv4 needs one lookup at `api.ipify.org`.

If a public address changes (home IPs change sometimes, for example after a router restart), the tunnel can't connect any more. `vlan_auto` checks for this every time it starts the tunnel (see the next section) and says which code to send.

## Off after a restart or when idle

- **A restart turns it all off.** The tunnel isn't started at boot: on Linux the NM connection has autoconnect off, and on Windows the tunnel service is set to Manual. A dedicated server never starts on its own anyway.
- **Idle for 5 minutes turns it off.** While the tunnel is up, a small watchdog checks its traffic every 30 s. Once 5 minutes pass with less than 2 KB per check, it takes the tunnel down. Keepalives and status pings stay well under that, while a game sends much more even standing in the lobby. A game or dedicated server listening on UDP `24565` on that PC counts as activity, so a server waiting for players keeps its VLAN.
  - **Linux:** the watchdog is `vlan_auto.sh watch`, run as the user unit `zsvlan-idle`. Where there's no systemd user session it's a detached process instead. A desktop notification says when it turned the tunnel off.
  - **Windows:** a hidden PowerShell process.
  - **Either way:** it ends with the tunnel, and `stop` ends it too. `status` says why the tunnel is off.
- **Starting again** is just running `vlan_auto` (or `vlan_auto start`, or `tools/server.sh --vlan`) on each PC. Before it starts, it compares this PC's public address with the one in the codes you sent:

| | what happens |
|---|---|
| unchanged | The same tunnel starts. Both sides start theirs, and they find each other with no new codes. |
| **host's** changed | The host's `vlan_auto` prints a new invite for each guest, by slot. The guest pastes it (same slot and key). No new reply is needed unless the guest's address changed too. |
| **guest's** changed | The guest's `vlan_auto` prints the new reply. The host pastes it (`vlan_auto <reply>`, or `add` in the server console). |

Keys are kept until `stop`, so a rejoin keeps its slot.

## What gets changed, and what `stop` removes

**Linux** (NetworkManager):
- **Network:** an NM connection and interface named `zsvlan`. Autoconnect is off, so it stays down after a reboot until `vlan_auto` runs again. No sudo is needed for this part, since polkit lets the desktop user change NetworkManager settings.
- **Firewall:** only if ufw is active, and this step uses sudo. The rules are `allow 51820/udp` and `allow in on zsvlan to any port 24565 proto udp` (the game only), tagged with the comment `zs-vlan`. Only rules the script actually added are recorded, and only those are removed.
- **State:** `~/.local/state/zs-vlan` (host) or `~/.local/state/zs-vlan-guest` (guest), with mode 700. It holds the keys, the guests, the public address the codes were made with, and the watchdog's lock.
- **Packages:** none are installed. Keys are made with `openssl`, and NetworkManager has WireGuard built in. Anything missing is named with the install command for your distro.

**Windows** (the official WireGuard client):
- **Software:** WireGuard via winget, but only if it is missing. `stop` uninstalls it only if zs-vlan installed it.
- **Tunnel:** a service named `WireGuardTunnel$zsvlan`, with Manual start. Guests are added to a running host live, without a restart.
- **Firewall:** rules in the group `zs-vlan`: inbound UDP 51820, plus game UDP 24565 and ping from `10.77.0.0/24`.
- **State:** `C:\ProgramData\zs-vlan-host` (host) or `C:\ProgramData\zs-vlan` (guest), readable only by admins and SYSTEM.

## Settings (environment variables)

| var | default | |
|---|---|---|
| `VLAN_PORT` | `51820` | WireGuard UDP port. Use the same value on every machine. |
| `VLAN_IPV4` | auto (`api.ipify.org`) | Public IPv4 to advertise, or `none` to skip IPv4. |
| `VLAN_IDLE_MIN` | `5` | Minutes without game traffic before the tunnel goes off. `0` keeps it on until a restart. |

## Limits

- **Guests reach only the VLAN host, not each other.** With 3+ PCs, the game (or the dedicated server) must run on the VLAN host.
- **Some setups can't be reached without a relay server:** no IPv6 on one side, plus a strict or CGNAT IPv4 router on either side. The fallback for those players is a relay, such as the Steam transport planned in `addons/top_down/design_document/multiplayer.md`.
- **To check whether a machine has IPv6,** open https://test-ipv6.com.
- **Firewall rules stay** after a restart or idle-off, until `stop`. They only allow the WireGuard port and the game over the tunnel, and they do nothing while the tunnel is down. Keeping them avoids a sudo prompt on every start.
- **IPv6 privacy addresses** change about once a day, and Windows and many Linux setups use them. The next start then counts as an address change and asks for new codes.
- **Not yet:** running zs-vlan from inside the game. The plan is for the game to call `vlan_auto … --machine` itself (see `multiplayer.md`).
