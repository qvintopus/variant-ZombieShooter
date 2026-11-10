# zs-vlan, guided, Windows (official WireGuard client). Linux: vlan_auto.sh. See README.md.
#   vlan_auto.cmd                     guided: host or join, then tells you each next step
#   vlan_auto.cmd <code>              paste whatever you got: an invite (zsi1.) joins, a reply (zsr1.) adds that guest
#   vlan_auto.cmd host                create the virtual LAN (or show it) + the invite for the next guest
#   vlan_auto.cmd host add <reply>    add a guest from the reply they sent back
#   vlan_auto.cmd host remove <N>     remove guest 10.77.0.N
#   vlan_auto.cmd join <invite>       join a host's virtual LAN; prints the reply to send back
#   vlan_auto.cmd start               start the last virtual LAN again (after a restart or going idle)
#   vlan_auto.cmd status              what this PC is, who is online, the code to send
#   vlan_auto.cmd stop                remove everything this made (host or guest)
# --machine anywhere: no prompts, no clipboard, short waits, and a last line "ZSVLAN key=value ..."
# The tunnel never starts at boot, and goes off after VLAN_IDLE_MIN (5) minutes without game traffic.
# Starting it again checks the public address: unchanged, the old codes still work; changed, it says
# which new code to send.
# Exit codes: 0 ok, 1 usage or broken code, 2 something this PC needs is missing, 3 wrong state, 4 timed out,
#   10 reopened itself as admin in a new window.
# Asks for admin. Installs WireGuard with winget if missing ('stop' uninstalls it again if it was installed here).
# The invite/reply codes are the same as vlan_auto.sh's, so Linux and Windows PCs mix freely.
$ErrorActionPreference = "Stop"
$Machine = $false
$Argv = @()
foreach ($a in $args) { if ("$a" -eq "--machine") { $Machine = $true } else { $Argv += "$a" } }
$Cmd = if ($Argv.Count -gt 0) { $Argv[0] } else { "" }

$Name = "zsvlan"; $Net = "10.77.0"; $GamePort = 24565
$Port = if ($env:VLAN_PORT) { [int]$env:VLAN_PORT } else { 51820 }
$StateHost = Join-Path $env:ProgramData "zs-vlan-host"
$StateGuest = Join-Path $env:ProgramData "zs-vlan"   # the folder older guest scripts used, so they keep working
$WgExe = Join-Path $env:ProgramFiles "WireGuard\wireguard.exe"
$Wg = Join-Path $env:ProgramFiles "WireGuard\wg.exe"
$Svc = 'WireGuardTunnel$' + $Name
$Self = "vlan_auto.cmd"
$IdleMin = if ($env:VLAN_IDLE_MIN -match '^\d+$') { [int]$env:VLAN_IDLE_MIN } else { 5 }   # 0 = never
$IdleBytes = 2048   # less traffic than this per check counts as idle (a game sends far more)
$IdleCheck = if ($env:VLAN_IDLE_CHECK -match '^\d+$') { [int]$env:VLAN_IDLE_CHECK } else { 30 }   # seconds

if ($Cmd -in @("help", "-h", "--help")) {
    Get-Content $PSCommandPath | Select-Object -Skip 1 -First 16 | ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

function Fail([int]$code, [string]$msg) {
    [Console]::Error.WriteLine($msg)
    if ($Machine) { Write-Host "ZSVLAN state=error exit=$code" }
    exit $code
}
function Result([string]$text) { if ($Machine) { Write-Host "ZSVLAN $text" } }
function Clip([string]$text) {
    if ($Machine) { return }
    try { Set-Clipboard -Value $text; Write-Host "   (copied to the clipboard)" } catch {}
}

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($Machine) { Fail 2 "zs-vlan needs admin rights: run it (or the dedicated server) as administrator" }
    $a = @("-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    foreach ($x in $Argv) { $a += "`"$x`"" }
    Start-Process powershell -Verb RunAs -ArgumentList $a
    exit 10   # vlan_auto.cmd: the admin window took over, don't pause here
}

