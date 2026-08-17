pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland

QtObject {
  id: root

  property var undoStack: []
  readonly property int undoCount: undoStack.length
  readonly property bool canMoveToMonitor: Hyprland.usingLua

  signal performed(string message)
  signal failed(string message)

  function normalizedAddress(value) {
    return String(value || "").replace(/^0x/i, "")
  }

  function matcher(value) {
    var address = root.normalizedAddress(value)
    return address ? "address:0x" + address : ""
  }

  function luaString(value) {
    return "\"" + String(value || "")
      .replace(/\\/g, "\\\\")
      .replace(/\"/g, "\\\"") + "\""
  }

  function rowAddress(row) {
    return row ? root.normalizedAddress(row.address) : ""
  }

  function pushUndo(action) {
    var next = [action]
    for (var i = 0; i < root.undoStack.length && next.length < 16; i++)
      next.push(root.undoStack[i])
    root.undoStack = next
  }

  function dispatchWorkspace(address, workspaceId) {
    var target = Number(workspaceId)
    var selector = root.matcher(address)
    if (!selector || !isFinite(target) || target < 1) return false
    if (Hyprland.usingLua) {
      Hyprland.dispatch("hl.dsp.window.move({ workspace = " + target
        + ", follow = false, window = " + root.luaString(selector) + " })")
    } else {
      Hyprland.dispatch("movetoworkspacesilent " + target + "," + selector)
    }
    return true
  }

  function moveToWorkspace(row, workspaceId, recordUndo) {
    var address = root.rowAddress(row)
    var target = Number(workspaceId)
    if (!address || !isFinite(target) || target < 1) {
      root.failed("Unable to move this window")
      return false
    }
    if (Number(row.workspaceId) === target) {
      root.performed("Already on workspace " + target)
      return true
    }
    var previousWorkspace = Number(row.workspaceId)
    if (recordUndo !== false && isFinite(previousWorkspace) && previousWorkspace >= 1)
      root.pushUndo({ kind: "workspace", address: address, value: previousWorkspace })
    if (!root.dispatchWorkspace(address, target)) {
      root.failed("Unable to move this window")
      return false
    }
    root.performed("Moved " + row.appName + " to workspace " + target)
    return true
  }

  function dispatchMonitor(address, monitorName) {
    var selector = root.matcher(address)
    if (!Hyprland.usingLua || !selector || !monitorName) return false
    Hyprland.dispatch("hl.dsp.window.move({ monitor = " + root.luaString(monitorName)
      + ", follow = false, window = " + root.luaString(selector) + " })")
    return true
  }

  function moveToMonitor(row, monitorName, recordUndo) {
    var address = root.rowAddress(row)
    if (!address || !monitorName || !root.canMoveToMonitor) {
      root.failed("Move to monitor is unavailable")
      return false
    }
    if (String(row.monitorName || "") === String(monitorName)) {
      root.performed("Already on " + monitorName)
      return true
    }
    var previousMonitor = String(row.monitorName || "")
    if (recordUndo !== false && previousMonitor)
      root.pushUndo({ kind: "monitor", address: address, value: previousMonitor })
    if (!root.dispatchMonitor(address, monitorName)) {
      root.failed("Move to monitor is unavailable")
      return false
    }
    root.performed("Moved " + row.appName + " to " + monitorName)
    return true
  }

  function closeWindow(row) {
    if (!row || !row.toplevel) {
      root.failed("Window is no longer available")
      return false
    }
    if (row.toplevel.wayland) {
      row.toplevel.wayland.close()
    } else {
      var selector = root.matcher(row.address)
      if (!selector) {
        root.failed("Window is no longer available")
        return false
      }
      if (Hyprland.usingLua)
        Hyprland.dispatch("hl.dsp.window.close({ window = " + root.luaString(selector) + " })")
      else
        Hyprland.dispatch("closewindow " + selector)
    }
    root.performed("Closed " + row.appName)
    return true
  }

  function undo() {
    if (root.undoStack.length === 0) {
      root.failed("Nothing to undo")
      return false
    }
    var action = root.undoStack[0]
    root.undoStack = root.undoStack.slice(1)
    var ok = action.kind === "workspace"
      ? root.dispatchWorkspace(action.address, action.value)
      : action.kind === "monitor"
        ? root.dispatchMonitor(action.address, action.value)
        : false
    if (ok) root.performed("Move undone")
    else root.failed("Unable to undo the move")
    return ok
  }
}
