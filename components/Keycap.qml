import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A key drawn as a cap, optionally followed by what it does.
Row {
  id: cap

  property string keys: ""
  property string hint: ""
  property bool large: false
  property color foreground: Commons.Color.foreground
  property color tint: foreground
  property string fontFamily: Style.font.menuFamily

  spacing: Style.space(6)

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: capLabel.implicitWidth + Style.space(cap.large ? 18 : 8)
    implicitHeight: capLabel.implicitHeight + Style.space(cap.large ? 10 : 2)
    radius: Math.min(Style.cornerRadius, Style.space(cap.large ? 6 : 4))
    color: Util.alpha(cap.tint, cap.large ? 0.1 : 0.06)
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Util.alpha(cap.tint, cap.large ? 0.45 : 0.2)

    Text {
      id: capLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: cap.keys
      color: cap.tint
      opacity: 0.9
      font.family: cap.fontFamily
      font.pixelSize: cap.large ? Style.font.title : Style.font.caption
      font.bold: true
    }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    visible: cap.hint !== ""
    textFormat: Text.PlainText
    text: cap.hint
    color: cap.foreground
    opacity: 0.5
    font.family: cap.fontFamily
    font.pixelSize: Style.font.caption
  }
}
