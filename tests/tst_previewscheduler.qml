import QtQuick
import QtTest
import ".."

TestCase {
  id: testCase
  name: "PreviewScheduler"

  property var requested: []

  PreviewScheduler {
    id: scheduler
    intervalMs: 5
    onCaptureRequested: function(address, generation) {
      testCase.requested = testCase.requested.concat([{ address: address, generation: generation }])
    }
  }

  function init() {
    scheduler.cancel()
    requested = []
  }

  function test_replaceDeduplicatesAndPaces() {
    scheduler.replace(["a", "b", "a", "", "c"])

    compare(requested.length, 1)
    compare(requested[0].address, "a")
    tryCompare(scheduler, "queuedCount", 0, 200)
    compare(requested.length, 3)
    compare(requested.map(function(item) { return item.address }).join(","), "a,b,c")
    compare(requested[0].generation, requested[2].generation)
  }

  function test_prioritizeMovesAddressToFront() {
    scheduler.intervalMs = 40
    scheduler.replace(["a", "b", "c"])
    scheduler.prioritize("c")

    compare(requested[0].address, "a")
    tryCompare(scheduler, "queuedCount", 0, 300)
    compare(requested.length, 3)
    compare(requested.map(function(item) { return item.address }).join(","), "a,c,b")
  }

  function test_cancelDropsPendingCaptures() {
    scheduler.intervalMs = 30
    scheduler.replace(["a", "b", "c"])
    compare(requested.length, 1)
    scheduler.cancel()
    wait(80)
    compare(requested.length, 1)
    compare(scheduler.queuedCount, 0)
  }
}
