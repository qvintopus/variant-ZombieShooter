# Dedicated co-op server control, Windows. Linux: tools/server.sh. See tools\vlan\README.md.
#   server.cmd                  menu: start / stop / restart, status, players, log, console, settings
#   server.cmd start [options]  start it in the background (saved settings, plus these options)
#   server.cmd stop             save the run, tell the players, quit
#   server.cmd restart          stop, then start
#   server.cmd status           running or not, room, players, uptime, settings
#   server.cmd players          who is connected
#   server.cmd log              follow the server's log (q goes back)
#   server.cmd console          type server commands (help lists them) into the running server
#   server.cmd send <command>   one server command, e.g. send kick 2
#   server.cmd settings         change the saved settings (port, name, players, idle kick, VLAN)
#   server.cmd run [options]    run it in this window instead (also: server.cmd --port ... as before)
# Options: --vlan --port N --max-players 2..8 --save-dir PATH --name NAME --status SECONDS --idle-kick MIN
# The server runs in a hidden window until stopped (closing the menu leaves it running); its log is in
# %LOCALAPPDATA%\zs-server\server.log. The menu talks to it over 127.0.0.1 with a token only this user
# can read. The virtual LAN setting needs admin (the menu reopens itself as admin for it).
# Godot: $env:GODOT, else godot on the PATH, else a Godot_v*_win64_console.exe next to the project folder
# (the console build: the plain .exe has no console to print to).
$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Dir = Join-Path $env:LOCALAPPDATA "zs-server"
$Control = Join-Path $Dir "control"
$Log = Join-Path $Dir "server.log"
$SettingsFile = Join-Path $Dir "settings"
$Self = "server.cmd"
New-Item -ItemType Directory $Dir -Force | Out-Null
$Argv = @($args | ForEach-Object { "$_" })
$Cmd = if ($Argv.Count -gt 0) { $Argv[0] } else { "" }
$Rest = if ($Argv.Count -gt 1) { $Argv[1..($Argv.Count - 1)] } else { @() }

