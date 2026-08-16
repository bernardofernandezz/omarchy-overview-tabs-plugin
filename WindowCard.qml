pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Ui

Item {
  id: root

  required property int index
  required property var toplevel
  required property string appId
  required property string appName
  required property string title
  required property string iconSource
  required property string workspaceName
  required property string monitorName

  property bool selected: false
  property bool urgent: false
  property bool captureEnabled: false
  property bool showMonitor: false
  property real previewAspect: 1.6

  signal hovered(int index)
  signal activated(int index)
  signal wheelRequested(real delta)

  readonly property bool hot: pointer.containsMouse
  readonly property bool previewAvailable: preview.hasContent
  readonly property real footerHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.space(24))

  scale: selected ? 1.012 : (hot ? 1.008 : 1.0)
  transformOrigin: Item.Center

  Behavior on scale {
    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
  }

  BorderSurface {
    id: surface
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.selected ? Color.menu.selectedBackground : Color.menu.background
    borderSpec: root.selected
      ? Border.controlSpec("focus", Color.menu.text, Color.accent, Color.urgent)
      : (root.hot
        ? Border.controlSpec("hover", Color.menu.text, Color.accent, Color.urgent)
        : Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(1))))

    Rectangle {
      id: previewFrame
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: footer.top
      anchors.margins: Math.max(1, surface.borderTop)
      color: Util.alpha(Color.background, 0.72)
      clip: true

      ScreencopyView {
        id: preview
        captureSource: root.captureEnabled && root.toplevel && root.toplevel.wayland
          ? root.toplevel.wayland : null
        paintCursor: false
        live: false
        visible: hasContent
        anchors.centerIn: parent

        readonly property real imageAspect: sourceSize.height > 0
          ? sourceSize.width / sourceSize.height : root.previewAspect
        width: imageAspect > parent.width / Math.max(1, parent.height)
          ? parent.width : parent.height * imageAspect
        height: imageAspect > parent.width / Math.max(1, parent.height)
          ? parent.width / imageAspect : parent.height
      }

      Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(36), Style.space(260))
        spacing: Style.space(12)
        visible: !preview.hasContent

        IconImage {
          anchors.horizontalCenter: parent.horizontalCenter
          implicitSize: Math.min(Style.space(72), previewFrame.height * 0.32)
          width: implicitSize
          height: implicitSize
          source: root.iconSource
          asynchronous: true
          opacity: 0.9
        }

        Text {
          width: parent.width
          text: root.appName
          color: Color.menu.text
          opacity: 0.66
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }

      Rectangle {
        visible: root.urgent
        width: Style.space(7)
        height: width
        radius: width / 2
        color: Color.urgent
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(10)
      }
    }

    Item {
      id: footer
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: root.footerHeight

      IconImage {
        id: appIcon
        anchors.left: parent.left
        anchors.leftMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: Style.space(28)
        width: implicitSize
        height: implicitSize
        source: root.iconSource
        asynchronous: true
      }

      Column {
        anchors.left: appIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: badges.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: root.appName
          color: root.selected ? Color.menu.selectedText : Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: root.title || root.appId
          color: Color.menu.text
          opacity: 0.62
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        id: badges
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(5)

        Rectangle {
          visible: root.showMonitor && root.monitorName.length > 0
          width: monitorText.implicitWidth + Style.space(10)
          height: Math.max(Style.space(22), monitorText.implicitHeight + Style.space(6))
          radius: Style.cornerRadius
          color: Style.normalFill

          Text {
            id: monitorText
            anchors.centerIn: parent
            text: root.monitorName
            color: Color.menu.text
            opacity: 0.62
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          width: workspaceText.implicitWidth + Style.space(12)
          height: Math.max(Style.space(22), workspaceText.implicitHeight + Style.space(6))
          radius: Style.cornerRadius
          color: root.selected ? Style.selectedAccentFill : Style.normalFill

          Text {
            id: workspaceText
            anchors.centerIn: parent
            text: root.workspaceName || "?"
            color: root.selected ? Color.menu.selectedText : Color.menu.text
            opacity: root.selected ? 1 : 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
          }
        }
      }
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hovered(root.index)
    onClicked: root.activated(root.index)
    onWheel: function(wheel) {
      root.wheelRequested(wheel.angleDelta.y)
      wheel.accepted = true
    }
  }
}
