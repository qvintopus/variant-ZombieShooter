#!/usr/bin/env bash
# Old name, kept as an alias: vlan_auto.sh stop (removes everything zs-vlan made on this PC). See README.md.
exec "$(dirname "$0")/vlan_auto.sh" stop "$@"
