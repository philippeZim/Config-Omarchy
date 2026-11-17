#!/usr/bin/env bash
# Keeps Omarchy's Bluetooth menu in the bar when Bluetooth is off.
#
# Omarchy turns Bluetooth off with an rfkill soft block. On this Dell laptop
# that block also powers the adapter down completely, so it disappears from the
# system, and Omarchy's menu hides itself when there is no adapter: once off,
# there was no switch left to turn Bluetooth back on.
#
# This installs a copy of the menu that stays visible without an adapter, shows
# it as off, and lets the switch turn it on again.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${OMARCHY_SETUP:-$HERE/../..}/lib/plugins.sh"

if ! systemctl is-enabled --quiet bluetooth.service; then
  sudo systemctl enable --now bluetooth.service
fi

build="$(begin_clone panels/bluetooth setup.bluetooth "Bluetooth (always visible)" omarchy.bluetooth)"
panel="$build/Panel.qml"

# Always in the bar, with the "off" icon and wording while the adapter is gone.
patch_clone "$panel" '  visible: adapter !== null' '  visible: true'
patch_clone "$panel" '    if (!adapter) return ""' '    if (!adapter) return "󰂲"'
patch_clone "$panel" 'if (!adapter) return Commons.I18n.t("bluetooth.noAdapter")' \
  'if (!adapter) return Commons.I18n.t("bluetooth.turnedOff")'
patch_clone "$panel" '!root.adapter ? Commons.I18n.t("bluetooth.noBluetoothAdapter")' \
  '!root.adapter ? Commons.I18n.t("bluetooth.turnOnToScan")'

# The switch stays, and turns Bluetooth on when there is no adapter.
patch_clone "$panel" '            visible: !!root.adapter
            checked: !!root.adapter && root.adapter.enabled' \
  '            checked: !!root.adapter && root.adapter.enabled'
patch_clone "$panel" '    if (!adapter) return
    Quickshell.execDetached(["omarchy-bluetooth-power", adapter.enabled ? "off" : "on"])' \
  '    Quickshell.execDetached(["omarchy-bluetooth-power", adapter && adapter.enabled ? "off" : "on"])'

finish_clone "$build" setup.bluetooth
