#!/bin/sh
# The virtual LAN script lives in the LAN Party addon; this keeps the old path working.
LANPARTY_SELF=${LANPARTY_SELF:-tools/vlan/vlan_auto.sh} exec bash "$(dirname "$0")/../../addons/lan_party/tools/vlan/vlan_auto.sh" "$@"
