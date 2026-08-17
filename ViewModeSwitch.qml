pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  required property string mode
  required property int workspaceCount
  required property int recentCount

  signal modeRequested(string mode)

  readonly property int inset: Style.space(3)
  readonly property real segmentWidth: (width - inset * 2) / 2

  implicitWidth: Style.space(238)
  implicitHeight: Style.space(36)
  radius: Style.cornerRadius
  color: Style.normalFillFor(Color.menu.text, Color.accent, Color.urgent)
  borderSpec: Border.flat(
    Util.alpha(Color.menu.text, 0.14), Math.max(1, Style.spacing.hairline))

  Rectangle {
    id: selection
    x: root.inset + (root.mode === "recent" ? root.segmentWidth : 0)
    y: root.inset
    width: root.segmentWidth
    height: root.height - root.inset * 2
    radius: Math.max(0, root.radius - root.inset)
    color: Style.selectedFillFor(Color.menu.text, Color.accent, Color.urgent)

    Behavior on x {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
  }

  Rectangle {
    x: selection.x + Style.space(12)
    anchors.bottom: selection.bottom
    width: Math.max(Style.space(20), selection.width - Style.space(24))
    height: Math.max(1, Style.space(2))
    radius: height / 2
    color: Color.accent
  }

  Row {
    anchors.fill: parent
    anchors.margins: root.inset

    ModeButton {
      width: root.segmentWidth
      height: parent.height
      label: "Workspaces"
      count: root.workspaceCount
      selected: root.mode === "workspaces"
      onClicked: root.modeRequested("workspaces")
    }

    ModeButton {
      width: root.segmentWidth
      height: parent.height
      label: "Recent"
      count: root.recentCount
      selected: root.mode === "recent"
      onClicked: root.modeRequested("recent")
    }
  }

  component ModeButton: Item {
    id: button

    required property string label
    required property int count
    required property bool selected

    signal clicked()

    readonly property bool hot: pointer.containsMouse

    Rectangle {
      anchors.fill: parent
      radius: Math.max(0, root.radius - root.inset)
      color: Style.hoverFillFor(Color.menu.text, Color.accent, Color.urgent)
      opacity: button.hot && !button.selected ? 1 : 0

      Behavior on opacity { NumberAnimation { duration: 110 } }
    }

    Row {
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: button.label
        color: button.selected ? Color.menu.selectedText : Color.menu.text
        opacity: button.selected ? 1 : (button.hot ? 0.92 : 0.72)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        font.weight: button.selected ? Font.DemiBold : Font.Normal

        Behavior on opacity { NumberAnimation { duration: 110 } }
        Behavior on color { ColorAnimation { duration: 110 } }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: button.count
        color: button.selected ? Color.menu.selectedText : Color.muted
        opacity: button.selected ? 0.88 : 0.62
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold

        Behavior on opacity { NumberAnimation { duration: 110 } }
        Behavior on color { ColorAnimation { duration: 110 } }
      }
    }

    MouseArea {
      id: pointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
  }
}