function IsAdmin {
    $me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
# Reopen this script as admin with these arguments (exit 10: server.cmd doesn't pause for this window).
function Elevate([string[]]$with) {
    $a = @("-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    foreach ($x in $with) { $a += "`"$x`"" }
    Start-Process powershell -Verb RunAs -ArgumentList $a
    exit 10
}

function FindGodot {
    if ($script:Godot) { return $true }
    $g = $env:GODOT
    if (-not $g) { $c = Get-Command godot -ErrorAction SilentlyContinue; if ($c) { $g = $c.Source } }
    if (-not $g) {
        $f = Get-ChildItem (Split-Path $Root -Parent) -Filter "Godot_v*_win64_console.exe" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
        if ($f) { $g = $f.FullName }
    }
    if (-not $g) {
        $gui = Get-ChildItem (Split-Path $Root -Parent) -Filter "Godot_v*_win64.exe" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
        if ($gui) {
            Write-Host "only the GUI Godot ($($gui.Name)) was found; the server needs the _console.exe next to it (it comes in the same Godot zip)."
            $g = $gui.FullName
        }
    }
    if (-not $g) {
        Write-Host "no Godot found. Put Godot_v*_win64_console.exe next to the project folder, or set GODOT=C:\path\to\Godot_console.exe"
        return $false
    }
    $script:Godot = $g
    if (-not (Test-Path (Join-Path $Root ".godot\imported"))) {
        Write-Host "first start, importing the project..."
        Push-Location $Root; & $g --headless --path . --import | Out-Null; Pop-Location
    }
    $true
}

# ---------------------------------------------------------------- settings

function LoadSettings {
    $script:S = @{ port = "24565"; name = "Server"; max_players = "8"; idle_kick = "5"; vlan = "no" }
    if (-not (Test-Path $SettingsFile)) { return }
    foreach ($line in (Get-Content $SettingsFile -Encoding UTF8)) {
        $k, $v = $line.Split("=", 2)
        switch ($k) {
            "port" { if ($v -match '^\d+$') { $S.port = $v } }
            "name" { if ($v) { $S.name = $v } }
            "max_players" { if ($v -match '^[2-8]$') { $S.max_players = $v } }
            "idle_kick" { if ($v -match '^\d+(\.\d+)?$') { $S.idle_kick = $v } }
            "vlan" { if ($v -in @("yes", "no")) { $S.vlan = $v } }
        }
    }
}
function SaveSettings {
    $text = "port=$($S.port)`nname=$($S.name)`nmax_players=$($S.max_players)`nidle_kick=$($S.idle_kick)`nvlan=$($S.vlan)`n"
    [IO.File]::WriteAllText($SettingsFile, $text, (New-Object Text.UTF8Encoding $false))
}
function SettingsLine {
    $idle = if ($S.idle_kick -eq "0") { "no idle kick" } else { "idle kick $($S.idle_kick) min" }
    "port $($S.port), name `"$($S.name)`", up to $($S.max_players) players, $idle, virtual LAN $(if ($S.vlan -eq 'yes') { 'on' } else { 'off' })"
}
function ServerArgs {
    $a = @("--port", $S.port, "--name", $S.name, "--max-players", $S.max_players, "--idle-kick", $S.idle_kick)
    if ($S.vlan -eq "yes") { $a += "--vlan" }
    $a
}

# ---------------------------------------------------------------- the running server

# control file: key=value lines written by the server (pid, control_port, token, port, started, name)
function ControlGet([string]$key) {
    if (-not (Test-Path $Control)) { return "" }
    foreach ($line in (Get-Content $Control)) { if ($line.StartsWith("$key=")) { return $line.Substring($key.Length + 1) } }
    ""
}
function ServerPid {
    $p = ControlGet "pid"
    if ($p -and (Get-Process -Id ([int]$p) -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "*odot*" })) { return [int]$p }
    if (Test-Path $Control) { Remove-Item $Control -Force }   # left by a server that was killed
    0
}
function Running { (ServerPid) -gt 0 }

# One command to the running server; returns its answer (without the echoed "> command" line).
function Request([string]$line) {
    $port = ControlGet "control_port"; $token = ControlGet "token"
    if (-not $port) { return "the server isn't running" }
    try {
        $c = New-Object Net.Sockets.TcpClient("127.0.0.1", [int]$port)
        $c.ReceiveTimeout = 120000
        $s = $c.GetStream()
        $b = [Text.Encoding]::UTF8.GetBytes("TOKEN $token`n$line`n")
        $s.Write($b, 0, $b.Length); $s.Flush()
        $text = (New-Object IO.StreamReader($s, [Text.Encoding]::UTF8)).ReadToEnd()
        $c.Close()
    } catch { return "the server doesn't answer (port $port)" }
    ($text -split "`n" | Where-Object { -not $_.StartsWith("> ") }) -join "`n"
}

# info -> $script:I (room players active up port max idle_kick vlan name), $null when it doesn't answer
function ReadInfo {
    $script:I = $null
    $line = (Request "info") -split "`n" | Where-Object { $_.StartsWith("INFO ") } | Select-Object -First 1
    if (-not $line) { return $false }
    $i = @{}
    $at = $line.IndexOf(" name=")
    $i.name = if ($at -ge 0) { $line.Substring($at + 6) } else { "" }
    foreach ($kv in $line.Substring(5, $(if ($at -ge 0) { $at - 5 } else { $line.Length - 5 })).Split(" ")) {
        $k, $v = $kv.Split("=", 2); if ($k) { $i[$k] = $v }
    }
    $script:I = $i
    $true
}
function Duration([int]$s) { if ($s -ge 3600) { "$([int][Math]::Floor($s / 3600))h $([int][Math]::Floor(($s % 3600) / 60))m" } elseif ($s -ge 60) { "$([int][Math]::Floor($s / 60))m" } else { "${s}s" } }
function RoomName([string]$r) { if ($r -eq "room_H00") { "home base" } elseif (-not $r) { "starting" } else { $r -replace '^room_', '' } }
function StateLine {
    $p = ServerPid
    if (-not $p) { return "stopped" }
    if (ReadInfo) {
        $v = if ($I.vlan -ne "-") { ", VLAN $($I.vlan)" } else { "" }
        "RUNNING for $(Duration ([int]$I.up)) (pid $p) - $(RoomName $I.room), $($I.players) of $($I.max) player(s), port $($I.port)$v"
    } else { "RUNNING (pid $p), starting up or busy" }
}

# ---------------------------------------------------------------- commands

function Start-Server([string[]]$extra) {
    $p = ServerPid
    if ($p) { Write-Host "already running (pid $p). Stop it first, or restart."; return }
    LoadSettings
    $a = @(ServerArgs) + @($extra | Where-Object { $_ })
    $vlan = $a -contains "--vlan"
    if ($vlan -and -not (IsAdmin)) {
        Write-Host "the virtual LAN needs admin: opening this as administrator..."
        Elevate (@("start") + $extra)
    }
    if (-not (FindGodot)) { return }
    if ($vlan) {
        Write-Host "virtual LAN first (vlan_auto host):"
        & (Join-Path $PSScriptRoot "vlan\vlan_auto.ps1") host --machine
        if ($LASTEXITCODE -ne 0) { Write-Host "the virtual LAN didn't come up (see above); fix it, or turn it off in settings"; return }
        Write-Host ""
    }
    if (Test-Path $Log) { Move-Item $Log "$Log.1" -Force }
    if (Test-Path $Control) { Remove-Item $Control -Force }
    # a hidden window of its own (so closing this one leaves it running); cmd writes its output to the log
    $q = @("--headless", "--path", ".", "--", "--server", "--control", $Control) + $a | ForEach-Object { if ($_ -match '[\s"]' -or $_ -eq "") { "`"$($_ -replace '"', '')`"" } else { $_ } }
    $line = "`"`"$Godot`" $($q -join ' ') > `"$Log`" 2>&1 < nul`""
    Start-Process cmd -ArgumentList "/c", $line -WorkingDirectory $Root -WindowStyle Hidden | Out-Null
    Write-Host "starting the server ($($a -join ' '))"
    for ($n = 0; $n -lt 120; $n++) {
        Start-Sleep -Milliseconds 500
        $text = if (Test-Path $Log) { [IO.File]::ReadAllText($Log) } else { "" }   # (cmd keeps it open: ReadAllText shares it)
        if ($text -match 'hosting on port \d+ - OK' -and (Test-Path $Control)) {
            Write-Host "server is up. Players join at:"
            $text -split "`n" | Where-Object { $_ -match 'join .* at' } | ForEach-Object { Write-Host ("  " + ($_ -replace '^DedicatedServer \[INFO\]: ', '').Trim()) }
            return
        }
        if ($text -match 'hosting on port \d+ - (?!OK)') {
            Write-Host "the server couldn't open its port:"; Write-Host ($text -split "`n" | Where-Object { $_ -match 'hosting on port' })
            $p = ControlGet "pid"; if ($p) { Stop-Process -Id ([int]$p) -Force -ErrorAction SilentlyContinue }
            return
        }
        if ($n -gt 8 -and -not (Test-Path $Control) -and -not (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Godot })) {
            Write-Host "the server quit while starting. The end of its log:"
            Get-Content $Log -Tail 20 -ErrorAction SilentlyContinue | Write-Host
            return
        }
    }
    Write-Host "the server is slow to start; check: $Self log"
}

