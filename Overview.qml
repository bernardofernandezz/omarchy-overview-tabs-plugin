pragma ComponentBehavior: Bound

import QtQuick
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

    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    if (root.shell && root.shell.appLibrary)
      root.shell.appLibrary.refreshIcons()

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

  function desktopEntryFor(appId) {
    return appId ? DesktopEntries.heuristicLookup(appId) : null
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
      var entry = root.desktopEntryFor(appId)
      var appName = entry ? String(entry.name || appId) : TaskViewModel.humanizeAppId(appId)
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

  function debugState() {
    var loadedCards = 0
    var previewsReady = 0
    for (var i = 0; i < windowGrid.count; i++) {
      var card = windowGrid.itemAtIndex(i)
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
    onTriggered: {
      if (root.selectedIndex >= 0)
        windowGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
    }
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
      color: Color.menu.scrim
      opacity: root.opened ? 1 : 0
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
      anchors.fill: parent
      anchors.margins: Math.max(Style.space(26), Math.min(panel.width, panel.height) * 0.035)
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

      Row {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(Style.space(44), titleLabel.implicitHeight)
        spacing: Style.space(18)

        Text {
          id: titleLabel
          anchors.verticalCenter: parent.verticalCenter
          text: "Task View"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.display
          font.weight: Font.DemiBold
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(0, parent.width - titleLabel.width - header.spacing)
          text: root.query ? "Search: " + root.query : "Type to search windows…"
          color: Color.menu.text
          opacity: root.query ? 0.92 : 0.48
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }

      Flickable {
        id: workspaceStrip
        anchors.top: header.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(34)
        contentWidth: workspaceButtons.width
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick

        Row {
          id: workspaceButtons
          height: parent.height
          spacing: Style.space(7)

          Rectangle {
            visible: root.allWorkspaces
            width: allLabel.implicitWidth + Style.space(22)
            height: parent.height
            radius: Style.cornerRadius
            color: root.workspaceFilter === -1 ? Color.menu.selectedBackground : Style.normalFill
            border.color: root.workspaceFilter === -1 ? Color.menu.selectedText : "transparent"
            border.width: root.workspaceFilter === -1 ? Math.max(1, Style.space(1)) : 0

            Text {
              id: allLabel
              anchors.centerIn: parent
              text: "All windows  " + Hyprland.toplevels.values.length
              color: root.workspaceFilter === -1 ? Color.menu.selectedText : Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.workspaceFilter = -1
            }
          }

          Repeater {
            model: root.workspaceRows

            delegate: Rectangle {
              id: workspaceButton
              required property int index
              required property var modelData

              readonly property bool chosen: root.workspaceFilter === modelData.id
              width: workspaceLabel.implicitWidth + Style.space(22)
              height: workspaceButtons.height
              radius: Style.cornerRadius
              color: chosen ? Color.menu.selectedBackground : Style.normalFill
              border.color: chosen ? Color.menu.selectedText : "transparent"
              border.width: chosen ? Math.max(1, Style.space(1)) : 0

              Text {
                id: workspaceLabel
                anchors.centerIn: parent
                text: workspaceButton.modelData.name + "  " + workspaceButton.modelData.count
                color: workspaceButton.chosen ? Color.menu.selectedText : Color.menu.text
                opacity: workspaceButton.modelData.active || workspaceButton.chosen ? 1 : 0.68
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.weight: workspaceButton.modelData.focused ? Font.DemiBold : Font.Normal
              }

              Rectangle {
                visible: workspaceButton.modelData.urgent
                width: Style.space(5)
                height: width
                radius: width / 2
                color: Color.urgent
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.space(5)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.workspaceFilter = workspaceButton.modelData.id
              }
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
        anchors.bottom: helpText.top
        anchors.bottomMargin: Style.space(14)

        GridView {
          id: windowGrid
          anchors.fill: parent
          clip: true
          model: root.windowRows
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds
          keyNavigationEnabled: false
          highlightFollowsCurrentItem: false
          currentIndex: root.selectedIndex

          readonly property int gap: Style.space(14)
          readonly property int columns: TaskViewModel.chooseColumns(
            width, height, root.windowRows.length, gap, Style.space(250),
            Style.space(560), 1.6, Style.space(62))
          readonly property real rawCellWidth: columns > 0
            ? width / columns - gap : width
          cellWidth: columns > 0 ? width / columns : width
          cellHeight: Math.max(Style.space(218), rawCellWidth / 1.6 + Style.space(62)) + gap

          delegate: WindowCard {
            required property var modelData

            width: windowGrid.rawCellWidth
            height: windowGrid.cellHeight - windowGrid.gap
            toplevel: modelData.toplevel
            appId: modelData.appId
            appName: modelData.appName
            title: modelData.title
            iconSource: modelData.iconSource
            workspaceName: modelData.workspaceName
            monitorName: modelData.monitorName
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
                windowGrid.contentHeight - windowGrid.height,
                windowGrid.contentY - delta))
            }
          }
        }

        Column {
          anchors.centerIn: parent
          visible: root.windowRows.length === 0
          spacing: Style.space(8)

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
            color: Color.menu.text
            opacity: 0.5
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Text {
        id: helpText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: implicitHeight
        text: "← ↑ ↓ →  Navigate     Enter  Open     Esc  Close"
        color: Color.menu.text
        opacity: 0.46
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }
}
