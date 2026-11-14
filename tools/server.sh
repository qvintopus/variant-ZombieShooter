#!/bin/sh
# The dedicated server launcher lives in the LAN Party addon; this keeps the old path working.
LANPARTY_SELF=${LANPARTY_SELF:-tools/server.sh} exec bash "$(dirname "$0")/../addons/lan_party/tools/server.sh" "$@"