function Stop-Server {
    $p = ServerPid
    if (-not $p) { Write-Host "the server isn't running."; return }
    Write-Host "stopping the server (the run is saved, players are told)..."
    Request "stop" | Out-Null
    $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
    if ($proc -and -not $proc.WaitForExit(15000)) {
        Write-Host "it didn't stop in 15 s; ending it (the run keeps its last checkpoint)"
        Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $Control) { Remove-Item $Control -Force }
    Write-Host "stopped."
}

function Show-Status {
    LoadSettings
    Write-Host "server   : $(StateLine)"
    if ((Running) -and (ReadInfo)) {
        Write-Host "name     : $($I.name)"
        Write-Host "players  : $($I.players) connected, $($I.active) active"
        $idle = $I.idle_kick -replace '\.0$', ''
        Write-Host "idle kick: $(if ($idle -eq '0') { 'off' } else { "$idle min (ghosts 3x)" })"
    }
    Write-Host "settings : $(SettingsLine)"
    Write-Host "log      : $Log"
}

function Show-Players { if (Running) { Write-Host (Request "players") } else { Write-Host "the server isn't running." } }

# The log as it grows; q or Esc goes back.
function Follow-Log {
    if (-not (Test-Path $Log)) { Write-Host "no log yet (start the server first)"; return }
    Write-Host "== $Log (q goes back) =="
    $fs = New-Object IO.FileStream($Log, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    $r = New-Object IO.StreamReader($fs)
    $lines = New-Object Collections.Generic.Queue[string]
    while ($null -ne ($l = $r.ReadLine())) { $lines.Enqueue($l); if ($lines.Count -gt 40) { [void]$lines.Dequeue() } }
    $lines | ForEach-Object { Write-Host $_ }
    while ($true) {
        while ($null -ne ($l = $r.ReadLine())) { Write-Host $l }
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq "Q" -or $k.Key -eq "Escape") { break }
        }
        Start-Sleep -Milliseconds 300
    }
    $r.Close()
    Write-Host ""
}

