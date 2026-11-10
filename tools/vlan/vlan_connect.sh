#!/usr/bin/env bash
# Old name, kept as an alias: vlan_auto.sh join <invite> (no invite: status). See README.md.
if [ -n "${1:-}" ]; then exec "$(dirname "$0")/vlan_auto.sh" join "$@"; fi
exec "$(dirname "$0")/vlan_auto.sh" status
