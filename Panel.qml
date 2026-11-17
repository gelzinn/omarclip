import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "components"
import "lib/Config.js" as Config
import "lib/Glyphs.js" as Glyphs

// Omarclip's overlay, the Alt+Z of this setup: instant replay status, a save
// button and every setting, over a dimmed screen and styled with the [menu]
// surface tokens like the launcher and the clipboard. Arrows move and
// change values, Enter activates, Esc closes.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var service: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "io.github.gelzinn.omarclip"

  property bool opened: false
  // Hosts can open the panel without taking the keyboard or pick its screen
  // (the dev host does both, so tests never steal the session's input).
  property bool grabKeyboard: true
  property var targetScreen: null

  // The [menu] surface colors. Always through the Commons namespace: a bare
  // `Color` can resolve to a Qt type of the same name instead of the theme.
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(40), Style.font.heading + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Math.max(Style.space(22), Style.font.caption + Style.space(12))
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(720), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(700), panel.height - Style.gapsOut * 2)

  readonly property var config: service ? service.config : null
  readonly property string status: service ? service.status : "off"

  function open(payloadJson) {
    var wasOpen = opened
    opened = true
    if (!wasOpen) settingsView.reset()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (capture.opened) cancelCapture()
    opened = false
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  onOpenedChanged: if (service) service.panelOpen = opened
  onServiceChanged: if (service) service.panelOpen = opened

  // The shell unloads the panel when it closes; never leave the hotkeys
  // suspended or the service thinking the panel is still up.
  Component.onDestruction: {
    if (!service) return
    if (captureAction) service.resumeHotkeys()
    service.panelOpen = false
  }

  property string captureAction: ""

  function startCapture(action, title, current) {
    if (!service) return
    keyCatcher.forceActiveFocus()
    captureAction = action
    capture.title = title
    capture.current = current
    capture.opened = true
    service.suspendHotkeys()
  }

  function finishCapture(hotkey) {
    if (service && captureAction) service.assignHotkey(captureAction, hotkey)
    capture.opened = false
    captureAction = ""
    if (service) service.resumeHotkeys()
  }

  function captureState() {
    return { candidate: capture.candidate ? capture.candidate.label : "", note: capture.note, refused: capture.refused }
  }

  function cancelCapture() {
    capture.opened = false
    captureAction = ""
    if (service) service.resumeHotkeys()
  }

  function handleKey(event) {
    if (capture.opened) {
      capture.handleKey(event)
      return true
    }
    var key = event.key
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (key === Qt.Key_Escape) dismiss()
    else if (key === Qt.Key_Up || key === Qt.Key_Backtab) settingsView.moveCursor(-1)
    else if (key === Qt.Key_Down || key === Qt.Key_Tab) settingsView.moveCursor(1)
    else if (key === Qt.Key_PageUp) settingsView.moveCursor(-6)
    else if (key === Qt.Key_PageDown) settingsView.moveCursor(6)
    else if (key === Qt.Key_Left) settingsView.adjust(-1)
    else if (key === Qt.Key_Right) settingsView.adjust(1)
    else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) settingsView.activate()
    else if (key === Qt.Key_Delete || key === Qt.Key_Backspace) settingsView.deleteCurrent()
    else if (ctrl && key === Qt.Key_S) { if (service) service.saveClip(0) }
    else if (ctrl && key === Qt.Key_O) { if (service) service.openFolder() }
    else return false
    return true
  }

  // Ticks the "buffered" counter while the panel is open.
  property double now: Date.now()

  Timer {
    interval: 500
    repeat: true
    running: root.opened && root.status === "running"
    triggeredOnStart: true
    onTriggered: root.now = Date.now()
  }

  readonly property string statusText: {
    var s = service
    if (!s) return ""
    var n = now
    if (s.status === "running") {
      var held = s.bufferedSeconds()
      var full = held >= s.config.length
      return "Recording " + s.recordingMonitor + " · " + (full ? "last " + Config.formatLength(s.config.length) + " ready"
        : Config.formatLength(held) + " of " + Config.formatLength(s.config.length) + " buffered")
    }
    if (s.status === "starting") return "Starting…"
    if (s.status === "waiting") return "Waiting · " + s.statusDetail
    if (s.status === "error") return "Stopped · " + s.statusDetail
    return "Off"
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarclip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened && root.grabKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { event.accepted = root.handleKey(event) }
        Keys.onReleased: function(event) {
          if (capture.opened) {
            capture.handleKeyRelease(event)
            event.accepted = true
          }
        }

        Item {
          id: content
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset

          Item {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.headerHeight

            Text {
              id: logo
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.status === "running" || root.status === "starting" ? Glyphs.app : Glyphs.off
              color: root.status === "running" ? root.selectedText : root.foreground
              opacity: root.status === "running" ? 1 : 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            Column {
              anchors.left: logo.right
              anchors.leftMargin: Style.space(12)
              anchors.right: saveButton.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Instant replay"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                elide: Text.ElideRight
              }

              Row {
                spacing: Style.space(6)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(7)
                  height: width
                  radius: width / 2
                  color: root.status === "running" ? Commons.Color.urgent
                    : (root.status === "error" ? Commons.Color.urgent : Util.alpha(root.foreground, 0.35))
                  opacity: root.status === "running" ? (pulse.on ? 1 : 0.35) : 1

                  Timer {
                    id: pulse
                    property bool on: true
                    interval: 900
                    repeat: true
                    running: root.opened && root.status === "running"
                    onTriggered: on = !on
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.statusText
                  color: root.status === "error" ? Commons.Color.urgent : root.foreground
                  opacity: 0.65
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.features: { "tnum": 1 }
                }
              }
            }

            Button {
              id: saveButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              iconText: root.service && root.service.saving ? Glyphs.save : Glyphs.rec
              iconSize: Style.font.title
              verticalPadding: Style.space(5)
              enabled: root.status === "running"
              opacity: enabled ? 1 : 0.4
              text: root.service && root.service.saving ? "Saving…" : "Save clip"
              tooltipText: root.config && root.config.hotkeys.save
                ? "Save the last " + Config.formatLength(root.config.length) + " (" + root.config.hotkeys.save.label + " anywhere, Ctrl+S here)"
                : "Save the last " + (root.config ? Config.formatLength(root.config.length) : "") + " (Ctrl+S)"
              onClicked: if (root.service) root.service.saveClip(0)
            }
          }

          SettingsView {
            id: settingsView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.topMargin: root.contentSpacing
            anchors.bottom: footer.top
            anchors.bottomMargin: root.contentSpacing
            service: root.service
            foreground: root.foreground
            background: root.background
            selectedBackground: root.selectedBackground
            selectedText: root.selectedText
            fontFamily: root.fontFamily
            onCaptureRequested: function(action, title, current) { root.startCapture(action, title, current) }
          }

          Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.footerHeight

            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(14)
              visible: !(root.service && root.service.notice)

              Keycap { keys: "↑↓"; hint: "move"; foreground: root.foreground; fontFamily: root.fontFamily }
              Keycap { keys: "←→"; hint: "change"; foreground: root.foreground; fontFamily: root.fontFamily }
              Keycap { keys: "Ctrl+S"; hint: "save clip"; foreground: root.foreground; fontFamily: root.fontFamily }
              Keycap { keys: "Ctrl+O"; hint: "clips folder"; foreground: root.foreground; fontFamily: root.fontFamily }
              Keycap { keys: "Esc"; hint: "close"; foreground: root.foreground; fontFamily: root.fontFamily }
            }

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: !!(root.service && root.service.notice)
              textFormat: Text.PlainText
              text: root.service ? root.service.notice : ""
              color: root.service && root.service.noticeKind === "error" ? Commons.Color.urgent : root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }
        }

        KeyRecorder {
          id: capture
          anchors.fill: parent
          background: root.background
          foreground: root.foreground
          fontFamily: root.fontFamily
          conflictCheck: function(hotkey) { return root.service ? root.service.hotkeyConflict(hotkey, root.captureAction) : null }
          onSaved: function(hotkey) { root.finishCapture(hotkey) }
          onCanceled: root.cancelCapture()
        }
      }
    }
  }
}
