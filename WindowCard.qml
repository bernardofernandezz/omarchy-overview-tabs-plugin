pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Ui

Item {
  id: root

  required property int index
  required property string address
  required property var toplevel
  required property string appId
  required property string appName
  required property string title
  required property string iconSource
  required property string workspaceName
  required property string monitorName

  property bool selected: false
  property bool active: false
  property bool urgent: false
  property bool captureEnabled: false
  property bool showMonitor: false
  property bool peeked: false
  property var pointerGate: null
  property var retainedCaptureSource: null
  property bool fallbackArmed: false
  property string captureState: "idle"
  property int captureGeneration: -1

  signal hovered(int index)
  signal activated(int index)
  signal closeRequested(int index)
  signal wheelRequested(real delta)

  readonly property bool hot: pointer.containsMouse
  readonly property bool previewAvailable: preview.hasContent
  readonly property string subtitleText: root.title && root.title !== root.appName
    ? root.title : root.appId
  readonly property real footerHeight: Math.max(
    Style.space(64), Style.font.body + Style.font.caption + Style.space(28))

  function requestPreview(generation) {
    if (!root.captureEnabled) return false

    root.captureGeneration = Number(generation)

    var nextSource = root.toplevel && root.toplevel.wayland
      ? root.toplevel.wayland : null
    if (!nextSource) {
      root.fallbackArmed = true
      root.captureState = "failed"
      return false
    }

    fallbackDelay.restart()
    if (root.retainedCaptureSource !== nextSource) {
      root.captureState = "capturing"
      root.retainedCaptureSource = nextSource
    } else if (preview.hasContent) {
      // Refresh the retained frame on every overview opening. ScreencopyView
      // keeps the previous texture on screen until the compositor delivers the
      // replacement frame, so previews stay current without flashing.
      preview.captureFrame()
      root.captureState = "ready"
    } else {
      // A previous one-shot request may have failed. Recreate the context only
      // on the next overview opening, never in a retry loop.
      root.retainedCaptureSource = null
      root.captureState = "capturing"
      Qt.callLater(function() {
        if (root.captureEnabled && root.captureGeneration === Number(generation)
            && root.toplevel && root.toplevel.wayland === nextSource)
          root.retainedCaptureSource = nextSource
      })
    }

    if (!preview.hasContent) captureTimeout.restart()
    return true
  }

  onCaptureEnabledChanged: {
    if (root.captureEnabled) return
    fallbackDelay.stop()
    captureTimeout.stop()
    root.captureState = preview.hasContent ? "ready" : "idle"
  }

  onToplevelChanged: {
    var nextSource = root.toplevel && root.toplevel.wayland
      ? root.toplevel.wayland : null
    if (root.retainedCaptureSource === nextSource) return
    root.retainedCaptureSource = null
    root.fallbackArmed = false
    root.captureState = "idle"
  }

  Timer {
    id: fallbackDelay
    interval: 180
    onTriggered: root.fallbackArmed = !preview.hasContent
  }

  Timer {
    id: captureTimeout
    interval: 750
    onTriggered: {
      if (!preview.hasContent) {
        root.captureState = "failed"
        root.fallbackArmed = true
      }
    }
  }

  z: peeked ? 12 : (selected ? 3 : (hot ? 2 : 1))
  scale: peeked ? 1.12 : (selected ? 1.014 : (hot ? 1.008 : 1.0))
  transformOrigin: Item.Center

  Behavior on scale {
    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: -Style.space(4)
    radius: Math.max(0, Style.cornerRadius + Style.space(4))
    color: "transparent"
    border.width: Math.max(1, Style.space(2))
    border.color: Util.alpha(Color.accent, 0.22)
    opacity: root.selected ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 110 } }
  }

  BorderSurface {
    id: surface
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: root.selected
      ? Border.hyprlandActiveSpec(Color.accent, Math.max(2, Style.space(2)))
      : root.hot
        ? Border.controlSpec("hover-cursor", Color.menu.text, Color.accent, Color.urgent)
        : Border.flat(Util.alpha(Color.menu.text, 0.16), Math.max(1, Style.space(1)))

    Rectangle {
      id: previewFrame
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: footer.top
      anchors.margins: Math.max(1, surface.borderTop)
      color: Color.background
      clip: true

      ScreencopyView {
        id: preview
        captureSource: root.retainedCaptureSource
        paintCursor: false
        live: false
        opacity: hasContent ? 1 : 0
        anchors.centerIn: parent
        constraintSize: Qt.size(previewFrame.width, previewFrame.height)
        width: implicitWidth
        height: implicitHeight

        Behavior on opacity {
          NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }

        onHasContentChanged: {
          if (hasContent) {
            fallbackDelay.stop()
            captureTimeout.stop()
            root.fallbackArmed = false
            root.captureState = "ready"
          } else if (root.captureEnabled) {
            fallbackDelay.restart()
          }
        }

        onStopped: {
          captureTimeout.stop()
          root.captureState = "failed"
          root.fallbackArmed = true
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: preview.hasContent && !root.selected && !root.hot
        color: Util.alpha(Color.background, 0.08)
      }

      Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(40), Style.space(280))
        spacing: Style.space(10)
        opacity: root.fallbackArmed && !preview.hasContent ? 1 : 0

        Behavior on opacity {
          NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(Style.space(76), previewFrame.height * 0.34)
          height: width
          radius: Style.cornerRadius
          color: Style.normalFill

          IconImage {
            anchors.centerIn: parent
            width: parent.width * 0.62
            height: width
            source: root.iconSource
            asynchronous: true
            opacity: 0.9
          }
        }

        Text {
          width: parent.width
          text: root.appName
          color: Color.menu.text
          opacity: 0.78
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
          font.weight: Font.DemiBold
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: "Preview unavailable"
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }

      Rectangle {
        visible: root.active
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Style.space(10)
        width: activeLabel.implicitWidth + Style.space(12)
        height: Math.max(Style.space(22), activeLabel.implicitHeight + Style.space(6))
        radius: height / 2
        color: Util.alpha(Color.background, 0.78)

        Text {
          id: activeLabel
          anchors.centerIn: parent
          text: "ACTIVE"
          color: Color.accent
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }
      }

      Rectangle {
        visible: root.urgent
        width: Style.space(8)
        height: width
        radius: width / 2
        color: Color.urgent
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.rightMargin: root.hot || root.selected ? Style.space(44) : Style.space(11)
        anchors.topMargin: Style.space(11)
      }
    }

    Item {
      id: footer
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: root.footerHeight

      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(1, Style.space(1))
        color: Util.alpha(Color.menu.text, 0.1)
      }

      IconImage {
        id: appIcon
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: Style.space(31)
        width: implicitSize
        height: implicitSize
        source: root.iconSource
        asynchronous: true
      }

      Column {
        anchors.left: appIcon.right
        anchors.leftMargin: Style.space(11)
        anchors.right: badges.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)

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
          text: root.subtitleText
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        id: badges
        anchors.right: parent.right
        anchors.rightMargin: Style.space(11)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(5)

        Rectangle {
          visible: root.showMonitor && root.monitorName.length > 0
          width: monitorText.implicitWidth + Style.space(10)
          height: Math.max(Style.space(22), monitorText.implicitHeight + Style.space(6))
          radius: height / 2
          color: Style.normalFill

          Text {
            id: monitorText
            anchors.centerIn: parent
            text: root.monitorName
            color: Color.muted
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          width: workspaceText.implicitWidth + Style.space(12)
          height: Math.max(Style.space(22), workspaceText.implicitHeight + Style.space(6))
          radius: height / 2
          color: root.selected ? Style.selectedAccentFill : Style.normalFill

          Text {
            id: workspaceText
            anchors.centerIn: parent
            text: root.workspaceName || "?"
            color: root.selected ? Color.menu.selectedText : Color.menu.text
            opacity: root.selected ? 1 : 0.72
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
    onPositionChanged: function(mouse) {
      if (!root.pointerGate || root.pointerGate.moved(pointer, mouse))
        root.hovered(root.index)
    }
    onClicked: root.activated(root.index)
    onWheel: function(wheel) { root.wheelRequested(wheel.angleDelta.y) }
  }

  Rectangle {
    id: closeButton
    z: 20
    visible: root.hot || root.selected
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.space(9)
    width: Style.space(27)
    height: width
    radius: width / 2
    color: closePointer.pressed
      ? Style.pressedFillFor(Color.menu.text, Color.accent, Color.urgent)
      : closePointer.containsMouse
        ? Style.hoverFillFor(Color.menu.text, Color.accent, Color.urgent)
        : Util.alpha(Color.background, 0.82)

    Text {
      anchors.centerIn: parent
      text: "×"
      color: Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.heading
    }

    MouseArea {
      id: closePointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.hovered(root.index)
        root.closeRequested(root.index)
      }
    }
  }
}
