import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../lib/Hotkeys.js" as Hotkeys

// Overlay that records a new hotkey for one action. The panel sends it every
// key while it is open: plain Enter saves, Backspace or Delete clears, Esc
// leaves, anything else is a candidate.
Item {
  id: recorder

  property bool opened: false
  property string title: ""
  property var current: null
  // function(candidate) -> { kind: "hyprland" | "omarclip", description } | null
  property var conflictCheck: null

  property var candidate: null
  property var held: []
  property string note: ""
  property bool refused: false

  property color background: Commons.Color.background
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.menuFamily

  signal saved(var hotkey)
  signal canceled()

  visible: opened
  onOpenedChanged: {
    candidate = null
    held = []
    note = ""
    refused = false
  }

  readonly property var shownParts: candidate ? candidate.label.split("+")
    : held.length ? held.concat(["…"])
    : current ? current.label.split("+") : []

  function handleKey(event) {
    if (!opened) return false
    var bare = (event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0
    if (bare && event.key === Qt.Key_Escape) canceled()
    else if (bare && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      if (candidate && !refused) saved({ keys: candidate.keys, label: candidate.label })
    } else if (bare && (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete)) saved(null)
    else consider(Hotkeys.capture(event.key, event.modifiers, event.nativeScanCode))
    return true
  }

  function handleKeyRelease(event) {
    if (opened && Hotkeys.isModifier(event.key) && !candidate) held = []
    return opened
  }

  function consider(result) {
    if (result.phase === "held") {
      held = result.labels
      return
    }
    held = []
    if (result.phase === "rejected") {
      candidate = null
      refused = true
      note = result.why
      return
    }
    candidate = result
    var clash = conflictCheck ? conflictCheck(result) : null
    refused = !!clash && clash.kind === "hyprland"
    note = !clash ? ""
      : refused ? "Hyprland already uses it for “" + clash.description + "”"
      : "Taken from “" + clash.description + "”, which is left without a hotkey"
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(recorder.background, 0.75)

    MouseArea {
      anchors.fill: parent
      onClicked: recorder.canceled()
    }
  }

  Rectangle {
    id: sheet
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(40), Style.space(400))
    height: body.implicitHeight + Style.space(36)
    radius: Style.cornerRadius
    color: recorder.background
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Util.alpha(recorder.refused ? recorder.urgent : recorder.accent, 0.8)

    MouseArea { anchors.fill: parent }

    Column {
      id: body
      anchors.fill: parent
      anchors.margins: Style.space(18)
      spacing: Style.space(14)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: recorder.title
        color: recorder.foreground
        font.family: recorder.fontFamily
        font.pixelSize: Style.font.subtitle
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      Item {
        width: parent.width
        height: Style.space(56)

        Row {
          anchors.centerIn: parent
          spacing: Style.space(6)
          opacity: recorder.candidate || recorder.held.length ? 1 : 0.45

          Repeater {
            model: recorder.shownParts

            Keycap {
              required property string modelData
              keys: modelData
              large: true
              foreground: recorder.foreground
              tint: recorder.refused ? recorder.urgent : recorder.candidate ? recorder.accent : recorder.foreground
              fontFamily: recorder.fontFamily
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: recorder.shownParts.length === 0
          textFormat: Text.PlainText
          text: "Press the keys"
          color: recorder.foreground
          opacity: 0.45
          font.family: recorder.fontFamily
          font.pixelSize: Style.font.title
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: recorder.note
          || (recorder.candidate ? "Enter to keep it"
          : recorder.current ? "Now set to this. Press other keys to change it"
          : "F-keys, PgUp or PgDn alone, or any key with Super, Ctrl or Alt")
        color: recorder.refused ? recorder.urgent : recorder.foreground
        opacity: recorder.refused ? 1 : 0.6
        font.family: recorder.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(14)

        Keycap { keys: "Enter"; hint: "keep"; foreground: recorder.foreground; fontFamily: recorder.fontFamily; opacity: recorder.candidate && !recorder.refused ? 1 : 0.4 }
        Keycap { keys: "Backspace"; hint: "no hotkey"; foreground: recorder.foreground; fontFamily: recorder.fontFamily }
        Keycap { keys: "Esc"; hint: "back"; foreground: recorder.foreground; fontFamily: recorder.fontFamily }
      }
    }
  }
}
