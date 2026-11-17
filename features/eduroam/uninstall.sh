#!/usr/bin/env bash
# Removes the eduroam connection and the certificate the installer saved.
set -euo pipefail

if nmcli -t -f NAME connection show | grep -qx eduroam; then
  nmcli connection delete id eduroam
fi
rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/cat_installer"
