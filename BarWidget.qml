import QtQuick
import qs.Commons
import qs.Ui
import "lib/Config.js" as Config
import "lib/Glyphs.js" as Glyphs

// Bar button: shows whether instant replay is recording and flashes when a
// clip is saved. Click opens the settings, right-click saves a clip,
// middle-click turns instant replay on or off.
BarWidget {
  id: root
  moduleName: "io.github.gelzinn.omarclip"

  property var service: null

  readonly property string status: service ? service.status : "off"
  readonly property bool problem: status === "error"
  property bool flash: false

  function resolveService() {
    if (service) return
    var host = bar && bar.shell
    if (host && typeof host.serviceFor === "function") service = host.serviceFor(moduleName)
    if (!service) serviceRetry.restart()
  }

  onBarChanged: resolveService()
  Component.onCompleted: resolveService()

  // The service can finish loading a moment after the widget.
  Timer {
    id: serviceRetry
    interval: 500
    onTriggered: root.resolveService()
  }

  Connections {
    target: root.service
    function onClipSaved() {
      root.flash = true
      flashTimer.restart()
    }
  }

  Timer {
    id: flashTimer
    interval: 1600
    onTriggered: root.flash = false
  }

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.flash ? Glyphs.saved
      : (root.service && root.service.saving ? Glyphs.save
      : (root.status === "running" || root.status === "starting" ? Glyphs.app : Glyphs.off))
    active: root.problem || root.flash
    opacity: root.status === "off" || root.status === "waiting" ? 0.55 : 1
    tooltipText: {
      var s = root.service
      if (!s) return "Omarclip"
      var save = s.config.hotkeys.save ? " · " + s.config.hotkeys.save.label + " saves" : ""
      if (s.status === "running") return "Instant replay · last " + Config.formatLength(s.config.length) + save + " · right-click to save"
      if (s.status === "starting") return "Instant replay is starting…"
      if (s.status === "waiting") return "Instant replay is waiting: " + s.statusDetail
      if (s.status === "error") return "Instant replay stopped: " + s.statusDetail
      return "Instant replay is off · middle-click to turn on"
    }

    onPressed: function(b) {
      var s = root.service
      if (!s) return
      if (b === Qt.RightButton) s.saveClip(0)
      else if (b === Qt.MiddleButton) s.toggleEnabled()
      else s.togglePanel()
    }
  }
}
