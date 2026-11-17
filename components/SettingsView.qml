import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../lib/Config.js" as Config
import "../lib/Recorder.js" as Recorder
import "../lib/Glyphs.js" as Glyphs

// Omarclip's settings: instant replay, video quality, capture, audio and
// where clips go. Keyboard-first: the panel forwards navigation here and
// this view keeps its own cursor; every row also works with the mouse.
Item {
  id: root

  property var service: null
  property color foreground: Commons.Color.foreground
  property color background: Commons.Color.background
  property color selectedBackground: Util.alpha(Commons.Color.foreground, 0.08)
  property color selectedText: Commons.Color.accent
  property string fontFamily: Style.font.menuFamily

  // Asks the panel to record a hotkey for an action.
  signal captureRequested(string action, string title, var current)

  readonly property var config: service ? service.config : null
  property int cursorIndex: 1

  // Fake bar for PanelSlider, which takes its colors from a bar object.
  readonly property QtObject sliderBar: QtObject {
    property color foreground: root.foreground
    property color background: root.background
  }

  readonly property var monitorChoices: {
    var list = ["focused"]
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (screens[i].name && list.indexOf(screens[i].name) === -1) list.push(screens[i].name)
    // A monitor in the config that is unplugged right now stays pickable.
    if (config && list.indexOf(config.monitor) === -1) list.push(config.monitor)
    return list
  }

  readonly property var choices: ({
    preset: { list: Config.PRESET_ORDER, label: function(v) { return Config.presetLabel(v) } },
    resolution: { list: Config.RESOLUTIONS, label: function(v) { return Config.resolutionLabel(v) } },
    fps: { list: Config.FRAMERATES, label: function(v) { return v + " fps" } },
    codec: { list: Config.CODECS, label: function(v) { return Config.CODEC_LABEL[v] || v } },
    monitor: { list: [], label: function(v) { return v === "focused" ? "Focused monitor" : v } },
    storage: { list: ["ram", "disk"], label: function(v) { return v === "disk" ? "Disk" : "RAM" } }
  })

  function choiceList(key) {
    return key === "monitor" ? monitorChoices : choices[key].list
  }

  readonly property var rows: [
    { type: "header", text: "INSTANT REPLAY" },
    { type: "toggle", key: "enabled", label: "Instant replay", description: "Keep recording into a buffer so a hotkey can save what just happened" },
    { type: "length", key: "length", label: "Replay length", description: "How far back a clip goes from the moment you press the hotkey" },
    { type: "hotkey", action: "save", label: "Save clip" },
    { type: "hotkey", action: "toggle", label: "Turn instant replay on/off" },
    { type: "hotkey", action: "open", label: "Open Omarclip" },
    { type: "header", text: "VIDEO QUALITY" },
    { type: "choice", key: "preset", label: "Quality", description: "Low, Medium and High set resolution, frame rate and bitrate; change any of them for Custom" },
    { type: "choice", key: "resolution", label: "Resolution", description: "Native records the monitor as it is; lower ones are scaled down, never up" },
    { type: "choice", key: "fps", label: "Frame rate", description: "" },
    { type: "slider", key: "bitrate", label: "Bitrate", description: "", min: Config.MIN_BITRATE, max: Config.MAX_BITRATE, unit: " Mbps" },
    { type: "choice", key: "codec", label: "Encoder", description: "H.264 plays everywhere; HEVC and AV1 look better at the same bitrate" },
    { type: "info", key: "estimate" },
    { type: "header", text: "CAPTURE" },
    { type: "choice", key: "monitor", label: "Monitor", description: "Focused: the monitor in focus when the buffer starts" },
    { type: "toggle", key: "cursor", label: "Record the cursor", description: "" },
    { type: "toggle", key: "systemAudio", label: "System audio", description: "Everything you hear: the game, music, calls" },
    { type: "toggle", key: "microphone", label: "Microphone", description: "Your default input" },
    { type: "toggle", key: "separateTracks", label: "Microphone on its own track", description: "Lets an editor balance your voice and the game apart" },
    { type: "header", text: "CLIPS" },
    { type: "folder", key: "folder", label: "Save clips to" },
    { type: "toggle", key: "organizeByApp", label: "A folder per app", description: "Clips/Cs2/Cs2 2026-11-16 21-04-11.mp4, named after the window in focus" },
    { type: "toggle", key: "notify", label: "Notify when a clip is saved", description: "With a preview; click it to watch the clip" },
    { type: "choice", key: "storage", label: "Keep the buffer in", description: "RAM is fastest and spares your SSD; Disk suits very long replays" },
    { type: "action", key: "openLast", label: "Watch the last clip" }
  ]

  function selectable(row) {
    return row && row.type !== "header" && row.type !== "info"
  }

  function reset() {
    cursorIndex = 0
    moveCursor(1)
    flick.contentY = 0
  }

  function moveCursor(delta) {
    var i = cursorIndex
    for (var steps = 0; steps < rows.length; steps++) {
      i = Math.max(0, Math.min(rows.length - 1, i + delta))
      if (selectable(rows[i])) {
        cursorIndex = i
        ensureVisible(i)
        return
      }
      if (i === 0 || i === rows.length - 1) return
    }
  }

  function ensureVisible(index) {
    var item = repeater.itemAt(index)
    if (!item) return
    var margin = Style.space(8)
    // Keep the header of the first section in view at the top.
    if (index <= 1) flick.contentY = 0
    else if (item.y < flick.contentY) flick.contentY = Math.max(0, item.y - margin)
    else if (item.y + item.height > flick.contentY + flick.height)
      flick.contentY = Math.min(flick.contentHeight - flick.height, item.y + item.height - flick.height + margin)
  }

  function cycle(key, delta) {
    service.setSetting(key, Config.step(choiceList(key), config[key], delta))
  }

  function adjust(delta) {
    var row = rows[cursorIndex]
    if (!row || !service || !config) return
    if (row.type === "slider") service.setSetting(row.key, Math.max(row.min, Math.min(row.max, currentBitrate() + delta * 5)))
    else if (row.type === "length") service.setSetting("length", Config.stepLength(config.length, delta))
    else if (row.type === "choice") cycle(row.key, delta)
    else if (row.type === "toggle") service.setSetting(row.key, delta > 0)
  }

  function activate() {
    var row = rows[cursorIndex]
    if (!row || !service || !config) return
    if (row.type === "toggle") service.setSetting(row.key, !config[row.key])
    else if (row.type === "choice") cycle(row.key, 1)
    else if (row.type === "length") service.setSetting("length", Config.stepLength(config.length, 1))
    else if (row.type === "hotkey") captureRequested(row.action, row.label, config.hotkeys[row.action])
    else if (row.type === "slider") service.setSetting(row.key, "auto")
    else if (row.type === "folder") service.openFolder()
    else if (row.type === "action" && row.key === "openLast") service.openLastClip()
  }

  function deleteCurrent() {
    var row = rows[cursorIndex]
    if (row && row.type === "hotkey" && service) service.assignHotkey(row.action, null)
    else if (row && row.type === "slider" && service) service.setSetting(row.key, "auto")
  }

  function valueText(row) {
    if (!config) return ""
    if (row.type === "choice") return "‹  " + choices[row.key].label(config[row.key]) + "  ›"
    if (row.type === "length") return "‹  " + Config.formatLength(config.length) + "  ›"
    if (row.type === "hotkey") {
      var hk = config.hotkeys[row.action]
      return hk ? hk.label : "Not set"
    }
    if (row.type === "folder") return Glyphs.folder
    if (row.type === "action") return Glyphs.play
    return ""
  }

  function rowDescription(row, hasCursor) {
    if (!config) return ""
    if (row.type === "hotkey") {
      var blocked = service ? service.blockedHotkeys.filter(function(b) { return b.name === row.action }) : []
      if (blocked.length) return "Taken by " + blocked[0].by + " · Enter pick other keys"
      // Always present so the row keeps its height; shown only under the cursor.
      return "Enter change · Del clear"
    }
    if (row.type === "slider") return config.bitrate === "auto"
      ? "Auto: follows resolution, frame rate and encoder · ←→ sets your own"
      : "Fixed by you · Enter goes back to Auto"
    if (row.type === "folder") return config.folder
    if (row.type === "action") {
      var c = service ? service.lastClip : null
      return c ? c.path.split("/").pop() : "No clip saved yet this session"
    }
    return row.description || ""
  }

  readonly property var quality: config && service
    ? Recorder.quality(config, service.monitorWidth, service.monitorHeight) : null

  function estimateText() {
    if (!config || !quality) return ""
    var size = Recorder.formatBytes(service.bufferBytes)
    var where = config.storage === "disk" ? "of disk" : "of RAM"
    var text = Glyphs.memory + "  A " + Config.formatLength(config.length) + " clip at "
      + quality.width + "×" + quality.height + " " + config.fps + " fps is about " + size
      + ", and the buffer holds that much " + where + ". "
      + quality.mbps + " Mbps in " + (Config.CODEC_LABEL[config.codec] || config.codec) + " "
      + Recorder.QUALITY_TEXT[quality.level]
    if (config.storage === "ram" && service.bufferBytes > 4e9) text += " Consider a lower bitrate, a shorter replay or Disk."
    return text
  }

  function scrollBy(pixels) {
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + pixels))
  }

  function currentBitrate() {
    return quality ? quality.mbps : (config && config.bitrate !== "auto" ? config.bitrate : 25)
  }

  function estimateWarns() {
    if (!config || !quality) return false
    return quality.level === "poor" || (config.storage === "ram" && service.bufferBytes > 4e9)
  }

  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: column.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

    Column {
      id: column
      width: flick.width
      spacing: Style.space(4)

      Repeater {
        id: repeater
        model: root.rows

        delegate: Loader {
          required property var modelData
          required property int index
          width: column.width
          sourceComponent: modelData.type === "header" ? headerRow
            : modelData.type === "info" ? infoRow
            : controlRow
        }
      }
    }
  }

  Component {
    id: headerRow

    Item {
      width: parent ? parent.width : 0
      height: headerText.implicitHeight + (index === 0 ? Style.space(2) : Style.space(12))

      PanelSectionHeader {
        id: headerText
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.bottom: parent.bottom
        text: modelData.text
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }
  }

  Component {
    id: infoRow

    Item {
      width: parent ? parent.width : 0
      height: infoText.implicitHeight + Style.space(10)

      Text {
        id: infoText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: root.estimateText()
        color: root.estimateWarns() ? Commons.Color.urgent : root.foreground
        opacity: root.estimateWarns() ? 0.9 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  Component {
    id: controlRow

    CursorSurface {
      id: row
      readonly property var entry: modelData
      readonly property int rowIndex: index
      hasCursor: root.cursorIndex === rowIndex
      foreground: root.foreground
      fill: root.selectedBackground
      width: parent ? parent.width : 0
      height: Math.max(Style.space(46), labels.implicitHeight + Style.space(16))

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: root.cursorIndex = row.rowIndex
        onClicked: function(mouse) {
          root.cursorIndex = row.rowIndex
          if (mouse.button === Qt.RightButton) {
            if (row.entry.type === "hotkey") root.deleteCurrent()
            else root.adjust(-1)
          } else if (row.entry.type !== "slider") root.activate()
        }
      }

      Column {
        id: labels
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.right: control.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.entry.label
          color: row.hasCursor ? root.selectedText : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.weight: Font.Medium
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          text: root.rowDescription(row.entry, row.hasCursor)
          color: row.entry.type === "hotkey" && text.indexOf("Taken by") === 0 ? Commons.Color.urgent : root.foreground
          opacity: row.entry.type !== "hotkey" ? 0.5
            : text.indexOf("Taken by") === 0 ? 1
            : row.hasCursor ? 0.5 : 0
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: row.entry.type === "folder" || row.entry.type === "action" ? Text.ElideMiddle : Text.ElideRight
        }
      }

      Item {
        id: control
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: row.entry.type === "slider" ? sliderRow.implicitWidth
          : (row.entry.type === "toggle" ? toggle.implicitWidth : valueLabel.implicitWidth)
        height: Math.max(Style.space(22), toggle.implicitHeight)

        ToggleSwitch {
          id: toggle
          visible: row.entry.type === "toggle"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          interactive: false
          checked: !!(root.config && row.entry.key && root.config[row.entry.key] === true)
          foreground: root.foreground
        }

        Row {
          id: sliderRow
          visible: row.entry.type === "slider"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          PanelSlider {
            id: slider
            width: Style.space(170)
            anchors.verticalCenter: parent.verticalCenter
            bar: root.sliderBar
            minimum: row.entry.min || 0
            maximum: row.entry.max || 100
            step: 5
            integer: true
            value: row.entry.type === "slider" ? root.currentBitrate() : 0
            onMoved: function(v) { root.cursorIndex = row.rowIndex }
            onReleased: function(v) { if (root.service) root.service.setSetting(row.entry.key, Math.round(v)) }

            // The slider takes wheel turns as changes; scrolling the list over
            // it would quietly set the bitrate. The wheel scrolls the list.
            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.NoButton
              onWheel: function(wheel) { root.scrollBy(-wheel.angleDelta.y) }
            }
          }

          Text {
            width: Style.space(104)
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: (root.config && root.config.bitrate === "auto" && !slider.dragging ? "Auto · " : "")
              + Math.round(slider.dragging ? slider.liveValue : slider.value) + (row.entry.unit || "")
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.features: { "tnum": 1 }
          }
        }

        Text {
          id: valueLabel
          visible: row.entry.type !== "toggle" && row.entry.type !== "slider"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.valueText(row.entry)
          color: row.hasCursor ? root.selectedText : root.foreground
          opacity: row.entry.type === "hotkey" && !(root.config && root.config.hotkeys[row.entry.action]) ? 0.45 : 0.85
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: row.entry.type === "hotkey"
        }
      }
    }
  }
}
