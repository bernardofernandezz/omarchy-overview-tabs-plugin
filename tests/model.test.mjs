import assert from "node:assert/strict"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const model = require("../TaskViewModel.js")

assert.equal(model.chooseColumns(1600, 800, 1, 14, 250, 560, 1.6, 62), 1)
assert.equal(model.chooseColumns(1600, 800, 2, 14, 250, 560, 1.6, 62), 2)
assert.equal(model.chooseColumns(1600, 800, 4, 14, 250, 560, 1.6, 62), 2)
assert.ok(model.chooseColumns(1600, 800, 20, 14, 250, 560, 1.6, 62) >= 4)

const sevenWindowGrid = model.gridMetrics(1840, 810, 7, 16, 260, 620, 1.6, 64)
assert.equal(sevenWindowGrid.columns, 4)
assert.equal(sevenWindowGrid.rows, 2)
assert.ok(sevenWindowGrid.cardWidth >= 400)
assert.ok(sevenWindowGrid.contentHeight <= 810)

const crowdedGrid = model.gridMetrics(1200, 600, 25, 14, 240, 620, 1.6, 64)
assert.ok(crowdedGrid.columns >= 4)
assert.ok(crowdedGrid.contentHeight > 600)

for (const [width, height] of [[1024, 600], [1280, 720], [1920, 1080], [3440, 1440]]) {
  for (let count = 1; count <= 40; count++) {
    const metrics = model.gridMetrics(width, height, count, 16, 240, 620, 1.6, 64)
    assert.ok(Number.isFinite(metrics.cardWidth) && metrics.cardWidth > 0)
    assert.ok(Number.isFinite(metrics.cardHeight) && metrics.cardHeight > 0)
    assert.ok(metrics.cardWidth <= width)
    assert.ok(metrics.columns >= 1 && metrics.columns <= Math.min(count, 6))
    assert.equal(metrics.rows, Math.ceil(count / metrics.columns))
  }
}

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

const desktopEntries = [
  { id: "Default", name: "Default", startupClass: "", execString: "chromium" },
  { id: "Discord", name: "Discord", startupClass: "", execString: "omarchy-launch-webapp https://discord.com/channels/@me" },
  { id: "spotify", name: "Spotify", startupClass: "spotify", execString: "spotify --uri=%u" },
  { id: "steam_app_1245620", name: "ELDEN RING", startupClass: "", execString: "steam -applaunch 1245620" },
  { id: "foot", name: "Foot", startupClass: "foot", execString: "foot" }
]

assert.equal(model.webAppHost("chrome-discord.com__channels_@me-Default"), "discord.com")
assert.equal(model.webAppHost("brave-discord.com__channels_@me-Default"), "discord.com")
assert.equal(model.steamAppId("steam_app_1245620"), "1245620")
assert.equal(
  model.bestDesktopEntry(desktopEntries, "chrome-discord.com__channels_@me-Default", "Discord", "", desktopEntries[0]).name,
  "Discord")
assert.equal(model.bestDesktopEntry(desktopEntries, "Spotify", "Music", "Spotify", null).name, "Spotify")
assert.equal(model.bestDesktopEntry(desktopEntries, "foot", "Terminal", "foot", null).name, "Foot")
assert.equal(model.bestDesktopEntry(desktopEntries, "org.quickshell", "Omarchy Spotify", "org.quickshell", null).name, "Spotify")
assert.equal(model.bestDesktopEntry(desktopEntries, "electron", "Discord — General", "electron", null).name, "Discord")
assert.equal(model.bestDesktopEntry(desktopEntries, "steam_app_1245620", "ELDEN RING", "", null).name, "ELDEN RING")
assert.equal(model.displayName(null, "org.quickshell", "Omarchy Settings"), "Omarchy Settings")

assert.equal(model.searchScore("", "Firefox", "GitHub", "org.mozilla.firefox", "1", "DP-1"), 0)
assert.ok(
  model.searchScore("firefox", "Firefox", "GitHub", "org.mozilla.firefox", "1", "DP-1")
  > model.searchScore("fire", "Firefox", "GitHub", "org.mozilla.firefox", "1", "DP-1"))
assert.ok(
  model.searchScore("github", "Firefox", "GitHub — Firefox", "org.mozilla.firefox", "1", "DP-1")
  > model.searchScore("mozilla", "Firefox", "GitHub — Firefox", "org.mozilla.firefox", "1", "DP-1"))
assert.ok(model.searchScore("fire github", "Firefox", "GitHub — Firefox", "org.mozilla.firefox", "1", "DP-1") > 0)
assert.ok(model.searchScore("workspace 2", "Terminal", "Shell", "foot", "Workspace 2", "DP-1") > 0)
assert.equal(model.searchScore("missing", "Firefox", "GitHub", "org.mozilla.firefox", "1", "DP-1"), -1)

console.log("TaskViewModel tests passed")
