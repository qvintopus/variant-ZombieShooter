#!/usr/bin/env bash
# Old name, kept as an alias: vlan_auto.sh host [add <reply> | remove <N>]. See README.md.
exec "$(dirname "$0")/vlan_auto.sh" host "$@"
