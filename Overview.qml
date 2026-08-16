pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "TaskViewModel.js" as TaskViewModel

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool surfaceVisible: false
  property string phase: "closed"
  property bool allWorkspaces: true
  property int workspaceFilter: -1
  property string query: ""
  property int selectedIndex: -1
  property string selectedAddress: ""
  property string pendingActivationAddress: ""
  property var targetScreen: null
  property var recentAddresses: []

  readonly property string pluginId: "local.task-view"
  readonly property int currentWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property string focusedMonitorName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  readonly property string currentWorkspaceName: Hyprland.focusedWorkspace
    ? String(Hyprland.focusedWorkspace.name || Hyprland.focusedWorkspace.id) : ""
  readonly property var windowRows: buildWindowRows()
  readonly property var workspaceRows: buildWorkspaceRows()

  function parsePayload(payloadJson) {
    if (!payloadJson) return ({})
    try { return JSON.parse(payloadJson) || ({}) } catch (error) {
      console.warn("task-view: invalid payload:", error)
      return ({})
    }
  }

  function configuredAllWorkspaces() {
    var config = root.shell && root.shell.shellConfig ? root.shell.shellConfig : null
    var plugins = config && Array.isArray(config.plugins) ? config.plugins : []
    for (var i = 0; i < plugins.length; i++) {
      var entry = plugins[i]
      if (entry && String(entry.id || "") === root.pluginId && entry.allWorkspaces !== undefined)
        return entry.allWorkspaces !== false
    }
    return true
  }

  function focusedScreen() {
    var screens = Quickshell.screens || []
    var monitor = Hyprland.focusedMonitor
    for (var i = 0; i < screens.length; i++) {
      if (monitor && Hyprland.monitorFor(screens[i]) === monitor) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function open(payloadJson) {
    var args = parsePayload(payloadJson)
    closeTimer.stop()
    readyTimer.stop()
    reconcileTimer.stop()
    positionTimer.stop()
    activationTimer.stop()
    activationFallbackTimer.stop()
    root.pendingActivationAddress = ""
    root.targetScreen = focusedScreen()
    root.allWorkspaces = args.allWorkspaces === undefined
      ? configuredAllWorkspaces() : args.allWorkspaces !== false
    root.workspaceFilter = root.allWorkspaces ? -1 : root.currentWorkspaceId
    root.query = ""
    root.phase = "loading"
    root.surfaceVisible = true
    root.opened = true

    var active = Hyprland.activeToplevel
    root.selectedAddress = active ? String(active.address || "") : ""
    root.reconcileSelection()

    readyTimer.restart()
  }

  function close() {
    if (!root.surfaceVisible || root.phase === "closing") return
    root.opened = false
    root.phase = "closing"
    root.query = ""
    closeTimer.restart()
  }

  function toggle(payloadJson) {
    if (root.opened) root.close()
    else root.open(payloadJson || "{}")
  }

  function appIdFor(toplevel) {
    if (!toplevel) return ""
    if (toplevel.wayland && toplevel.wayland.appId)
      return String(toplevel.wayland.appId)
    var snapshot = toplevel.lastIpcObject || ({})
    return String(snapshot.class || snapshot.initialClass || "")
  }

  function titleFor(toplevel) {
    if (!toplevel) return ""
    return String(toplevel.title || (toplevel.wayland ? toplevel.wayland.title : "") || "")
  }

  function desktopEntryFor(toplevel, appId, title) {
    var snapshot = toplevel ? (toplevel.lastIpcObject || ({})) : ({})
    var initialClass = String(snapshot.initialClass || snapshot.class || "")
    var heuristic = appId ? DesktopEntries.heuristicLookup(appId) : null
    return TaskViewModel.bestDesktopEntry(
      DesktopEntries.applications.values || [], appId, title, initialClass, heuristic)
  }

  function iconSourceFor(entry) {
    var icon = entry ? String(entry.icon || "") : ""
    if (root.shell && root.shell.appLibrary)
      return root.shell.appLibrary.iconSource(icon)
    return Quickshell.iconPath(icon || "application-x-executable", true)
  }

  function recencyRank(address, snapshot) {
    var recent = root.recentAddresses.indexOf(address)
    if (recent >= 0) return recent
    var history = snapshot && snapshot.focusHistoryID !== undefined
      ? Number(snapshot.focusHistoryID) : 1000000
    return isFinite(history) && history >= 0 ? 1000 + history : 1000000
  }

  function buildWindowRows() {
    var values = Hyprland.toplevels.values || []
    var rows = []
    var needle = root.query.toLowerCase().trim()

    for (var i = 0; i < values.length; i++) {
      var toplevel = values[i]
      if (!toplevel) continue
      var workspace = toplevel.workspace
      var workspaceId = workspace ? workspace.id : -1
      if (root.workspaceFilter !== -1 && workspaceId !== root.workspaceFilter) continue

      var appId = root.appIdFor(toplevel)
      var title = root.titleFor(toplevel)
      var entry = root.desktopEntryFor(toplevel, appId, title)
      var appName = TaskViewModel.displayName(entry, appId, title)
      if (needle && (appName + " " + appId + " " + title).toLowerCase().indexOf(needle) === -1)
        continue

      var snapshot = toplevel.lastIpcObject || ({})
      var monitor = toplevel.monitor
      rows.push({
        toplevel: toplevel,
        address: String(toplevel.address || ""),
        appId: appId,
        appName: appName,
        title: title,
        iconSource: root.iconSourceFor(entry),
        workspaceId: workspaceId,
        workspaceName: workspace ? String(workspace.name || workspace.id) : "?",
        monitorName: monitor ? String(monitor.name || "") : "",
        urgent: toplevel.urgent === true,
        active: toplevel.activated === true,
        sameWorkspace: workspaceId === root.currentWorkspaceId,
        recency: root.recencyRank(String(toplevel.address || ""), snapshot)
      })
    }

    rows.sort(function(left, right) {
      if (left.active !== right.active) return left.active ? -1 : 1
      if (left.recency !== right.recency) return left.recency - right.recency
      if (left.sameWorkspace !== right.sameWorkspace) return left.sameWorkspace ? -1 : 1
      if (left.workspaceId !== right.workspaceId) return left.workspaceId - right.workspaceId
      return left.title.localeCompare(right.title)
    })
    return rows
  }

  function buildWorkspaceRows() {
    var values = Hyprland.workspaces.values || []
    var rows = []
    for (var i = 0; i < values.length; i++) {
      var workspace = values[i]
      if (!workspace || workspace.toplevels.values.length === 0) continue
      rows.push({
        workspace: workspace,
        id: workspace.id,
        name: String(workspace.name || workspace.id),
        active: workspace.active === true,
        focused: workspace.focused === true,
        urgent: workspace.urgent === true,
        count: workspace.toplevels.values.length
      })
    }
    rows.sort(function(left, right) { return left.id - right.id })
    return rows
  }

  function rememberActive(toplevel) {
    if (!toplevel || !toplevel.address) return
    var address = String(toplevel.address)
    var next = [address]
    for (var i = 0; i < root.recentAddresses.length && next.length < 64; i++) {
      if (root.recentAddresses[i] !== address) next.push(root.recentAddresses[i])
    }
    root.recentAddresses = next
  }

  function indexForAddress(address) {
    if (!address) return -1
    for (var i = 0; i < root.windowRows.length; i++) {
      if (root.windowRows[i].address === address) return i
    }
    return -1
  }

  function reconcileSelection() {
    if (root.windowRows.length === 0) {
      root.selectedIndex = -1
      root.selectedAddress = ""
      return
    }

    var preserved = root.indexForAddress(root.selectedAddress)
    if (preserved >= 0) {
      root.selectedIndex = preserved
      return
    }

    var active = Hyprland.activeToplevel
    var activeIndex = root.indexForAddress(active ? String(active.address || "") : "")
    root.setSelection(activeIndex >= 0 ? activeIndex : 0)
  }

  function setSelection(index) {
    if (root.windowRows.length === 0) {
      root.selectedIndex = -1
      root.selectedAddress = ""
      return
    }
    root.selectedIndex = Math.max(0, Math.min(index, root.windowRows.length - 1))
    root.selectedAddress = root.windowRows[root.selectedIndex].address
    positionTimer.restart()
  }

  function moveSelection(direction) {
    root.setSelection(TaskViewModel.moveSpatial(
      root.selectedIndex, root.windowRows.length, windowGrid.columns, direction))
  }

  function stepSelection(delta) {
    root.setSelection(TaskViewModel.stepWrapped(
      root.selectedIndex, root.windowRows.length, delta))
  }

  function findToplevel(address) {
    var values = Hyprland.toplevels.values || []
    for (var i = 0; i < values.length; i++) {
      if (values[i] && String(values[i].address || "") === address) return values[i]
    }
    return null
  }

  function dispatchFocusAddress(address) {
    if (!address) return
    var matcher = "address:0x" + address
    if (Hyprland.usingLua) {
      Hyprland.dispatch("hl.dsp.focus({ window = \"" + matcher + "\" })")
    } else {
      Hyprland.dispatch("focuswindow " + matcher)
    }
  }

  function finishActivation(address) {
    var current = root.findToplevel(address)
    if (!current) {
      root.pendingActivationAddress = ""
      return
    }
    if (current.wayland) {
      current.wayland.activate()
      activationFallbackTimer.restart()
    } else {
      root.dispatchFocusAddress(address)
      root.pendingActivationAddress = ""
    }
  }

  function activateIndex(index) {
    if (index < 0 || index >= root.windowRows.length) return
    var row = root.windowRows[index]
    var address = row.address
    var workspace = row.toplevel ? row.toplevel.workspace : null
    root.close()
    root.pendingActivationAddress = address
    if (workspace && !workspace.active) workspace.activate()
    activationTimer.restart()
  }

  function ensureSelectionVisible() {
    if (root.selectedIndex < 0) return
    var card = windowRepeater.itemAt(root.selectedIndex)
    if (!card) return

    var margin = Style.space(12)
    var top = card.y - margin
    var bottom = card.y + card.height + margin
    if (top < windowGrid.contentY) {
      windowGrid.contentY = Math.max(0, top)
    } else if (bottom > windowGrid.contentY + windowGrid.height) {
      windowGrid.contentY = Math.min(
        Math.max(0, windowGrid.contentHeight - windowGrid.height),
        bottom - windowGrid.height)
    }
  }

  function debugState() {
    var loadedCards = 0
    var previewsReady = 0
    for (var i = 0; i < root.windowRows.length; i++) {
      var card = windowRepeater.itemAt(i)
      if (!card) continue
      loadedCards++
      if (card["previewAvailable"] === true) previewsReady++
    }
    return JSON.stringify({
      opened: root.opened,
      phase: root.phase,
      windowCount: root.windowRows.length,
      selectedIndex: root.selectedIndex,
      selectedAddress: root.selectedAddress,
      columns: windowGrid.columns,
      loadedCards: loadedCards,
      previewsReady: previewsReady,
      workspaceFilter: root.workspaceFilter,
      focusedMonitor: root.focusedMonitorName
    })
  }

  onWindowRowsChanged: reconcileTimer.restart()

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      root.rememberActive(Hyprland.activeToplevel)
    }
    function onFocusedMonitorChanged() {
      if (root.opened) root.targetScreen = root.focusedScreen()
    }
  }

  Component.onCompleted: {
    root.targetScreen = root.focusedScreen()
    root.rememberActive(Hyprland.activeToplevel)
  }

  Timer {
    id: closeTimer
    interval: 110
    onTriggered: {
      root.surfaceVisible = false
      root.phase = "closed"
    }
  }

  Timer {
    id: readyTimer
    interval: 0
    onTriggered: {
      if (!root.opened) return
      root.phase = "ready"
      root.reconcileSelection()
      keyCatcher.forceActiveFocus()
    }
  }

  Timer {
    id: reconcileTimer
    interval: 0
    onTriggered: root.reconcileSelection()
  }

  Timer {
    id: positionTimer
    interval: 0
    onTriggered: root.ensureSelectionVisible()
  }

  Timer {
    id: activationTimer
    interval: 45
    onTriggered: root.finishActivation(root.pendingActivationAddress)
  }

  Timer {
    id: activationFallbackTimer
    interval: 85
    onTriggered: {
      var active = Hyprland.activeToplevel
      var activeAddress = active ? String(active.address || "") : ""
      if (root.pendingActivationAddress && activeAddress !== root.pendingActivationAddress)
        root.dispatchFocusAddress(root.pendingActivationAddress)
      root.pendingActivationAddress = ""
    }
  }

  PanelWindow {
    id: panel
    visible: root.surfaceVisible
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-task-view"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.background
      opacity: root.opened ? 0.9 : 0
      Behavior on opacity {
        NumberAnimation { duration: root.opened ? 150 : 90; easing.type: Easing.OutCubic }
      }
    }

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      opacity: root.opened ? 0.34 : 0
      Behavior on opacity {
        NumberAnimation { duration: root.opened ? 150 : 90; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.opened
      onClicked: root.close()
    }

    Item {
      id: viewport
      readonly property real edgeMargin: Math.max(
        Style.space(24), Math.min(panel.width, panel.height) * 0.042)
      width: Math.min(panel.width - edgeMargin * 2, Style.space(1760))
      height: panel.height - edgeMargin * 2
      anchors.centerIn: parent
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.98

      Behavior on opacity {
        NumberAnimation { duration: root.opened ? 160 : 90; easing.type: Easing.OutCubic }
      }
      Behavior on scale {
        NumberAnimation { duration: root.opened ? 160 : 90; easing.type: Easing.OutCubic }
      }

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.moveSelection("left")
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.moveSelection("right")
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveSelection("up")
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveSelection("down")
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier)) {
            root.stepSelection(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.stepSelection(1)
            event.accepted = true
          } else if (Util.editsFilter(event, root.query)) {
            root.query = Util.editedFilter(event, root.query)
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                     && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            root.query += event.text
            event.accepted = true
          }
        }
      }

      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(54)

        Column {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)

          Text {
            text: "Task View"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.display
            font.weight: Font.DemiBold
          }

          Text {
            text: root.windowRows.length + (root.windowRows.length === 1 ? " window" : " windows")
              + (root.currentWorkspaceName ? "  ·  Workspace " + root.currentWorkspaceName : "")
            color: Color.muted
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        BorderSurface {
          id: searchSurface
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(Style.space(420), Math.max(Style.space(260), parent.width * 0.34))
          height: Style.space(38)
          radius: Style.cornerRadius
          color: root.query
            ? Style.focusFillFor(Color.menu.text, Color.accent, Color.urgent)
            : Style.normalFillFor(Color.menu.text, Color.accent, Color.urgent)
          borderSpec: Border.controlSpec(
            root.query ? "focus" : "normal", Color.menu.text, Color.accent, Color.urgent)

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(9)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "⌕"
              color: root.query ? Color.menu.selectedText : Color.muted
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.heading
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - searchKey.width - Style.space(42)
              text: root.query || "Search windows…"
              color: root.query ? Color.menu.text : Color.muted
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Rectangle {
              id: searchKey
              anchors.verticalCenter: parent.verticalCenter
              width: searchKeyLabel.implicitWidth + Style.space(10)
              height: Style.space(22)
              radius: Style.cornerRadius
              color: Util.alpha(Color.menu.text, 0.08)

              Text {
                id: searchKeyLabel
                anchors.centerIn: parent
                text: root.query ? "⌫" : "type"
                color: Color.muted
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      Flickable {
        id: workspaceStrip
        anchors.top: header.bottom
        anchors.topMargin: Style.space(12)
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(38)
        contentWidth: workspaceButtons.width
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick

        Row {
          id: workspaceButtons
          x: Math.max(0, (workspaceStrip.width - width) / 2)
          height: parent.height
          spacing: Style.space(8)

          WorkspaceTab {
            visible: root.allWorkspaces
            label: "All windows"
            count: Hyprland.toplevels.values.length
            selected: root.workspaceFilter === -1
            active: false
            urgent: false
            onClicked: root.workspaceFilter = -1
          }

          Repeater {
            model: root.workspaceRows

            delegate: WorkspaceTab {
              id: workspaceButton
              required property var modelData

              label: "Workspace " + modelData.name
              count: modelData.count
              selected: root.workspaceFilter === modelData.id
              active: modelData.focused || modelData.active
              urgent: modelData.urgent
              onClicked: root.workspaceFilter = workspaceButton.modelData.id
            }
          }
        }
      }

      Item {
        id: gridFrame
        anchors.top: workspaceStrip.bottom
        anchors.topMargin: Style.space(18)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: helpBar.top
        anchors.bottomMargin: Style.space(14)

        Flickable {
          id: windowGrid
          anchors.fill: parent
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: metrics.contentHeight > height
          contentWidth: width
          contentHeight: Math.max(height, metrics.contentHeight)

          readonly property int gap: Style.space(16)
          readonly property var metrics: TaskViewModel.gridMetrics(
            width, height, root.windowRows.length, gap, Style.space(250),
            Style.space(620), 1.6, Style.space(64))
          readonly property int columns: metrics.columns
          readonly property real verticalOffset: metrics.contentHeight < height
            ? (height - metrics.contentHeight) / 2 : 0

          QQC.ScrollBar.vertical: QQC.ScrollBar {
            policy: windowGrid.metrics.contentHeight > windowGrid.height
              ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
          }

          Item {
            id: gridCanvas
            width: windowGrid.width
            height: windowGrid.contentHeight

            Repeater {
              id: windowRepeater
              model: root.windowRows

              delegate: WindowCard {
                id: windowCard
                required property var modelData

                readonly property int gridRow: Math.floor(index / windowGrid.columns)
                readonly property int gridColumn: index % windowGrid.columns
                readonly property int rowStart: gridRow * windowGrid.columns
                readonly property int itemsInRow: Math.min(
                  windowGrid.columns, root.windowRows.length - rowStart)
                readonly property real rowWidth: itemsInRow * width
                  + Math.max(0, itemsInRow - 1) * windowGrid.gap

                x: (gridCanvas.width - rowWidth) / 2
                  + gridColumn * (width + windowGrid.gap)
                y: windowGrid.verticalOffset
                  + gridRow * (height + windowGrid.gap)
                width: windowGrid.metrics.cardWidth
                height: windowGrid.metrics.cardHeight
                toplevel: modelData.toplevel
                appId: modelData.appId
                appName: modelData.appName
                title: modelData.title
                iconSource: modelData.iconSource
                workspaceName: modelData.workspaceName
                monitorName: modelData.monitorName
                active: modelData.active
                urgent: modelData.urgent
                selected: index === root.selectedIndex
                showMonitor: modelData.monitorName.length > 0
                  && modelData.monitorName !== root.focusedMonitorName
                captureEnabled: root.opened && root.phase === "ready"
                opacity: root.opened ? 1 : 0

                Behavior on opacity {
                  NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                }

                onHovered: function(nextIndex) { root.setSelection(nextIndex) }
                onActivated: function(nextIndex) { root.activateIndex(nextIndex) }
                onWheelRequested: function(delta) {
                  windowGrid.contentY = Math.max(0, Math.min(
                    Math.max(0, windowGrid.contentHeight - windowGrid.height),
                    windowGrid.contentY - delta))
                }
              }
            }
          }
        }

        Column {
          anchors.centerIn: parent
          visible: root.windowRows.length === 0
          spacing: Style.space(10)

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.space(54)
            height: width
            radius: Style.cornerRadius
            color: Style.normalFillFor(Color.menu.text, Color.accent, Color.urgent)

            Text {
              anchors.centerIn: parent
              text: root.query ? "⌕" : "□"
              color: Color.accent
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.display
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.query ? "No matching windows" : "No open windows"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.query ? "Press Backspace to edit your search" : "Press Escape to return"
            color: Color.muted
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Item {
        id: helpBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(26)

        Row {
          anchors.centerIn: parent
          spacing: Style.space(18)

          Repeater {
            model: [
              { keys: "← ↑ ↓ →", label: "Navigate" },
              { keys: "Enter", label: "Open" },
              { keys: "Esc", label: "Close" }
            ]

            delegate: Row {
              required property var modelData
              spacing: Style.space(7)

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: shortcutKey.implicitWidth + Style.space(10)
                height: Style.space(22)
                radius: Style.cornerRadius
                color: Util.alpha(Color.menu.text, 0.08)

                Text {
                  id: shortcutKey
                  anchors.centerIn: parent
                  text: modelData.keys
                  color: Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: Color.muted
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
