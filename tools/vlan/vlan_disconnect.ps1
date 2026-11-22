# Old name, kept as an alias: vlan_auto.ps1 stop (removes everything zs-vlan made on this PC). See README.md.
#   powershell -ExecutionPolicy Bypass -File vlan_disconnect.ps1
& (Join-Path $PSScriptRoot "vlan_auto.ps1") stop
exit $LASTEXITCODE
