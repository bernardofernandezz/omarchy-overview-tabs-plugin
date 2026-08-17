pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  required property string label
  required property int count

  property bool selected: false
  property bool active: false
  property bool urgent: false

  signal clicked()

  readonly property bool hot: pointer.containsMouse
  readonly property color foreground: root.selected ? Color.menu.selectedText : Color.menu.text

  implicitWidth: content.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: Style.space(36)
  radius: Style.cornerRadius
  color: pointer.pressed
    ? Style.pressedFillFor(Color.menu.text, Color.accent, Color.urgent)
    : root.selected
      ? Style.selectedFillFor(Color.menu.text, Color.accent, Color.urgent)
      : root.hot
        ? Style.hoverFillFor(Color.menu.text, Color.accent, Color.urgent)
        : Style.normalFillFor(Color.menu.text, Color.accent, Color.urgent)
  borderSpec: root.hot
    ? Border.controlSpec("hover-cursor", Color.menu.text, Color.accent, Color.urgent)
    : Border.none()

  Behavior on color { ColorAnimation { duration: 110 } }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(8)

    Rectangle {
      visible: root.active || root.urgent
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(6)
      height: width
      radius: width / 2
      color: root.urgent ? Color.urgent : Color.accent
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      color: root.foreground
      opacity: root.count > 0 || root.selected || root.active ? 1 : 0.52
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.bodySmall
      font.weight: root.selected || root.active ? Font.DemiBold : Font.Normal
    }

    Rectangle {
      visible: root.count > 0
      anchors.verticalCenter: parent.verticalCenter
      width: countLabel.implicitWidth + Style.space(10)
      height: Math.max(Style.space(20), countLabel.implicitHeight + Style.space(4))
      radius: height / 2
      color: root.selected
        ? Util.alpha(Color.menu.selectedText, 0.16)
        : Util.alpha(Color.menu.text, 0.08)

      Text {
        id: countLabel
        anchors.centerIn: parent
        text: root.count
        color: root.foreground
        opacity: root.selected ? 1 : 0.7
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
      }
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    height: Math.max(1, Style.space(2))
    radius: height / 2
    color: Color.accent
    opacity: root.selected ? 1 : 0
    scale: root.selected ? 1 : 0.45

    Behavior on opacity { NumberAnimation { duration: 110 } }
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