# ---------------------------------------------------------------- shared

function Enc([string]$prefix, [string]$text) { "$prefix." + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($text)) }
function Dec([string]$prefix, [string]$line) {
    if (-not $line.StartsWith("$prefix.")) { Fail 1 "not a $prefix code: $line" }
    try { return [Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($line.Substring($prefix.Length + 1))).Split(" ") }
    catch { Fail 1 "broken $prefix code (copy the whole line)" }
}
# Public IPv6 = the source address Windows uses toward the internet (no external lookup). "-" if none.
function MyV6 {
    try {
        $a = (Find-NetRoute -RemoteIPAddress "2606:4700:4700::1111" -ErrorAction Stop | Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress
        if ($a -and $a -notmatch '^(fe80|fc|fd)') { return $a }
    } catch {}
    "-"
}
# Public IPv4 (fallback only): $env:VLAN_IPV4 = addr sets it, "none" skips; else one lookup at api.ipify.org.
function MyV4 {
    if ($env:VLAN_IPV4) { if ($env:VLAN_IPV4 -eq "none") { return "-" } return $env:VLAN_IPV4 }
    try { $a = "$(Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 4)".Trim(); if ($a -match '^\d+\.\d+\.\d+\.\d+$') { return $a } } catch {}
    "-"
}
# IPv6 when both sides have it, else the peer's IPv4; $null when neither works.
function PickEp($v6, $v4, $port, $myv6) {
    if ($v6 -ne "-" -and $myv6 -ne "-") { return "[${v6}]:${port}" }
    if ($v4 -ne "-") { return "${v4}:${port}" }
    $null
}
function AddrWarn($v6, $v4) {
    if ($v6 -eq "-" -and $v4 -eq "-") { Write-Host "warning   : no public IPv6 and no public IPv4 found - check the internet connection" }
    elseif ($v6 -eq "-") {
        Write-Host "note      : no public IPv6 here; the IPv4 fallback fails behind CGNAT or a port-changing router"
        Write-Host "            (check both PCs at https://test-ipv6.com - IPv6 on both sides almost always works)"
    }
}
function PingSt([string]$ip) { if ("$(ping -n 1 -w 1000 $ip)" -match 'TTL=') { "online" } else { "no reply" } }
function WaitOnline([string]$ip, [int]$seconds) {
    $end = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $end) {
        if ((PingSt $ip) -eq "online") { if (-not $Machine) { Write-Host "" }; return $true }
        if (-not $Machine) { Write-Host -NoNewline "." }
        Start-Sleep 1
    }
    if (-not $Machine) { Write-Host "" }
    $false
}
function Role {
    if (Test-Path $StateHost) { "host" } elseif (Test-Path $StateGuest) { "guest" } else { "none" }
}
# TunnelUp: the tunnel service is installed (it may be stopped); TunnelOn: it runs.
function TunnelUp { [bool](Get-Service $Svc -ErrorAction SilentlyContinue) }
function TunnelOn { (TunnelState) -eq "Running" }
function TunnelState { $s = Get-Service $Svc -ErrorAction SilentlyContinue; if ($s) { "$($s.Status)" } else { "not installed" } }
# A native tool whose stderr must not throw (Windows PowerShell 5.1 turns it into an error under "Stop").
function Native([scriptblock]$block) {
    $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & $block 2>$null } catch {} finally { $ErrorActionPreference = $old }
}
function Pub([string]$keyfile) { ((Get-Content $keyfile -Raw).Trim() | & $Wg pubkey).Trim() }

