# Starts a headless dedicated co-op server from the project folder, on Windows. Linux: tools/server.sh
#   tools\server.cmd [--vlan] [--port N] [--max-players 2..8] [--save-dir PATH] [--name NAME] [--status SECONDS] [--idle-kick MIN]
# --vlan (or -Vlan): also host the zs-vlan virtual LAN. Asks for admin, runs tools\vlan\vlan_auto.ps1 host
#   first, and the console then takes invite / add / guests / revoke.
# Type "help" in the server window for its commands; "stop" saves and quits.
# Godot binary: $env:GODOT, else godot on the PATH, else a Godot_v*_win64_console.exe next to the project
# folder (the console build: the plain .exe has no console to type into or print to).
$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Pass = @()
$Vlan = $false
foreach ($a in $args) {
    if ("$a" -in @("--vlan", "-Vlan", "-vlan")) { $Vlan = $true; $Pass += "--vlan" } else { $Pass += "$a" }
}

if ($Vlan) {
    $me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $a = @("-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
        foreach ($x in $Pass) { $a += "`"$x`"" }
        Start-Process powershell -Verb RunAs -ArgumentList $a
        exit 10   # server.cmd: the admin window took over
    }
}

$Godot = $env:GODOT
if (-not $Godot) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { $Godot = $cmd.Source }
}
if (-not $Godot) {
    $found = Get-ChildItem (Split-Path $Root -Parent) -Filter "Godot_v*_win64_console.exe" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
    if ($found) { $Godot = $found.FullName }
}
if (-not $Godot) {
    $gui = Get-ChildItem (Split-Path $Root -Parent) -Filter "Godot_v*_win64.exe" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
    if ($gui) {
        Write-Host "server: only the GUI Godot ($($gui.Name)) was found; the server console needs the _console.exe next to it (it comes in the same Godot zip)."
        $Godot = $gui.FullName
    }
}
if (-not $Godot) {
    Write-Host "server: no Godot found. Put Godot_v*_win64_console.exe next to the project folder, or set GODOT=C:\path\to\Godot_console.exe"
    exit 1
}

Set-Location $Root
if ($Vlan) {
    # --machine: shows the invite but doesn't stop to ask for replies - paste those into the server console
    & (Join-Path $PSScriptRoot "vlan\vlan_auto.ps1") host --machine
    if ($LASTEXITCODE -ne 0) { Write-Host "server: the virtual LAN didn't come up (see above); fix it or start without --vlan"; exit 1 }
    Write-Host ""
}
if (-not (Test-Path (Join-Path $Root ".godot\imported"))) {
    Write-Host "server: first start, importing the project..."
    & $Godot --headless --path . --import | Out-Null
}
& $Godot --headless --path . -- --server @Pass
exit $LASTEXITCODE
