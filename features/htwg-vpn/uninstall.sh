#!/usr/bin/env bash
# Removes the HTWG-VPN connection, its saved secrets, the command and the
# network panel copy (Omarchy's own panel takes its place again).
set -euo pipefail

source "${OMARCHY_SETUP:-$(dirname "${BASH_SOURCE[0]}")/../..}/lib/plugins.sh"
remove_plugin setup.network

if nmcli -t -f NAME connection show | grep -qxF "HTWG-VPN"; then
  nmcli connection delete id "HTWG-VPN" >/dev/null
fi

secret-tool clear service htwg-vpn 2>/dev/null || true
rm -f "$HOME/.local/bin/htwg-vpn" "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-setup/htwg-vpn.profile"