# Everything this PC needs; one line with the fix per problem.
function Preflight {
    if ([Environment]::OSVersion.Version.Major -lt 10) { Fail 2 "problem: needs Windows 10 or newer" }
    if (-not (Get-Command Find-NetRoute -ErrorAction SilentlyContinue)) { Fail 2 "problem: the NetTCPIP PowerShell module is missing (Windows 10+ has it) - run this from Windows PowerShell" }
}
function NewStateDir([string]$dir) {
    if (Test-Path $dir) { return }
    New-Item -ItemType Directory $dir | Out-Null
    icacls $dir /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" | Out-Null   # admins + SYSTEM only
}
function EnsureWireGuard([string]$dir) {
    if (Test-Path $WgExe) { return }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Fail 2 "problem: WireGuard is missing and winget isn't available - install it from https://www.wireguard.com/install/ and run this again" }
    Write-Host "installing WireGuard (winget)..."
    winget install --id WireGuard.WireGuard -e --silent --accept-package-agreements --accept-source-agreements | Out-Host
    if (-not (Test-Path $WgExe)) { Fail 2 "problem: the WireGuard install failed - install it from https://www.wireguard.com/install/ and run this again" }
    Set-Content "$dir\installed_wireguard" "1"
}
function InstallTunnel([string]$dir) {
    if (TunnelUp) { & $WgExe /uninstalltunnelservice $Name; Start-Sleep 3 }
    & $WgExe /installtunnelservice "$dir\$Name.conf"
    Start-Sleep 3
    TunnelStarted $dir
}
# Never at boot (Manual: a restart leaves it off until vlan_auto runs again), then the idle watchdog.
# Also fixes services made by older versions, which started at boot.
function TunnelStarted([string]$dir) {
    Set-Service $Svc -StartupType Manual -ErrorAction SilentlyContinue
    if (-not (TunnelOn)) { Start-Service $Svc }
    WatchStart $dir
}
function OffReason([string]$dir) {
    if (Test-Path "$dir\idle_down") { (Get-Content "$dir\idle_down" -Raw).Trim() } else { "not started since the PC restarted, or stopped" }
}

# Public addresses now vs. the ones the codes were made with ($dir\public: "v6 v4"). Sets V6 V4 and
# PubOld (the saved ones when they differ, else ""); PubCheck also saves the current ones.
function PubCompare([string]$dir) {
    $script:V6 = MyV6; $script:V4 = MyV4; $script:PubOld = ""
    if (Test-Path "$dir\public") {
        $saved = (Get-Content "$dir\public" -Raw).Trim()
        if ($saved -and $saved -ne "$($script:V6) $($script:V4)") { $script:PubOld = $saved }
    }
}
function PubCheck([string]$dir) { PubCompare $dir; Set-Content "$dir\public" "$($script:V6) $($script:V4)" }
$V6 = $null; $V4 = $null; $PubOld = ""

