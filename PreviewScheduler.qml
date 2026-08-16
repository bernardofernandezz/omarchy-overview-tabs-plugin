pragma ComponentBehavior: Bound

import QtQuick

QtObject {
  id: root

  property int intervalMs: 24
  property var queue: []
  property int generation: 0
  readonly property int queuedCount: queue.length

  signal captureRequested(string address, int generation)

  function uniqueAddresses(addresses) {
    var result = []
    var seen = ({})
    var values = addresses || []
    for (var i = 0; i < values.length; i++) {
      var address = String(values[i] || "")
      if (!address || seen[address]) continue
      seen[address] = true
      result.push(address)
    }
    return result
  }

  function replace(addresses) {
    pumpTimer.stop()
    root.generation += 1
    root.queue = root.uniqueAddresses(addresses)
    root.pump()
  }

  function append(addresses) {
    var merged = root.queue.slice()
    var values = addresses || []
    for (var i = 0; i < values.length; i++) merged.push(values[i])
    root.queue = root.uniqueAddresses(merged)
    if (!pumpTimer.running) root.pump()
  }

  function prioritize(address) {
    address = String(address || "")
    if (!address) return

    var next = [address]
    for (var i = 0; i < root.queue.length; i++) {
      if (root.queue[i] !== address) next.push(root.queue[i])
    }
    root.queue = next
    if (!pumpTimer.running) root.pump()
  }

  function cancel() {
    pumpTimer.stop()
    root.queue = []
    root.generation += 1
  }

  function pump() {
    if (root.queue.length === 0) return
    var next = root.queue.slice()
    var address = next.shift()
    root.queue = next
    root.captureRequested(address, root.generation)
    if (root.queue.length > 0) pumpTimer.restart()
  }

  property Timer pumpTimer: Timer {
    interval: root.intervalMs
    repeat: false
    onTriggered: root.pump()
  }
}
