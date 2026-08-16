import assert from "node:assert/strict"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const model = require("../TaskViewModel.js")

assert.equal(model.chooseColumns(1600, 800, 1, 14, 250, 560, 1.6, 62), 1)
assert.equal(model.chooseColumns(1600, 800, 2, 14, 250, 560, 1.6, 62), 2)
assert.equal(model.chooseColumns(1600, 800, 4, 14, 250, 560, 1.6, 62), 2)
assert.ok(model.chooseColumns(1600, 800, 20, 14, 250, 560, 1.6, 62) >= 4)

for (const count of [0, 1, 2, 4, 8, 15, 25]) {
  const columns = model.chooseColumns(1600, 800, count, 14, 250, 560, 1.6, 62)
  assert.ok(columns >= 1 && columns <= Math.max(1, Math.min(count, 6)))
}

// [A] [B] [C]
// [D] [E]
assert.equal(model.moveSpatial(4, 5, 3, "up"), 1)
assert.equal(model.moveSpatial(2, 5, 3, "down"), 4)
assert.equal(model.moveSpatial(3, 5, 3, "right"), 4)
assert.equal(model.moveSpatial(4, 5, 3, "right"), 4)
assert.equal(model.moveSpatial(0, 5, 3, "left"), 0)
assert.equal(model.stepWrapped(4, 5, 1), 0)
assert.equal(model.stepWrapped(0, 5, -1), 4)

assert.equal(model.humanizeAppId("org.mozilla.firefox"), "Firefox")
assert.equal(model.humanizeAppId("com.visual-studio-code.desktop"), "Code")
assert.equal(model.humanizeAppId(""), "Application")

console.log("TaskViewModel tests passed")