# ---- idle watchdog: "vlan_auto.ps1 watch <minutes>", a hidden process while the tunnel runs
function WatchStart([string]$dir) {
    if ($IdleMin -le 0) { return }
    Remove-Item "$dir\idle_down" -ErrorAction SilentlyContinue
    # a second one exits at once (mutex in Watch)
    Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "watch", "$IdleMin")
}
function WatchStop([string]$dir) {
    if (-not (Test-Path "$dir\watch.pid")) { return }
    $p = Get-Process -Id ([int](Get-Content "$dir\watch.pid" -Raw).Trim()) -ErrorAction SilentlyContinue
    if ($p -and $p.ProcessName -match 'powershell') { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
}
# Bytes through the tunnel so far (all peers, both ways), -1 when it isn't running.
function Traffic {
    if (-not (TunnelOn)) { return -1 }
    $t = [int64]0
    foreach ($l in @(Native { & $Wg show $Name transfer })) {
        $f = "$l".Trim() -split "\s+"
        if ($f.Count -ge 3) { $t += [int64]$f[1] + [int64]$f[2] }
    }
    $t
}
# A game or dedicated server listens on this PC: its friends can come any time, so that isn't idle.
function HostingGame { [bool](Get-NetUDPEndpoint -LocalPort $GamePort -ErrorAction SilentlyContinue) }
function Watch([int]$min) {
    $role = Role
    if ($role -eq "host") { $dir = $StateHost } elseif ($role -eq "guest") { $dir = $StateGuest } else { return }
    $mutex = New-Object Threading.Mutex($false, "Global\zsvlan-idle")
    try { if (-not $mutex.WaitOne(0)) { return } } catch [Threading.AbandonedMutexException] {}
    Set-Content "$dir\watch.pid" $PID
    $idle = 0; $off = 0; $last = Traffic
    while ($true) {
        Start-Sleep $IdleCheck
        if (-not (Test-Path $dir) -or -not (TunnelUp)) { return }
        $now = Traffic
        if ($now -lt 0) { $off++; if ($off -ge 2) { return }; continue }   # stopped by hand, or for a moment
        $off = 0
        # wg counts keepalives too (32 bytes each way every 25 s per guest)
        $limit = $IdleBytes + 128 * [Math]::Max(1, @(Peers).Count)
        if ($last -lt 0 -or ($now - $last) -lt 0 -or ($now - $last) -ge $limit -or (HostingGame)) { $idle = 0 } else { $idle += $IdleCheck }
        $last = $now
        if ($idle -ge $min * 60) {
            Stop-Service $Svc -ErrorAction SilentlyContinue
            Set-Content "$dir\idle_down" "idle for $min min, at $(Get-Date -Format HH:mm)"
            return
        }
    }
}
# UDP to WireGuard from anywhere; over the tunnel only the game and ping.
function FwOpen {
    if (Get-NetFirewallRule -Group "zs-vlan" -ErrorAction SilentlyContinue) { return }
    New-NetFirewallRule -DisplayName "zs-vlan WireGuard UDP $Port" -Group "zs-vlan" -Direction Inbound -Protocol UDP -LocalPort $Port -Action Allow -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName "zs-vlan game UDP $GamePort" -Group "zs-vlan" -Direction Inbound -Protocol UDP -LocalPort $GamePort -RemoteAddress "$Net.0/24" -Action Allow -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName "zs-vlan ping" -Group "zs-vlan" -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -RemoteAddress "$Net.0/24" -Action Allow -Profile Any | Out-Null
}

# ---------------------------------------------------------------- host

function Peers { if (Test-Path "$StateHost\peers") { @(Get-ChildItem "$StateHost\peers" | Sort-Object Name) } else { @() } }
function NextSlot { foreach ($n in 2..8) { if (-not (Test-Path "$StateHost\peers\$n")) { return "$n" } }; "-" }
function HostConf {
    $priv = (Get-Content "$StateHost\host.key" -Raw).Trim()
    $c = "[Interface]`r`nPrivateKey = $priv`r`nAddress = $Net.1/24`r`nListenPort = $Port`r`n"
    foreach ($f in (Peers)) {
        $pub, $ep = (Get-Content $f.FullName -Raw).Trim().Split(" ")
        $c += "`r`n[Peer]`r`nPublicKey = $pub`r`nAllowedIPs = $Net.$($f.Name)/32`r`nEndpoint = $ep`r`nPersistentKeepalive = 25`r`n"
    }
    [IO.File]::WriteAllText("$StateHost\$Name.conf", $c)
}

function HostUp {
    if ((Role) -eq "guest") { Fail 3 "this PC has joined someone else's virtual LAN; to host instead run: $Self stop" }
    if ((Test-Path "$StateHost\host.key") -and (TunnelUp)) {
        PubCheck $StateHost
        $was = TunnelOn
        TunnelStarted $StateHost
        if (-not $was) { Write-Host "started the virtual LAN again (same keys and guests) - this PC is $Net.1"; Write-Host "" }
        return
    }
    Preflight
    NewStateDir $StateHost
    EnsureWireGuard $StateHost
    New-Item -ItemType Directory "$StateHost\peers" -Force | Out-Null
    if (-not (Test-Path "$StateHost\host.key")) { Set-Content "$StateHost\host.key" (& $Wg genkey).Trim() }
    PubCheck $StateHost
    HostConf
    InstallTunnel $StateHost
    FwOpen
    Write-Host "created the virtual LAN - this PC is $Net.1"
    Write-Host ""
}

function HostShow {
    if ($null -eq $script:V6) { PubCompare $StateHost }
    $v6 = $script:V6; $v4 = $script:V4
    Write-Host "== zs-vlan: this PC hosts =="
    Write-Host "this PC   : $Net.1   (tunnel $Name`: $(TunnelState))"
    Write-Host "public    : IPv6 $v6   IPv4 $v4"
    AddrWarn $v6 $v4
    if (-not (TunnelUp)) {
        Write-Host ""
        Write-Host "the tunnel is gone (removed outside vlan_auto). Recreate it: $Self host   or clean up: $Self stop"
        Result "role=host state=down ip=$Net.1"
        return
    }
    if (-not (TunnelOn)) {
        Write-Host ""
        Write-Host "the virtual LAN is off ($(OffReason $StateHost))."
        Write-Host "start it again: $Self   (same keys and guests; each guest starts theirs too)"
        Result "role=host state=off ip=$Net.1"
        return
    }
    $hpub = Pub "$StateHost\host.key"
    Write-Host "guests    :"
    $list = @()
    foreach ($f in (Peers)) {
        $pub, $ep = (Get-Content $f.FullName -Raw).Trim().Split(" ")
        $st = PingSt "$Net.$($f.Name)"
        Write-Host "  $Net.$($f.Name)  via $ep  ($st)"
        $list += "$($f.Name):$($st -replace ' ', '-')"
    }
    if ($list.Count -eq 0) { Write-Host "  none yet" }
    Write-Host ""
    # the guests' tunnels point at the old public address: each needs an invite with the new one
    $moved = "no"
    if ($script:PubOld -and $list.Count -gt 0) {
        $moved = "yes"
        $o6, $o4 = $script:PubOld.Split(" ")
        Write-Host "this PC's public address changed (was IPv6 $o6  IPv4 $o4), so guests can't reach it."
        Write-Host "send each guest their new invite; they paste it into vlan_auto (same slot, no new reply needed"
        Write-Host "unless their address changed too):"
        foreach ($f in (Peers)) { Write-Host "  $Net.$($f.Name):  $(Enc "zsi1" "$hpub $Port $($f.Name) $v6 $v4")" }
        Write-Host ""
    }
    $slot = NextSlot
    $code = "-"
    if ($slot -eq "-") {
        Write-Host "all 7 guest slots are used ($Self host remove <N> frees one)"
    } else {
        $code = Enc "zsi1" "$hpub $Port $slot $v6 $v4"
        Write-Host "1. send this invite to your friend (it holds only public info):"
        Write-Host ""
        Write-Host $code
        Clip $code
        Write-Host ""
        Write-Host "2. they run vlan_auto with it and send you back a reply code"
        Write-Host "3. you paste the reply:  $Self <reply>"
    }
    Write-Host ""
    Write-Host "game: host from the Comms Terminal, or run tools\server.cmd - friends join  $Net.1"
    $g = if ($list.Count -gt 0) { $list -join "," } else { "-" }
    Result "role=host state=up ip=$Net.1 game=$Net.1`:$GamePort next=$slot code=$code guests=$g moved=$moved"
}

function HostAdd([string]$reply) {
    if ((Role) -ne "host") { Fail 3 "this PC doesn't host a virtual LAN; run: $Self host   first" }
    $slot, $gpub, $gport, $gv6, $gv4 = Dec "zsr1" $reply
    if (-not ("$slot" -match '^[2-8]$' -and "$gpub".Length -eq 44 -and "$gport" -match '^\d+$')) { Fail 1 "broken reply code (copy the whole line)" }
    $file = "$StateHost\peers\$slot"
    if (Test-Path $file) {
        $old = (Get-Content $file -Raw).Trim().Split(" ")[0]
        if ($old -ne $gpub) { Fail 3 "slot $Net.$slot already belongs to another guest; send a fresh invite ($Self host) and have them join with it" }
    }
    $ep = PickEp $gv6 $gv4 $gport (MyV6)
    if (-not $ep) { Fail 3 "the guest sent no address usable from here (no IPv6 on one side and no IPv4 from them)" }
    Set-Content $file "$gpub $ep"
    HostConf
    Native { & $Wg set $Name peer $gpub allowed-ips "$Net.$slot/32" endpoint $ep persistent-keepalive 25 }
    if ($LASTEXITCODE -ne 0) { InstallTunnel $StateHost }   # tunnel wasn't running: start it with the new config
    Write-Host "guest $Net.$slot added (via $ep), waiting for it to answer"
    $wait = if ($Machine) { 20 } else { 60 }
    if (WaitOnline "$Net.$slot" $wait) {
        Write-Host "guest $Net.$slot is online - they join the game at $Net.1"
        Result "role=host state=added slot=$slot online=yes"
    } else {
        Write-Host "guest $Net.$slot doesn't answer yet. It connects once their side is up too;"
        Write-Host "check later with: $Self status   (both PCs need IPv6, or routers that keep UDP ports)"
        Result "role=host state=added slot=$slot online=no"
    }
}

function HostRemove([string]$n) {
    if (-not ($n -match '^[2-8]$')) { Fail 1 "usage: $Self host remove <2..8>" }
    $file = "$StateHost\peers\$n"
    if (-not (Test-Path $file)) { Fail 3 "no guest $Net.$n" }
    $pub = (Get-Content $file -Raw).Trim().Split(" ")[0]
    Remove-Item $file
    HostConf
    Native { & $Wg set $Name peer $pub remove }
    Write-Host "guest $Net.$n removed"
    Result "role=host state=removed slot=$n"
}

function HostLoop {
    HostShow
    if ($Machine) { return }
    while ($true) {
        Write-Host ""
        $line = (Read-Host "paste a reply code here when it arrives (Enter = done)") -replace '\s', ''
        if (-not $line) { break }
        & $PSCommandPath host add $line   # own process: a failed add doesn't end this loop
        Write-Host ""
        HostShow
    }
}

# ---------------------------------------------------------------- guest

function GuestJoin([string]$invite) {
    if ((Role) -eq "host") { Fail 3 "this PC hosts a virtual LAN; to join someone instead run: $Self stop" }
    $hpub, $hport, $slot, $hv6, $hv4 = Dec "zsi1" $invite
    if (-not ("$slot" -match '^[2-8]$' -and "$hpub".Length -eq 44 -and "$hport" -match '^\d+$')) { Fail 1 "broken invite code (copy the whole line)" }
    $ep = PickEp $hv6 $hv4 $hport (MyV6)
    if (-not $ep) { Fail 3 "the host has no address usable from here: they have no IPv4 in the invite and this PC has no IPv6" }
    Preflight
    NewStateDir $StateGuest
    EnsureWireGuard $StateGuest
    if (-not (Test-Path "$StateGuest\guest.key")) { Set-Content "$StateGuest\guest.key" (& $Wg genkey).Trim() }   # same key on rejoin
    Set-Content "$StateGuest\invite" $invite
    PubCheck $StateGuest
    $priv = (Get-Content "$StateGuest\guest.key" -Raw).Trim()
    $conf = "[Interface]`r`nPrivateKey = $priv`r`nAddress = $Net.$slot/24`r`nListenPort = $Port`r`n`r`n" +
            "[Peer]`r`nPublicKey = $hpub`r`nAllowedIPs = $Net.1/32`r`nEndpoint = $ep`r`nPersistentKeepalive = 25`r`n"
    [IO.File]::WriteAllText("$StateGuest\$Name.conf", $conf)
    InstallTunnel $StateGuest
    FwOpen   # this PC can host the game for the VLAN host too
    Write-Host "tunnel set up."
    Write-Host ""
}

# Start the joined tunnel again (after a restart or going idle).
function GuestUp {
    if (-not ((Test-Path "$StateGuest\invite") -and (TunnelUp))) { return }   # gone: GuestShow says what to do
    PubCheck $StateGuest
    $was = TunnelOn
    TunnelStarted $StateGuest
    if (-not $was) { Write-Host "started the tunnel again (same slot and key)"; Write-Host "" }
}

function GuestShow {
    if (-not (Test-Path "$StateGuest\invite")) { Fail 3 "not joined yet; run: $Self <invite code from the host>" }
    $hpub, $hport, $slot, $hv6, $hv4 = Dec "zsi1" (Get-Content "$StateGuest\invite" -Raw).Trim()
    if ($null -eq $script:V6) { PubCompare $StateGuest }
    $v6 = $script:V6; $v4 = $script:V4
    $st = PingSt "$Net.1"
    $hs = "none yet (the host must add your reply)"
    $line = Native { & $Wg show $Name latest-handshakes }
    if ($line) {
        $t = [int64](("$line" -split "\s+")[1])
        if ($t -gt 0) { $hs = "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $t)s ago" }
    }
    $ep = PickEp $hv6 $hv4 $hport $v6
    if (-not $ep) { $ep = "?" }
    Write-Host "== zs-vlan: this PC joined =="
    Write-Host "this PC   : $Net.$slot   (tunnel $Name`: $(TunnelState))"
    Write-Host "host      : $Net.1 via $ep  ($st)"
    Write-Host "handshake : $hs"
    AddrWarn $v6 $v4
    Write-Host ""
    if (-not (TunnelUp)) {
        Write-Host "the tunnel is gone (removed outside vlan_auto). Join again with the invite: $Self <invite>"
        Write-Host "or clean up with: $Self stop"
        Result "role=guest state=down ip=$Net.$slot"
        return
    }
    if (-not (TunnelOn)) {
        Write-Host "the tunnel is off ($(OffReason $StateGuest))."
        Write-Host "start it again: $Self   (once the host has started theirs)"
        Result "role=guest state=off ip=$Net.$slot"
        return
    }
    $reply = Enc "zsr1" "$slot $(Pub "$StateGuest\guest.key") $Port $v6 $v4"
    if ($st -eq "online") {
        Write-Host "connected. In the game: Comms Terminal -> Join ->  $Net.1"
        Clip "$Net.1"
    } else {
        if ($script:PubOld) { Write-Host "this PC's public address changed since your last reply, so the host needs the new one." }
        Write-Host "1. send this reply back to the host:"
        Write-Host ""
        Write-Host $reply
        Clip $reply
        Write-Host ""
        Write-Host "2. the host pastes it into vlan_auto (or the dedicated server console)"
        Write-Host "3. once connected, join in the game at  $Net.1"
    }
    Result "role=guest state=up ip=$Net.$slot game=$Net.1`:$GamePort host=$($st -replace ' ', '-') code=$reply"
}

function GuestWait {
    if ($Machine) { return }
    if (-not (TunnelOn)) { return }
    if ((PingSt "$Net.1") -eq "online") { return }
    Write-Host ""
    Write-Host "waiting for the host to add your reply (up to 2 min; Ctrl+C stops waiting, the tunnel stays)"
    if (WaitOnline "$Net.1" 120) {
        Write-Host ""
        Write-Host "online! In the game: Comms Terminal -> Join ->  $Net.1"
        Clip "$Net.1"
    } else {
        Write-Host "no answer from the host yet. Check that:"
        Write-Host "  - the host started their virtual LAN and pasted your reply (vlan_auto, or 'add <reply>' on the server console)"
        Write-Host "  - the host's public address didn't change: if it did, their vlan_auto shows a new invite for you"
        Write-Host "  - both PCs have IPv6 (https://test-ipv6.com); without it the IPv4 fallback fails behind CGNAT"
        Write-Host "rerun '$Self status' any time - it shows when the host answers."
        exit 4
    }
}

# ---------------------------------------------------------------- common

function Status {
    switch (Role) {
        "host" { HostShow }
        "guest" { GuestShow }
        default {
            Write-Host "this PC isn't in a virtual LAN."
            Write-Host "  host:  $Self host"
            Write-Host "  join:  $Self <invite code from the host>"
            Result "role=none state=down"
        }
    }
}

function Teardown([string]$dir) {
    WatchStop $dir
    if (TunnelUp) { & $WgExe /uninstalltunnelservice $Name; Start-Sleep 3; Write-Host "removed tunnel $Name" }
    if (Get-NetFirewallRule -Group "zs-vlan" -ErrorAction SilentlyContinue) { Remove-NetFirewallRule -Group "zs-vlan"; Write-Host "removed firewall rules (group zs-vlan)" }
    if (Test-Path "$dir\installed_wireguard") {
        winget uninstall --id WireGuard.WireGuard -e --silent | Out-Host
        Write-Host "uninstalled WireGuard (zs-vlan had installed it)"
    }
    Remove-Item $dir -Recurse -Force
    Write-Host "removed $dir"
}

function Stop {
    $did = $false
    foreach ($dir in @($StateHost, $StateGuest)) { if (Test-Path $dir) { Teardown $dir; $did = $true } }
    if (-not $did) {
        if (TunnelUp) { & $WgExe /uninstalltunnelservice $Name; Write-Host "removed tunnel $Name" }
        if (Get-NetFirewallRule -Group "zs-vlan" -ErrorAction SilentlyContinue) { Remove-NetFirewallRule -Group "zs-vlan"; Write-Host "removed firewall rules (group zs-vlan)" }
        else { Write-Host "nothing to remove." }
    }
    Write-Host "done."
    Result "role=none state=down"
}

# Start whichever role this PC has again, without prompts.
function Start-Role {
    switch (Role) {
        "host" { HostUp; HostShow }
        "guest" { GuestUp; GuestShow }
        default { Fail 3 "nothing to start: this PC isn't in a virtual LAN (host: $Self host   join: $Self <invite>)" }
    }
}

function Code([string]$c) {
    if ($c.StartsWith("zsi1.")) { GuestJoin $c; GuestShow; GuestWait }
    elseif ($c.StartsWith("zsr1.")) { HostAdd $c }
    else { Fail 1 "that isn't a zs-vlan code (invites start with zsi1., replies with zsr1.)" }
}

function Guided {
    switch (Role) {
        "host" { HostUp; HostLoop; return }
        "guest" { GuestUp; GuestShow; GuestWait; return }
    }
    if ($Machine) { Status; return }
    Write-Host "zs-vlan: a private virtual LAN for co-op over the internet (no accounts, no port forwarding)."
    Write-Host ""
    $pick = Read-Host "[h]ost a game for friends, or [j]oin a friend?"
    if ($pick -match '^[hH]') { HostUp; HostLoop }
    elseif ($pick -match '^[jJ]') { Code ((Read-Host "paste the invite code from the host") -replace '\s', '') }
    else { Fail 1 "nothing done." }
}

$Arg1 = if ($Argv.Count -gt 1) { $Argv[1] } else { "" }
$Arg2 = if ($Argv.Count -gt 2) { $Argv[2] } else { "" }
switch -regex ($Cmd) {
    '^$' { Guided; break }
    '^host$' {
        switch ($Arg1) {
            "" { HostUp; HostLoop }
            "add" { if (-not $Arg2) { Fail 1 "usage: $Self host add <reply>" }; HostAdd $Arg2 }
            "remove" { HostRemove $Arg2 }
            default { Fail 1 "usage: $Self host [add <reply> | remove <N>]" }
        }
        break
    }
    '^join$' { if (-not $Arg1) { Fail 1 "usage: $Self join <invite>" }; GuestJoin $Arg1; GuestShow; GuestWait; break }
    '^start$' { Start-Role; break }
    '^watch$' { Watch $(if ($Arg1 -match '^\d+$') { [int]$Arg1 } else { $IdleMin }); break }
    '^status$' { Status; break }
    '^stop$' { Stop; break }
    '^zs[ir]1\.' { Code $Cmd; break }
    default { Fail 1 "unknown command '$Cmd' (try: $Self help)" }
}
exit 0
