# LAN Party settings for the PowerShell scripts (dot-sourced): fills $LP with every key=value in
#   1. the defaults below,
#   2. the addon's lan_party.cfg (two folders up from this file),
#   3. lan_party.cfg in this folder (a copy the game made, already merged),
#   4. lan_party.cfg next to the project's project.godot (the nearest folder above this one that has it),
#   5. $env:LANPARTY_CONFIG, when set (tests).
# Later ones win. The file is parsed, never run. Values are trimmed; '#' starts a comment.
$LP = @{
    prefix = "lanparty"; vlan_name = "lanparty"; vlan_net = "10.88.0"; vlan_port = "51820"; game_port = "7777"
    code_prefix = "lp"; game_title = "Godot game"; server_name = "Server"; max_players = "8"; idle_kick = "5"
    extra_settings = ""
}

function LpReadConfig([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8)) {
        $line = ($line -split '#', 2)[0]
        $at = $line.IndexOf("=")
        if ($at -lt 1) { continue }
        $key = $line.Substring(0, $at).Trim()
        if ($key -notmatch '^[a-z_][a-z0-9_]*$') { continue }
        $LP[$key] = $line.Substring($at + 1).Trim()
    }
}

# The folder above $dir (inclusive) that holds project.godot; "" if none.
function LpProjectDir([string]$dir) {
    $d = $dir
    while ($d) {
        if (Test-Path -LiteralPath (Join-Path $d "project.godot") -PathType Leaf) { return $d }
        $up = Split-Path $d -Parent
        if ($up -eq $d) { break }
        $d = $up
    }
    return ""
}

$LpVlanDir = $PSScriptRoot
$LpProject = LpProjectDir $LpVlanDir
LpReadConfig (Join-Path (Split-Path (Split-Path $LpVlanDir -Parent) -Parent) "lan_party.cfg")
LpReadConfig (Join-Path $LpVlanDir "lan_party.cfg")
if ($LpProject) { LpReadConfig (Join-Path $LpProject "lan_party.cfg") }
if ($env:LANPARTY_CONFIG) { LpReadConfig $env:LANPARTY_CONFIG }