function Open-Console {
    if (-not (Running)) { Write-Host "the server isn't running."; return }
    Write-Host "server console: type a command (help lists them), Enter on an empty line goes back."
    while ($true) {
        $line = Read-Host "server"
        if (-not "$line".Trim() -or $line -in @("back", "q")) { break }
        Write-Host (Request $line)
        if (-not (Running)) { Write-Host "(the server has stopped)"; break }
    }
}

function Ask([string]$prompt, [string]$default) {
    $v = Read-Host "$prompt [$default]"
    if ("$v".Trim()) { "$v".Trim() } else { $default }
}

function Edit-Settings {
    LoadSettings
    while ($true) {
        Write-Host ""
        Write-Host "== settings (used on the next start) =="
        Write-Host "  1  port          $($S.port)"
        Write-Host "  2  name          $($S.name)"
        Write-Host "  3  max players   $($S.max_players)"
        Write-Host "  4  idle kick     $(if ($S.idle_kick -eq '0') { 'off' } else { "$($S.idle_kick) min" })"
        Write-Host "  5  virtual LAN   $(if ($S.vlan -eq 'yes') { 'on (hosts zs-vlan, needs admin; see tools\vlan\README.md)' } else { 'off' })"
        Write-Host "  b  back"
        $c = Read-Host "change"
        switch ($c) {
            "1" { $v = Ask "port (1024-65535)" $S.port; if ($v -match '^\d+$' -and [int]$v -ge 1024 -and [int]$v -le 65535) { $S.port = $v } else { Write-Host "not a port" } }
            "2" { $v = (Ask "server name" $S.name) -replace '[\p{Cc}"&|<>^%!]', ''; if ($v.Length -gt 24) { $v = $v.Substring(0, 24) }; if ($v) { $S.name = $v } }
            "3" { $v = Ask "max players (2-8)" $S.max_players; if ($v -match '^[2-8]$') { $S.max_players = $v } else { Write-Host "2 to 8" } }
            "4" { $v = Ask "idle kick minutes (0 = off)" $S.idle_kick; if ($v -match '^\d+(\.\d+)?$') { $S.idle_kick = $v } else { Write-Host "a number of minutes" } }
            "5" { $S.vlan = if ($S.vlan -eq "yes") { "no" } else { "yes" } }
            { $_ -in @("b", "q", "") } { SaveSettings; if (Running) { Write-Host "the server is running: restart it to use the new settings." }; return }
            default { Write-Host "pick 1-5 or b" }
        }
        SaveSettings
    }
}

