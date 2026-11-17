import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "plugin" as Omarclip

// Stand-in for omarchy-shell, so the plugin runs in a Quickshell of its own.
// dev/run puts this file next to links to the plugin and to Omarchy's
// Commons and Ui, which makes the panel look exactly as in the real shell.
ShellRoot {
  id: host

  readonly property var manifest: ({ id: "io.github.gelzinn.omarclip" })
  // Hands-off by default: the panel opens on a screen you're not looking at
  // and leaves the keyboard alone. OMARCLIP_DEV_FOCUS=1 for hands-on.
  readonly property bool handsOn: Quickshell.env("OMARCLIP_DEV_FOCUS") === "1"
  readonly property var sideScreen: {
    var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    return Quickshell.screens.filter(function(s) { return s.name !== focused })[0] || null
  }

  QtObject {
    id: shellApi
    function summon(id, payload) { panel.open(payload); return true }
    function hide(id) { panel.close(); return true }
    function toggle(id, payload) { return panel.opened ? hide(id) : summon(id, payload) }
    function isPluginOpen(id) { return panel.opened }
    function serviceFor(id) { return service }
    function updateEntryInline(id, settings) { return false }
  }

  Omarclip.Service {
    id: service
    shell: shellApi
    manifest: host.manifest
    appId: "omarclip-dev"
    hotkeysEnabled: Quickshell.env("OMARCLIP_DEV_HOTKEYS") === "1"
  }

  Omarclip.Panel {
    id: panel
    shell: shellApi
    service: service
    manifest: host.manifest
    grabKeyboard: host.handsOn
    targetScreen: host.handsOn ? null : host.sideScreen
  }

  IpcHandler {
    target: "omarclip-dev-host"

    // A key press for the panel, like "Down", "ctrl+s" or "alt+F10".
    function press(spec: string): string {
      var parts = spec.split("+")
      var name = parts.pop()
      var modBits = { ctrl: Qt.ControlModifier, shift: Qt.ShiftModifier, alt: Qt.AltModifier, super: Qt.MetaModifier }
      var mods = parts.reduce(function(bits, m) { return bits | (modBits[m.toLowerCase()] || 0) }, 0)
      // [Qt key, XKB keycode]
      var known = {
        Return: [Qt.Key_Return, 36], Escape: [Qt.Key_Escape, 9], Tab: [Qt.Key_Tab, 23], Space: [Qt.Key_Space, 65],
        Backspace: [Qt.Key_Backspace, 22], Delete: [Qt.Key_Delete, 119], Up: [Qt.Key_Up, 111], Down: [Qt.Key_Down, 116],
        Left: [Qt.Key_Left, 113], Right: [Qt.Key_Right, 114], PageUp: [Qt.Key_PageUp, 112], PageDown: [Qt.Key_PageDown, 117],
        F10: [Qt.Key_F10, 76], s: [Qt.Key_S, 39], o: [Qt.Key_O, 32], z: [Qt.Key_Z, 52]
      }
      var key = known[name]
      if (!key) return "unknown key: " + name
      var event = { key: key[0], modifiers: mods, text: "", nativeScanCode: key[1], accepted: false }
      return panel.handleKey(event) ? "handled" : "ignored"
    }

    function inspect(): string {
      return JSON.stringify({
        panel: panel.opened,
        screen: host.sideScreen ? host.sideScreen.name : "",
        status: service.status,
        detail: service.statusDetail,
        notice: service.notice,
        recorder: panel.captureAction ? panel.captureState() : null
      })
    }
  }
}
