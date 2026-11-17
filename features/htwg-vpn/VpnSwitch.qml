import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// HTWG-VPN on/off row for the network panel. Added by Omarchy_Setup; the
// connecting itself is done by ~/.local/bin/htwg-vpn.
Toggle {
  id: root

  property var bar
  readonly property string tool: Quickshell.env("HOME") + "/.local/bin/htwg-vpn"

  // What NetworkManager reports, and what a click in flight is heading for.
  property bool active: false
  property bool busy: false
  property bool wanted: false

  label: "HTWG-VPN"
  description: busy ? (wanted ? "Connecting…" : "Disconnecting…") : (active ? "Connected" : "Off")
  checked: busy ? wanted : active
  foreground: bar ? bar.foreground : foreground
  fontFamily: bar ? bar.fontFamily : fontFamily

  onClicked: {
    if (busy) return
    wanted = !active
    busy = true
    action.command = [tool, wanted ? "up" : "down"]
    action.running = true
  }

  Process {
    id: action
    onExited: {
      root.busy = false
      if (!status.running) status.running = true
    }
  }

  Process {
    id: status
    command: [root.tool, "status"]
    stdout: StdioCollector {
      onStreamFinished: root.active = text.trim() === "on"
    }
  }

  Timer {
    interval: 3000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!status.running && !root.busy) status.running = true
  }
}
