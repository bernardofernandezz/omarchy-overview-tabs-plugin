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
  property string monitorFilter: ""
  property string viewMode: "workspaces"
  property bool vimNavigation: false
  property string query: ""
  property int selectedIndex: -1
  property string selectedAddress: ""
  property bool peeked: false
  property string statusMessage: ""
  property bool statusError: false
  property string pendingActivationAddress: ""
  property int activationAttempt: 0
  property string previousFocusAddress: ""
  property string closeReason: "cancel"
  property int closeCount: 0
  property var targetScreen: null
  property var recentAddresses: []
  property int modelGeneration: 0
  property double openStartedAt: 0
  property int openingLatencyMs: 0

  readonly property string pluginId: "local.task-view"
  readonly property int currentWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property string focusedMonitorName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  readonly property string currentWorkspaceName: Hyprland.focusedWorkspace
    ? String(Hyprland.focusedWorkspace.name || Hyprland.focusedWorkspace.id) : ""
  readonly property int totalWindowCount: (Hyprland.toplevels.values || []).length
  readonly property var windowRows: buildWindowRows()
  readonly property var workspaceRows: buildWorkspaceRows()
  readonly property var monitorRows: buildMonitorRows()

  ScriptModel {
    id: stableWindowModel
    values: root.windowRows
    objectProp: "address"
  }

  ScriptModel {
    id: stableMonitorModel
    values: root.monitorRows
    objectProp: "name"
  }

  WindowActions {
    id: windowActions
    onPerformed: function(message) { root.showStatus(message, false) }
    onFailed: function(message) { root.showStatus(message, true) }
  }

  PointerMoveGate {
    id: pointerMoveGate
    referenceItem: viewport
  }

  ScriptModel {
    id: stableWorkspaceModel
    values: root.workspaceRows
    objectProp: "id"
  }

  PreviewScheduler {
    id: previewScheduler
    intervalMs: 24
    onCaptureRequested: function(address, generation) {
      var card = root.cardForAddress(address)
      if (card && root.opened) card.requestPreview(generation)
    }
  }

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

  function configuredVimNavigation() {
    var config = root.shell && root.shell.shellConfig ? root.shell.shellConfig : null
    var plugins = config && Array.isArray(config.plugins) ? config.plugins : []
    for (var i = 0; i < plugins.length; i++) {
      var entry = plugins[i]
      if (entry && String(entry.id || "") === root.pluginId)
        return entry.vimNavigation === true
    }
    return false
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
    previewScheduleTimer.stop()
    previewScheduler.cancel()
    activationTimer.stop()
    activationFallbackTimer.stop()
    root.pendingActivationAddress = ""
    root.targetScreen = focusedScreen()
    if (!root.targetScreen) {
      root.opened = false
      root.surfaceVisible = false
      root.phase = "closed"
      return
    }
    root.allWorkspaces = args.allWorkspaces === undefined
      ? configuredAllWorkspaces() : args.allWorkspaces !== false
    root.vimNavigation = args.vimNavigation === undefined
      ? configuredVimNavigation() : args.vimNavigation === true
    root.workspaceFilter = root.allWorkspaces ? -1 : root.currentWorkspaceId
    root.monitorFilter = ""
    root.viewMode = "workspaces"
    root.query = ""
    root.peeked = false
    root.statusMessage = ""
    root.closeReason = "cancel"
    root.openStartedAt = Date.now()
    root.openingLatencyMs = 0
    root.phase = "loading"
    root.surfaceVisible = true
    root.opened = true

    var active = Hyprland.activeToplevel
    root.previousFocusAddress = active ? String(active.address || "") : ""
    root.selectedAddress = active ? String(active.address || "") : ""
    root.reconcileSelection()

    readyTimer.restart()
  }

  function close(reason) {
    if (!root.surfaceVisible || root.phase === "closing") return
    root.closeReason = reason || "external"
    root.closeCount += 1
    root.opened = false
    root.phase = "closing"
    root.query = ""
    root.peeked = false
    previewScheduleTimer.stop()
    previewScheduler.cancel()
    closeTimer.restart()
  }

  function toggle(payloadJson) {
    if (root.opened) root.close("toggle")
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

  function recentWindowCount() {
    var values = Hyprland.toplevels.values || []
    var count = 0
    for (var i = 0; i < values.length; i++) {
      if (values[i] && root.recentAddresses.indexOf(String(values[i].address || "")) >= 0)
        count += 1
    }
    return count
  }

  function buildWindowRows() {
    var values = Hyprland.toplevels.values || []
    var rows = []
    var needle = root.query.trim()

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
      var snapshot = toplevel.lastIpcObject || ({})
      var monitor = toplevel.monitor
      var workspaceName = workspace ? String(workspace.name || workspace.id) : "?"
      var monitorName = monitor ? String(monitor.name || "") : ""
      if (root.monitorFilter && monitorName !== root.monitorFilter) continue
      var searchScore = TaskViewModel.searchScore(
        needle, appName, title, appId, workspaceName, monitorName)
      if (searchScore < 0) continue

      rows.push({
        toplevel: toplevel,
        address: String(toplevel.address || ""),
        appId: appId,
        appName: appName,
        title: title,
        iconSource: root.iconSourceFor(entry),
        workspaceId: workspaceId,
        workspaceName: workspaceName,
        monitorName: monitorName,
        urgent: toplevel.urgent === true,
        active: toplevel.activated === true,
        sameWorkspace: workspaceId === root.currentWorkspaceId,
        recency: root.recencyRank(String(toplevel.address || ""), snapshot),
        searchScore: searchScore
      })
    }

    rows.sort(function(left, right) {
      if (needle && left.searchScore !== right.searchScore)
        return right.searchScore - left.searchScore
      if (root.viewMode === "recent" || needle) {
        if (left.active !== right.active) return left.active ? -1 : 1
        if (left.recency !== right.recency) return left.recency - right.recency
      } else {
        if (left.sameWorkspace !== right.sameWorkspace) return left.sameWorkspace ? -1 : 1
        if (left.monitorName !== right.monitorName)
          return left.monitorName.localeCompare(right.monitorName)
      }
      if (left.workspaceId !== right.workspaceId) return left.workspaceId - right.workspaceId
      if (left.active !== right.active) return left.active ? -1 : 1
      if (left.recency !== right.recency) return left.recency - right.recency
      return left.title.localeCompare(right.title)
    })
    return rows
  }

  function buildWorkspaceRows() {
    var values = Hyprland.workspaces.values || []
    var byId = ({})
    var rows = []
    for (var i = 0; i < values.length; i++) {
      var workspace = values[i]
      if (!workspace || workspace.id < 1) continue
      byId[String(workspace.id)] = workspace
    }

    var ids = []
    for (var fixed = 1; fixed <= 9; fixed++) ids.push(fixed)
    for (var known in byId) {
      var numeric = Number(known)
      if (numeric > 9 && ids.indexOf(numeric) < 0) ids.push(numeric)
    }
    ids.sort(function(left, right) { return left - right })

    for (var j = 0; j < ids.length; j++) {
      var id = ids[j]
      var workspace = byId[String(id)] || null
      var windows = workspace && workspace.toplevels ? workspace.toplevels.values || [] : []
      rows.push({
        workspace: workspace,
        id: id,
        name: workspace ? String(workspace.name || id) : String(id),
        active: workspace ? workspace.active === true : id === root.currentWorkspaceId,
        focused: workspace ? workspace.focused === true : id === root.currentWorkspaceId,
        urgent: workspace ? workspace.urgent === true : false,
        count: windows.length,
        empty: windows.length === 0
      })
    }
    return rows
  }

  function buildMonitorRows() {
    var monitors = Hyprland.monitors.values || []
    var windows = Hyprland.toplevels.values || []
    var rows = []
    for (var i = 0; i < monitors.length; i++) {
      var monitor = monitors[i]
      if (!monitor) continue
      var name = String(monitor.name || "")
      var count = 0
      for (var j = 0; j < windows.length; j++) {
        if (windows[j] && windows[j].monitor && String(windows[j].monitor.name || "") === name)
          count += 1
      }
      rows.push({
        monitor: monitor,
        name: name,
        label: String(monitor.description || name),
        focused: monitor.focused === true,
        count: count,
        x: Number(monitor.x || 0),
        y: Number(monitor.y || 0)
      })
    }
    rows.sort(function(left, right) {
      if (left.x !== right.x) return left.x - right.x
      if (left.y !== right.y) return left.y - right.y
      return left.name.localeCompare(right.name)
    })
    return rows
  }

  function workspaceFilterOptions() {
    var options = root.allWorkspaces ? [-1] : []
    for (var i = 0; i < root.workspaceRows.length; i++)
      options.push(root.workspaceRows[i].id)
    return options
  }

  function cycleWorkspaceFilter(delta) {
    var options = root.workspaceFilterOptions()
    if (options.length === 0) return
    var current = options.indexOf(root.workspaceFilter)
    if (current < 0) current = 0
    var next = (current + delta + options.length) % options.length
    root.workspaceFilter = options[next]
  }

  function setViewMode(mode) {
    var next = String(mode || "")
    if (next !== "workspaces" && next !== "recent") return false
    root.viewMode = next
    return true
  }

  function monitorFilterOptions() {
    var options = [""]
    for (var i = 0; i < root.monitorRows.length; i++)
      options.push(root.monitorRows[i].name)
    return options
  }

  function cycleMonitorFilter(delta) {
    var options = root.monitorFilterOptions()
    if (options.length <= 1) return
    var current = options.indexOf(root.monitorFilter)
    if (current < 0) current = 0
    root.monitorFilter = options[(current + delta + options.length) % options.length]
  }

  function filterWorkspaceNumber(number) {
    for (var i = 0; i < root.workspaceRows.length; i++) {
      if (root.workspaceRows[i].id === number) {
        root.workspaceFilter = number
        return
      }
    }
  }

  function reconcileWorkspaceFilter() {
    if (root.workspaceFilter === -1) return
    if (root.workspaceFilter >= 1 && root.workspaceFilter <= 9) return
    var values = Hyprland.workspaces.values || []
    for (var i = 0; i < values.length; i++) {
      if (values[i] && values[i].id === root.workspaceFilter) return
    }
    root.workspaceFilter = root.allWorkspaces ? -1 : root.currentWorkspaceId
  }

  function reconcileMonitorFilter() {
    if (!root.monitorFilter) return
    for (var i = 0; i < root.monitorRows.length; i++) {
      if (root.monitorRows[i].name === root.monitorFilter) return
    }
    root.monitorFilter = ""
  }

  function cardForAddress(address) {
    for (var i = 0; i < windowRepeater.count; i++) {
      var card = windowRepeater.itemAt(i)
      if (card && card.address === address) return card
    }
    return null
  }

  function prioritizedPreviewAddresses() {
    var result = []
    var seen = ({})

    function add(address) {
      address = String(address || "")
      if (!address || seen[address]) return
      seen[address] = true
      result.push(address)
    }

    add(root.selectedAddress)

    for (var i = 0; i < root.windowRows.length; i++) {
      var visibleCard = root.cardForAddress(root.windowRows[i].address)
      if (visibleCard && visibleCard.y + visibleCard.height >= windowGrid.contentY
          && visibleCard.y <= windowGrid.contentY + windowGrid.height)
        add(root.windowRows[i].address)
    }

    for (var j = 0; j < root.windowRows.length; j++) {
      if (root.windowRows[j].workspaceId === root.currentWorkspaceId)
        add(root.windowRows[j].address)
    }
    for (var k = 0; k < root.windowRows.length; k++) add(root.windowRows[k].address)
    return result
  }

  function requestPreviewSchedule() {
    if (!root.opened || root.phase !== "ready") return
    previewScheduleTimer.restart()
  }

  function runPreviewSchedule() {
    if (!root.opened || root.phase !== "ready") return
    // Every opening re-captures all visible cards so retained frames never
    // show stale content; captureFrame() keeps the old frame until the new
    // one is ready, so the refresh is invisible.
    previewScheduler.replace(root.prioritizedPreviewAddresses())
  }

  function rememberActive(toplevel) {
    if (!toplevel || !toplevel.address) return
    var address = String(toplevel.address)
    if (root.recentAddresses.length > 0 && root.recentAddresses[0] === address) return
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

    if (root.selectedIndex >= 0) {
      root.setSelection(Math.min(root.selectedIndex, root.windowRows.length - 1))
      return
    }

    var active = Hyprland.activeToplevel
    var activeIndex = root.indexForAddress(active ? String(active.address || "") : "")
    root.setSelection(activeIndex >= 0 ? activeIndex : 0)
  }

  function setSelection(index, fromPointer) {
    if (root.windowRows.length === 0) {
      root.selectedIndex = -1
      root.selectedAddress = ""
      return
    }
    root.selectedIndex = Math.max(0, Math.min(index, root.windowRows.length - 1))
    root.selectedAddress = root.windowRows[root.selectedIndex].address
    if (fromPointer !== true) pointerMoveGate.reset()
    if (root.opened && root.phase === "ready")
      previewScheduler.prioritize(root.selectedAddress)
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

  function selectedRow() {
    return root.selectedIndex >= 0 && root.selectedIndex < root.windowRows.length
      ? root.windowRows[root.selectedIndex] : null
  }

  function showStatus(message, isError) {
    root.statusMessage = String(message || "")
    root.statusError = isError === true
    statusTimer.restart()
  }

  function closeSelected() {
    var row = root.selectedRow()
    if (row) windowActions.closeWindow(row)
  }

  function moveSelectedToWorkspace(workspaceId) {
    var row = root.selectedRow()
    if (row) windowActions.moveToWorkspace(row, workspaceId, true)
  }

  function moveSelectedToMonitor(delta) {
    var row = root.selectedRow()
    if (!row || root.monitorRows.length < 2) {
      root.showStatus("No other monitor available", true)
      return
    }
    var current = -1
    for (var i = 0; i < root.monitorRows.length; i++) {
      if (root.monitorRows[i].name === row.monitorName) {
        current = i
        break
      }
    }
    if (current < 0) current = 0
    var next = (current + delta + root.monitorRows.length) % root.monitorRows.length
    windowActions.moveToMonitor(row, root.monitorRows[next].name, true)
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

  function beginActivation(address) {
    if (!address) return
    root.pendingActivationAddress = address
    root.activationAttempt = 0
    activationTimer.restart()
  }

  function finishActivation(address) {
    var current = root.findToplevel(address)
    if (!current) {
      root.pendingActivationAddress = ""
      return
    }

    var workspace = current.workspace
    if (workspace && !workspace.active && root.activationAttempt < 3) {
      root.activationAttempt += 1
      workspace.activate()
      activationTimer.restart()
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
    root.close("activate")
    root.beginActivation(address)
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
    var previewsCapturing = 0
    var previewsFailed = 0
    for (var i = 0; i < root.windowRows.length; i++) {
      var card = windowRepeater.itemAt(i)
      if (!card) continue
      loadedCards++
      if (card["previewAvailable"] === true) previewsReady++
      if (card["captureState"] === "capturing") previewsCapturing++
      if (card["captureState"] === "failed") previewsFailed++
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
      previewsCapturing: previewsCapturing,
      previewsFailed: previewsFailed,
      previewQueue: previewScheduler.queuedCount,
      openingLatencyMs: root.openingLatencyMs,
      modelGeneration: root.modelGeneration,
      closeReason: root.closeReason,
      closeCount: root.closeCount,
      workspaceFilter: root.workspaceFilter,
      monitorFilter: root.monitorFilter,
      focusedMonitor: root.focusedMonitorName,
      viewMode: root.viewMode,
      peeked: root.peeked,
      undoCount: windowActions.undoCount,
      usingLua: Hyprland.usingLua
    })
  }

  onWindowRowsChanged: {
    root.modelGeneration += 1
    pointerMoveGate.reset()
    reconcileTimer.restart()
    root.requestPreviewSchedule()
  }
  onWorkspaceRowsChanged: workspaceReconcileTimer.restart()
  onMonitorRowsChanged: monitorReconcileTimer.restart()

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      root.rememberActive(Hyprland.activeToplevel)
    }
    function onFocusedMonitorChanged() {
      if (!root.opened) return
      var nextScreen = root.focusedScreen()
      if (nextScreen) root.targetScreen = nextScreen
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
      if (root.closeReason !== "activate" && root.previousFocusAddress)
        root.beginActivation(root.previousFocusAddress)
    }
  }

  Timer {
    id: readyTimer
    interval: 0
    onTriggered: {
      if (!root.opened) return
      root.phase = "ready"
      root.openingLatencyMs = Math.max(0, Date.now() - root.openStartedAt)
      root.reconcileSelection()
      keyCatcher.forceActiveFocus()
      root.requestPreviewSchedule()
    }
  }

  Timer {
    id: reconcileTimer
    interval: 0
    onTriggered: root.reconcileSelection()
  }

  Timer {
    id: workspaceReconcileTimer
    interval: 0
    onTriggered: root.reconcileWorkspaceFilter()
  }

  Timer {
    id: monitorReconcileTimer
    interval: 0
    onTriggered: root.reconcileMonitorFilter()
  }

  Timer {
    id: statusTimer
    interval: 1800
    onTriggered: root.statusMessage = ""
  }

  Timer {
    id: previewScheduleTimer
    interval: 0
    onTriggered: root.runPreviewSchedule()
  }

  Timer {
    id: positionTimer
    interval: 0
    onTriggered: root.ensureSelectionVisible()
  }

  Timer {
    id: activationTimer
    interval: 35
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
      onClicked: root.close("backdrop")
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
            root.close("escape")
            event.accepted = true
          } else if (event.key === Qt.Key_Space && !root.query
                     && root.selectedIndex >= 0) {
            if (!event.isAutoRepeat) root.peeked = true
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateIndex(root.selectedIndex)
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier)
                     && (event.modifiers & Qt.ShiftModifier)
                     && event.key === Qt.Key_Left) {
            root.moveSelectedToMonitor(-1)
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier)
                     && (event.modifiers & Qt.ShiftModifier)
                     && event.key === Qt.Key_Right) {
            root.moveSelectedToMonitor(1)
            event.accepted = true
          } else if ((event.modifiers & Qt.ShiftModifier)
                     && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                     && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            root.moveSelectedToWorkspace(event.key - Qt.Key_0)
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier)
                     && event.key === Qt.Key_W) {
            root.closeSelected()
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier)
                     && event.key === Qt.Key_Z) {
            windowActions.undo()
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier)
                     && event.key === Qt.Key_R) {
            root.setViewMode(root.viewMode === "recent" ? "workspaces" : "recent")
            event.accepted = true
          } else if ((event.modifiers & Qt.AltModifier)
                     && event.key === Qt.Key_Left) {
            root.cycleMonitorFilter(-1)
            event.accepted = true
          } else if ((event.modifiers & Qt.AltModifier)
                     && event.key === Qt.Key_Right) {
            root.cycleMonitorFilter(1)
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier)
                     && event.key === Qt.Key_Left) {
            root.cycleWorkspaceFilter(-1)
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier)
                     && event.key === Qt.Key_Right) {
            root.cycleWorkspaceFilter(1)
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier)
                     && event.key === Qt.Key_A && root.allWorkspaces) {
            root.workspaceFilter = -1
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier)
                     && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            root.filterWorkspaceNumber(event.key - Qt.Key_0)
            event.accepted = true
          } else if (event.key === Qt.Key_Left
                     || (root.vimNavigation && !root.query
                         && event.modifiers === Qt.NoModifier && event.key === Qt.Key_H)) {
            root.moveSelection("left")
            event.accepted = true
          } else if (event.key === Qt.Key_Right
                     || (root.vimNavigation && !root.query
                         && event.modifiers === Qt.NoModifier && event.key === Qt.Key_L)) {
            root.moveSelection("right")
            event.accepted = true
          } else if (event.key === Qt.Key_Up
                     || (root.vimNavigation && !root.query
                         && event.modifiers === Qt.NoModifier && event.key === Qt.Key_K)) {
            root.moveSelection("up")
            event.accepted = true
          } else if (event.key === Qt.Key_Down
                     || (root.vimNavigation && !root.query
                         && event.modifiers === Qt.NoModifier && event.key === Qt.Key_J)) {
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
        Keys.onReleased: function(event) {
          if (event.key === Qt.Key_Space && root.peeked) {
            root.peeked = false
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
            text: "Mission Control"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.display
            font.weight: Font.DemiBold
          }

          Text {
            text: ((root.query || root.workspaceFilter !== -1)
              ? root.windowRows.length + " of " + root.totalWindowCount
              : root.totalWindowCount)
              + (root.totalWindowCount === 1 ? " window" : " windows")
              + (root.currentWorkspaceName ? "  ·  Workspace " + root.currentWorkspaceName : "")
              + (root.monitorFilter ? "  ·  " + root.monitorFilter : "")
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

          ViewModeSwitch {
            mode: root.viewMode
            workspaceCount: root.totalWindowCount
            recentCount: root.recentWindowCount()
            onModeRequested: function(mode) { root.setViewMode(mode) }
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(1, Style.space(1))
            height: Style.space(22)
            color: Util.alpha(Color.menu.text, 0.14)
          }

          WorkspaceTab {
            visible: root.allWorkspaces
            label: "All"
            count: Hyprland.toplevels.values.length
            selected: root.workspaceFilter === -1
            active: false
            urgent: false
            onClicked: root.workspaceFilter = -1
          }

          Repeater {
            model: stableWorkspaceModel

            delegate: WorkspaceTab {
              id: workspaceButton
              required property var modelData

              label: modelData.name
              count: modelData.count
              selected: root.workspaceFilter === modelData.id
              active: modelData.focused || modelData.active
              urgent: modelData.urgent
              onClicked: root.workspaceFilter = workspaceButton.modelData.id
            }
          }

          Rectangle {
            visible: root.monitorRows.length > 1
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(1, Style.space(1))
            height: Style.space(22)
            color: Util.alpha(Color.menu.text, 0.14)
          }

          WorkspaceTab {
            visible: root.monitorRows.length > 1
            label: "All displays"
            count: root.totalWindowCount
            selected: root.monitorFilter === ""
            active: false
            urgent: false
            onClicked: root.monitorFilter = ""
          }

          Repeater {
            model: stableMonitorModel

            delegate: WorkspaceTab {
              id: monitorButton
              required property var modelData

              visible: root.monitorRows.length > 1
              label: modelData.name
              count: modelData.count
              selected: root.monitorFilter === modelData.name
              active: modelData.focused
              urgent: false
              onClicked: root.monitorFilter = monitorButton.modelData.name
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
          onMovementEnded: root.requestPreviewSchedule()
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
              model: stableWindowModel

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
                address: modelData.address
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
                peeked: root.peeked && selected
                pointerGate: pointerMoveGate
                showMonitor: modelData.monitorName.length > 0
                  && modelData.monitorName !== root.focusedMonitorName
                captureEnabled: root.opened && root.phase === "ready"

                Behavior on x {
                  enabled: root.opened && root.phase === "ready"
                  NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                  enabled: root.opened && root.phase === "ready"
                  NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }

                onHovered: function(nextIndex) { root.setSelection(nextIndex, true) }
                onActivated: function(nextIndex) { root.activateIndex(nextIndex) }
                onCloseRequested: function(nextIndex) {
                  root.setSelection(nextIndex, true)
                  root.closeSelected()
                }
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

      BorderSurface {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: helpBar.top
        anchors.bottomMargin: Style.space(10)
        z: 30
        visible: root.statusMessage.length > 0
        implicitWidth: statusText.implicitWidth + Style.space(28)
        implicitHeight: Style.space(34)
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.flat(
          Util.alpha(root.statusError ? Color.urgent : Color.accent, 0.72),
          Math.max(1, Style.space(1)))

        Text {
          id: statusText
          anchors.centerIn: parent
          text: root.statusMessage
          color: root.statusError ? Color.urgent : Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
          font.weight: Font.DemiBold
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
              { keys: "Space", label: "Peek" },
              { keys: "Shift+1…9", label: "Move" },
              { keys: "Ctrl+W", label: "Close" },
              { keys: "Enter", label: "Open" },
              { keys: "Esc", label: "Dismiss" }
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
