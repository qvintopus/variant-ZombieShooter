# LAN Party: virtual LAN and dedicated server, the manual

This is for players and server operators. Game developers: see the addon's [README](../../README.md).

**Names in this manual are the addon's defaults** (`lanparty-vlan`, `10.88.0.x`, game port `7777`, codes `lpi2.`/`lpr2.`). A game sets its own in `lan_party.cfg` next to its `project.godot`, so in your game they may differ: for example `zs-vlan`, `10.77.0.x`, port `24565` and `zsi2.` codes. `<prefix>` below is that game's `prefix`.

## The virtual LAN

A direct WireGuard tunnel between the host and each guest. It needs **no port forwarding, no accounts and no servers**, and it's free. One script per OS, `vlan_auto`, does both hosting and joining and says what to do at each step.

| | address | game |
|---|---|---|
| host | `10.88.0.1` | hosts on the game's port |
| guests (up to 7) | each picks its own, `10.88.0.2` – `10.88.0.254` | join `10.88.0.1` |

### Quick start

**From the game** (no terminal): if the game shows the LAN Party pages, its **virtual LAN** page does all of this (see [From the game](#from-the-game)). The scripts stay the fallback.

| | Linux | Windows |
|---|---|---|
| run | `vlan_auto.sh` | double-click `vlan_auto.cmd` |

The scripts are in the game's `addons/lan_party/tools/vlan` folder (a game may also keep shortcuts in `tools/vlan`).

It asks **host or join**, then guides you. If this PC already hosted or joined before, the menu says so first and offers **c** continue that one (Enter), **j** join a different host or a new invite, **h** host instead, or **s** stop. Switching removes the old one; a pasted invite is checked before anything is removed.

| step | host | guest |
|---|---|---|
| 1 | Pick **host** and pick your name (Enter keeps the suggested one). It prints an **invite** (`lpi2.…`, copied to the clipboard). Send the same invite to every friend. | |
| 2 | | Pick **join** and paste the invite. It shows a suggested name. Type your own, or press Enter to keep it. The host sees this name. It prints a **reply** (`lpr2.…`, copied). Send it back. |
| 3 | Paste each reply as it comes in, when it asks (or run `vlan_auto <reply>` later). It waits until that guest is online. | It waits for the host, then says **online** and copies `10.88.0.1`. |
| play | Host a game, or run the dedicated server. | Join `10.88.0.1`. |

One invite serves everyone: each guest picks its own address and the reply tells the host which, so the host only pastes the replies. In the rare case two guests pick the same address, the host is told; that guest runs `vlan_auto newaddress` and sends the new reply it prints.

Codes hold only public keys, addresses and a name, so they're safe to send in chat. Linux and Windows PCs mix freely, either as host or as guest.

**Nothing stays on by itself.** The tunnel doesn't start when the PC boots, and it switches off after 5 minutes without a game on it (see [Off after a restart or when idle](#off-after-a-restart-or-when-idle)). The next time, just run `vlan_auto` again on each PC. It starts the same tunnel, with the same codes and addresses.

Done for good: `vlan_auto stop` on each PC removes everything it made.

**The tunnel is up but the game won't join?** First, the host's game must be running (hosting, or the dedicated server). If it is and the host is a **Windows** PC, its firewall is the usual cause:
- The first time Godot opens its port, Windows asks "allow access". It adds an Allow rule for the network types that are ticked (Private, by default) and a **Block** rule for the ones left unticked (Public).
- Windows counts the virtual LAN as an unidentified network, which is **Public**. A Block rule beats the virtual LAN's own game rule, so guests can ping the host but never reach the game. A player on the host PC itself still joins fine.
- **Fix:** the host runs `vlan_auto.cmd firewall`. It switches those Godot Block rules off (it doesn't delete them; `stop` switches them back on) and allows the Godot exe from `10.88.0.0/24` only. `vlan_auto host` does this too: it asks first, or with `--machine` it just does it. The dedicated server passes its Godot exes along (`--allow EXE`), so Windows never asks.

### From the game

The game's virtual LAN page drives `vlan_auto --machine`; its Server page starts the dedicated server itself.
- **Virtual LAN**, as numbered steps:
  - Not set up: **Create virtual LAN**, or paste a host's invite (**Paste**) and **Join**.
  - Hosting: 1 the invite with **Copy**, 2 a field for each friend's reply (**Paste**, **Add**), 3 the guests with online state and **Remove**; **Turn off** (keeps keys and guests).
  - Joined: 1 your reply with **Copy**, 2 waiting for the host, 3 **Join <host>'s game (10.88.0.1)** once the host answers. Also **New address** and **Turn off**.
  - Off: **Start again**. Always: **Remove** / **Leave** (press twice), which is `stop`.
  - The state is checked when the page opens and every 15 s while it's shown.
- **Server:** a dedicated server on this PC, in the background (see [Dedicated server](#dedicated-server)). Set its name, players, idle kick and "over the virtual LAN" (needs this PC to host the virtual LAN), then **Start and join**. Also **Join it**, **Stop** and **Open log**. It's the same server `server.sh` / `server.cmd` see: same folder, settings and control file.

Rights:
- **Windows:** every change shows a **UAC prompt** (WireGuard and the firewall need admin); nothing privileged stays installed. The game runs a copy of the scripts from `%LOCALAPPDATA%\<prefix>-vlan-game` (an admin process doesn't see `subst` or mapped drives, so a game on `O:` couldn't be found), and lets the real path of its exe through the firewall. If the hidden admin run fails or says nothing, the page offers **Open in a window**: the same command in a PowerShell window that asks for admin itself and keeps its window open, so you see every message; the page updates by itself when it's done. On a standard (non-admin) Windows account, the prompt needs an administrator's password. The status check needs none: it shows the role and tunnel state now, and the rest as the last admin run saved it (`C:\ProgramData\<prefix>-vlan-last`, public info only). Declining the prompt changes nothing and says so.
- **Linux:** if ufw is active, a desktop password prompt (pkexec) appears once per step; without pkexec it uses `sudo -n` and says to run `vlan_auto.sh` in a terminal once if that fails.

Quitting the game while a server or the tunnel still runs asks: **Stop all** (stops the server, then `vlan_auto off`), **Keep running**, or **Cancel**.

### Commands

The same on both OSes: `vlan_auto.sh …` on Linux, `vlan_auto.cmd …` on Windows.

| command | does |
|---|---|
| *(none)* | Guided: host or join, then the next step. Rerun it any time to see the status. |
| `<code>` | Paste whatever you got: an invite joins, a reply adds that guest. |
| `host` | Creates the virtual LAN, or shows it: guests online and the invite (the same for every guest). |
| `host add <reply>` | Adds a guest, or updates one with the same key (also when it moved to a new address). |
| `host remove <N>` | Removes guest `10.88.0.N`. |
| `join <invite>` | Joins and prints the reply to send back. |
| `newaddress` | Guest: picks another address and prints the new reply (when the host says the address is taken). |
| `name [NEW]` | Shows or changes this PC's name (see [Names](#names)). A guest then gets a new reply to send, so the host sees the change. |
| `start` | Starts the last tunnel again, with no prompts (running `vlan_auto` alone does the same and keeps guiding). |
| `status` | What this PC is, who is online, and the code to send. It never starts anything. |
| `stop` | Removes everything the virtual LAN made on this PC. |
| `off` | Takes the tunnel down but keeps everything (keys, guests, the join); `start` brings it back. |
| `firewall [EXE…]` | Windows: lets friends on the virtual LAN reach the game. It switches off Windows Firewall Block rules for Godot (see above) and allows the Godot exe (and any `EXE` given) from `10.88.0.0/24`. |
| `--allow EXE` (Windows, with any command) | Also allows that game exe from the virtual LAN when hosting. |
| `--name NAME` (with any command) | Uses that name without asking. |
| `--machine` (with any command) | For programs: no prompts, no clipboard, short waits, and a last line `LANPARTY key=value …`. On Windows `status --machine` also works without admin. |
| `--out FILE` (Windows, with any command) | Also writes everything shown into `FILE` (UTF-8): the game reads an elevated run's output from it. |

Exit codes: 0 ok, 1 usage or broken code, 2 something this PC needs is missing (the message says how to fix it), 3 wrong state (not set up, or this PC already has the other role), 4 timed out waiting. The game uses 5 for a declined UAC prompt and 6 when the admin PowerShell couldn't start.

The old script names still work as aliases: `vlan_up.sh` (= `host`), `vlan_connect.sh`/`.ps1` (= `join`), `vlan_down.sh`, `vlan_disconnect.sh`/`.ps1` (= `stop`).

## Dedicated server

The server is the game itself, run headless. The launchers are in `addons/lan_party/tools`:

| | Linux | Windows |
|---|---|---|
| control menu | `server.sh` | double-click `server.cmd` |
| one step | `server.sh start\|stop\|restart\|status\|players\|log\|console\|settings` | `server.cmd start\|stop\|…` (the same) |
| in this window | `server.sh run [options]` (or just `server.sh --port …`) | `server.cmd run [options]` |

The menu shows whether the server is running, where it is, its players and uptime, and the saved settings:

```
== Godot game: dedicated server ==
  server   : RUNNING for 12m (pid 4242) - lobby, 2 of 8 player(s), port 7777
  settings : port 7777, name "Server", up to 8 players, idle kick 5 min, virtual LAN off

  1  stop          2  restart
  3  status        4  players       5  follow the log
  6  console       7  settings
  q  quit this menu (the server keeps running)
```

- **Start / stop:** `start` runs the server in the background, so quitting the menu or closing the window leaves it running. `stop` asks the game to save and tell the players, then it quits. If it doesn't quit within 15 s, it's ended.
- **Status, players:** asked of the running server. `send <command>` runs any console command once, e.g. `server.sh send kick 2`.
- **Follow the log:** the server's output as it comes. Ctrl+C (Linux) or q (Windows) goes back to the menu.
  - Linux: `~/.local/state/<prefix>-server/server.log`
  - Windows: `%LOCALAPPDATA%\<prefix>-server\server.log`
  - The previous run's log is kept as `server.log.1`.
- **Console:** type the server commands below into the running server. An empty line goes back.
- **Settings:** port, name, max players, idle kick, the virtual LAN on/off, and the game's own choices (`extra_settings` in `lan_party.cfg`; each item cycles through its choices). They're saved next to the log and used at the next start. `start --port N …` adds one-off options on top.
- **How the menu reaches the server:**
  - The server is started with `--control FILE` and listens on `127.0.0.1` only, on a free port.
  - It writes its pid, that port and a random token to the file, in a folder only this user can read. Each request must carry the token.
  - The file is removed on a clean stop. A file left by a killed server is spotted (the pid is gone) and cleaned up.
- **Godot:** `$GODOT`, then `godot` on the PATH, then a Godot binary in the project folder, the folder above it, `tools`, or a `Godot*` folder in those (where "Extract all" puts the zip's files). If none is found, it lists where it looked, the exact names it wants, and any Godot-like files whose names don't match. For an exported game, set `GODOT` to the game's executable.
  - **Windows:** keep **both** exes from the Godot zip side by side: `Godot_v4.x-stable_win64.exe` and `Godot_v4.x-stable_win64_console.exe`, or renamed to `godot.exe` and `godot_console.exe`. The server runs the console one, which starts the plain exe of the same name and shows its output. With Explorer hiding extensions, a file renamed to "godot.exe" is really `godot.exe.exe`.
  - **Linux:** `Godot_v4.x-stable_linux.x86_64`, `godot` or `godot.x86_64`.
- **Virtual LAN on** (settings, or `--vlan`): `start` runs `vlan_auto host` first and prints the first invite. Guests are then handled with `8 VLAN guests + invite` or from the console. On Windows this needs admin, and the menu reopens itself as administrator.
- **Windows firewall:** after a start, and in `status`, the menu warns if Windows Firewall blocks Godot for other PCs, and names the fix (`vlan_auto.cmd firewall`).

Console commands (the menu's console, `send`, or typed into the window with `run`). `help` lists them, the game's own included.

| command | does |
|---|---|
| `info` | One line for programs (`INFO room=… players=… up=… port=… max=… idle_kick=… vlan=… <the game's fields> hosting=… name=…`). The menu reads it. |
| `stop` | Saves, tells the players and quits (also `quit`, `exit`). Ctrl+C quits at once instead. |
| `invite` | The virtual LAN invite (one for all guests). |
| `add <reply>` / paste a bare `lpr2.…` | Adds a guest (a taken name becomes `Name#2`). |
| `guests` | Guests, their names, and whether they're online. |
| `revoke <N>` | Removes guest `10.88.0.N`. |
| the game's | e.g. `status`, `players`, `kick <slot>`: see `help`. |

- Once hosting, the server prints where to join: the virtual LAN address, the LAN addresses, and `127.0.0.1` for a player on the same PC.
- **Options:** `--port N`, `--max-players N`, `--save-dir PATH` (`user://server`), `--name NAME`, `--status SECONDS`, `--idle-kick MIN` (5), `--vlan`, `--control FILE`, and the game's own.
- **While the server runs, its virtual LAN stays on** (it's hosting, see below). Stop the server and the virtual LAN goes off 5 minutes later.
- Its saves are its own (`--save-dir`), so a player on the server's PC keeps their own progress.

## Names

- **Optional, with a default.** The default is the computer name. A distro's stock host name (`archlinux`, `ubuntu`, …) gets the login name in front, such as `qvin-archlinux`, so it's more likely to be unique. The name can be up to 24 characters, and spaces and accents are fine.
- **Asked once.**
  - The host is asked when the virtual LAN is made, before the first invite.
  - A guest is asked on every new invite, before the reply. The suggestion is shown first.
  - `vlan_auto name` changes it later.
- **Taken names get a number.** The host keeps every name on its virtual LAN unique, ignoring case. If `Player` is there and another `Player` joins, the newcomer shows as `Player#2`, then `Player#3`. `status` and the server console's `guests` list the names.
- **The game can read the name** from `~/.local/state/<prefix>-vlan-name` (Linux) or `C:\ProgramData\<prefix>-vlan-name` (Windows), e.g. as the default player name.
- **Code versions.** Codes carrying a name end their prefix in `2.` (`lpi2.`/`lpr2.`). Older `…1.` codes still work (no name: `guest N`).

## How it works

Both sides know each other's public address (that's why there are two codes) and send to each other at the same time, with a keepalive every 25 s. Each router sees outgoing traffic, so it lets the other side's packets back in. This is UDP hole punching.

- **IPv6 is the default.** It's used whenever both sides have a public IPv6. There's no address translation, so it works almost always.
- **IPv4 is the fallback.** It works only if both routers keep the UDP port number unchanged. It never works behind CGNAT. Finding your own public IPv4 needs one lookup at `api.ipify.org`.

If a public address changes (home IPs change sometimes, for example after a router restart), the tunnel can't connect any more. `vlan_auto` checks for this every time it starts the tunnel (see the next section) and says which code to send.

## Off after a restart or when idle

- **A restart turns it all off.** The tunnel isn't started at boot: on Linux the NM connection has autoconnect off, and on Windows the tunnel service is set to Manual. A dedicated server never starts on its own anyway.
- **Idle for 5 minutes turns it off.** While the tunnel is up, a small watchdog checks its traffic every 30 s. Once 5 minutes pass with less than 2 KB per check, it takes the tunnel down. Keepalives and status pings stay well under that, while a game sends much more even standing in a lobby. A game or dedicated server listening on the game's UDP port on that PC counts as activity, so a server waiting for players keeps its virtual LAN.
  - **Linux:** the watchdog is `vlan_auto.sh watch`, run as the user unit `<vlan_name>-idle`. Where there's no systemd user session it's a detached process instead. A desktop notification says when it turned the tunnel off.
  - **Windows:** a hidden PowerShell process.
  - **Either way:** it ends with the tunnel, and `stop` ends it too. `status` says why the tunnel is off.
- **Starting again** is just running `vlan_auto` (or `vlan_auto start`, or `server.sh --vlan`) on each PC. Before it starts, it compares this PC's public address with the one in the codes you sent:

| | what happens |
|---|---|
| unchanged | The same tunnel starts. Both sides start theirs, and they find each other with no new codes. |
| **host's** changed | The host's `vlan_auto` prints the new invite, one for all guests. Each guest pastes it (same address and key). No new reply is needed unless the guest's public address changed too. |
| **guest's** changed | The guest's `vlan_auto` prints the new reply. The host pastes it (`vlan_auto <reply>`, or `add` in the server console). |

Keys and the guest's address are kept until `stop`, so a rejoin keeps its address.

## What gets changed, and what `stop` removes

**Linux** (NetworkManager):
- **Network:** an NM connection and interface named after `vlan_name` (`lanparty`). Autoconnect is off, so it stays down after a reboot until `vlan_auto` runs again. No sudo is needed for this part, since polkit lets the desktop user change NetworkManager settings.
- **Firewall:** only if ufw is active, and this step needs root: sudo, or pkexec from the game (`LANPARTY_SUDO`), one call per step. The rules are `allow 51820/udp` and `allow in on lanparty to any port 7777 proto udp` (the game only), tagged with the comment `lanparty-vlan`. Only rules the script actually added are recorded, and only those are removed.
- **State:** `~/.local/state/<prefix>-vlan` (host) or `~/.local/state/<prefix>-vlan-guest` (guest), with mode 700. It holds the keys, the guests and their names, the public address the codes were made with, and the watchdog's lock. The name is in `~/.local/state/<prefix>-vlan-name`.
- **Packages:** none are installed. Keys are made with `openssl`, and NetworkManager has WireGuard built in. Anything missing is named with the install command for your distro.

**Windows** (the official WireGuard client):
- **Software:** WireGuard via winget, but only if it's missing. `stop` uninstalls it only if the script installed it.
- **Tunnel:** a service named `WireGuardTunnel$lanparty`, with Manual start. Guests are added to a running host live, without a restart.
- **Firewall:** rules in the group `<prefix>-vlan`: inbound UDP 51820, plus the game's UDP port and ping from `10.88.0.0/24`, plus one per allowed game exe (from `10.88.0.0/24`). Godot Block rules switched off by `firewall` or `host` are listed in `C:\ProgramData\<prefix>-vlan-fw`, and `stop` switches them back on.
- **State:** `C:\ProgramData\<prefix>-vlan-host` (host) or `C:\ProgramData\<prefix>-vlan` (guest), readable only by admins and SYSTEM. The name is in `C:\ProgramData\<prefix>-vlan-name`, readable by everyone so the game can read it.

## Settings (environment variables)

| var | default | |
|---|---|---|
| `VLAN_PORT` | `vlan_port` (51820) | WireGuard UDP port. Use the same value on every machine. |
| `VLAN_IPV4` | auto (`api.ipify.org`) | Public IPv4 to advertise, or `none` to skip IPv4. |
| `VLAN_IDLE_MIN` | `5` | Minutes without game traffic before the tunnel goes off. `0` keeps it on until a restart. |
| `LANPARTY_CONFIG` | | One more `lan_party.cfg` read last (tests). |
| `LANPARTY_SERVER_DIR` | | The dedicated server's folder instead of `<state>/<prefix>-server` (tests). |

## Limits

- **Guests reach only the virtual LAN host, not each other.** With 3+ PCs, the game (or the dedicated server) must run on the host.
- **Some setups can't be reached without a relay server:** no IPv6 on one side, plus a strict or CGNAT IPv4 router on either side.
- **To check whether a machine has IPv6,** open https://test-ipv6.com.
- **Firewall rules stay** after a restart or idle-off, until `stop`. They only allow the WireGuard port and the game over the tunnel, and they do nothing while the tunnel is down. Keeping them avoids a sudo prompt on every start.
- **IPv6 privacy addresses** change about once a day, and Windows and many Linux setups use them. The next start then counts as an address change and asks for new codes.
- **Linux and Windows only.** macOS isn't supported.
