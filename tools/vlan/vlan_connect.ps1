# Old name, kept as an alias: vlan_auto.ps1 join <invite> (no invite: status). See README.md.
#   powershell -ExecutionPolicy Bypass -File vlan_connect.ps1 [<invite>]
param([string]$Invite = "")
if ($Invite) { & (Join-Path $PSScriptRoot "vlan_auto.ps1") join $Invite } else { & (Join-Path $PSScriptRoot "vlan_auto.ps1") status }
exit $LASTEXITCODE
