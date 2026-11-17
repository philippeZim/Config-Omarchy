#!/usr/bin/env bash
# Puts Omarchy's own Bluetooth menu back.
set -euo pipefail

source "${OMARCHY_SETUP:-$(dirname "${BASH_SOURCE[0]}")/../..}/lib/plugins.sh"
remove_plugin setup.bluetooth