function Show-Menu {
    while ($true) {
        LoadSettings
        Write-Host ""
        Write-Host "== Zombie Shooter dedicated server =="
        Write-Host "  server   : $(StateLine)"
        Write-Host "  settings : $(SettingsLine)"
        Write-Host ""
        $on = Running
        if ($on) { Write-Host "  1  stop          2  restart" } else { Write-Host "  1  start" }
        Write-Host "  3  status        4  players       5  follow the log"
        Write-Host "  6  console       7  settings$(if ($S.vlan -eq 'yes') { '      8  VLAN guests + invite' })"
        Write-Host "  q  quit this menu (the server keeps running)"
        $c = Read-Host "choose"
        Write-Host ""
        switch ($c) {
            "1" { if ($on) { Stop-Server } else { Start-Server @() } }
            "2" { if ($on) { Stop-Server; Start-Server @() } else { Write-Host "not running (1 starts it)" } }
            "3" { Show-Status }
            "4" { Show-Players }
            "5" { Follow-Log }
            "6" { Open-Console }
            "7" { Edit-Settings }
            "8" { if ($on) { Write-Host (Request "guests") } else { Write-Host "the server isn't running." } }
            { $_ -in @("q", "Q") } { return }
            "" { }
            default { Write-Host "pick one of the numbers, or q" }
        }
    }
}

# the old way: the server in this window, typing into it
function Run-Here([string[]]$pass) {
    $vlan = $false
    $p = @()
    foreach ($a in $pass) { if ($a -in @("--vlan", "-Vlan", "-vlan")) { $vlan = $true; $p += "--vlan" } else { $p += $a } }
    if ($vlan -and -not (IsAdmin)) { Elevate (@("run") + $p) }
    if (-not (FindGodot)) { exit 1 }
    Set-Location $Root
    if ($vlan) {
        # --machine: shows the invite but doesn't stop to ask for replies - paste those into the server console
        & (Join-Path $PSScriptRoot "vlan\vlan_auto.ps1") host --machine
        if ($LASTEXITCODE -ne 0) { Write-Host "server: the virtual LAN didn't come up (see above); fix it or start without --vlan"; exit 1 }
        Write-Host ""
    }
    & $Godot --headless --path . -- --server @p
    exit $LASTEXITCODE
}

switch -regex ($Cmd) {
    '^$' { Show-Menu; break }
    '^menu$' { Show-Menu; break }
    '^start$' { Start-Server $Rest; break }
    '^stop$' { Stop-Server; break }
    '^restart$' { Stop-Server; Start-Server $Rest; break }
    '^status$' { Show-Status; break }
    '^players$' { Show-Players; break }
    '^log$' { Follow-Log; break }
    '^console$' { Open-Console; break }
    '^send$' {
        if ($Rest.Count -eq 0) { Write-Host "usage: $Self send <command>"; exit 1 }
        if (-not (Running)) { Write-Host "the server isn't running."; exit 3 }
        Write-Host (Request ($Rest -join " ")); break
    }
    '^settings$' { Edit-Settings; break }
    '^(help|-h|--help)$' { Get-Content $PSCommandPath | Select-Object -Skip 1 -First 17 | ForEach-Object { $_ -replace '^# ?', '' }; break }
    '^run$' { Run-Here $Rest; break }
    '^-' { Run-Here $Argv; break }
    default { Write-Host "unknown command '$Cmd' (try: $Self help)"; exit 1 }
}
exit 0
