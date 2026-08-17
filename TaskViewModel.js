function chooseColumns(width, height, count, gap, minWidth, maxWidth, previewAspect, footerHeight) {
  return gridMetrics(width, height, count, gap, minWidth, maxWidth, previewAspect, footerHeight).columns
}

function gridMetrics(width, height, count, gap, minWidth, maxWidth, previewAspect, footerHeight) {
  var itemCount = Math.max(0, Number(count) || 0)
  var usableWidth = Math.max(1, Number(width) || 1)
  var usableHeight = Math.max(1, Number(height) || 1)
  var spacing = Math.max(0, Number(gap) || 0)
  var minimum = Math.max(1, Number(minWidth) || 1)
  var maximum = Math.max(minimum, Number(maxWidth) || minimum)
  var aspect = Math.max(0.1, Number(previewAspect) || 1.6)
  var footer = Math.max(0, Number(footerHeight) || 0)

  if (itemCount === 0) {
    return {
      columns: 1,
      rows: 0,
      cardWidth: Math.min(maximum, usableWidth),
      cardHeight: 0,
      contentHeight: 0
    }
  }

  if (itemCount === 1) maximum = Math.max(maximum, Math.min(usableWidth, 860))
  else if (itemCount === 2) maximum = Math.max(maximum, Math.min(usableWidth / 2, 720))

  var maxColumns = Math.min(itemCount, 6)
  var best = null

  for (var columns = 1; columns <= maxColumns; columns++) {
    var rows = Math.ceil(itemCount / columns)
    var widthLimit = (usableWidth - spacing * (columns - 1)) / columns
    var rowHeightLimit = (usableHeight - spacing * (rows - 1)) / rows
    var heightWidthLimit = Math.max(0, rowHeightLimit - footer) * aspect
    var cardWidth = Math.min(maximum, widthLimit, heightWidthLimit)
    var cardHeight = cardWidth / aspect + footer
    var contentHeight = rows * cardHeight + spacing * (rows - 1)
    var fitsWidth = cardWidth >= minimum
    var fitsHeight = contentHeight <= usableHeight
    if (!fitsWidth || !fitsHeight) continue

    var emptySlots = rows * columns - itemCount
    var score = cardWidth * cardHeight - emptySlots * cardWidth * 0.08
    if (!best || score > best.score || (score === best.score && rows < best.rows)) {
      best = {
        columns: columns,
        rows: rows,
        cardWidth: cardWidth,
        cardHeight: cardHeight,
        contentHeight: contentHeight,
        score: score
      }
    }
  }

  if (best) return best

  var fallbackColumns = Math.max(1, Math.min(maxColumns,
    Math.floor((usableWidth + spacing) / (minimum + spacing))))
  var fallbackRows = Math.ceil(itemCount / fallbackColumns)
  var fallbackWidth = Math.min(maximum,
    (usableWidth - spacing * (fallbackColumns - 1)) / fallbackColumns)
  fallbackWidth = Math.max(Math.min(minimum, usableWidth), fallbackWidth)
  var fallbackHeight = fallbackWidth / aspect + footer

  return {
    columns: fallbackColumns,
    rows: fallbackRows,
    cardWidth: fallbackWidth,
    cardHeight: fallbackHeight,
    contentHeight: fallbackRows * fallbackHeight + spacing * (fallbackRows - 1)
  }
}

function normalizeIdentity(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/\.desktop$/i, "")
    .replace(/^org\.|^com\.|^io\.|^net\.|^dev\./, "")
    .replace(/[^a-z0-9]+/g, "")
}

function identityWords(value) {
  return String(value || "")
    .replace(/\.desktop$/i, "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(function(word) { return word.length > 0 })
}

function isGenericLabel(value) {
  var label = normalizeIdentity(value)
  return label === "" || label === "application" || label === "default"
    || label === "quickshell" || label === "orgquickshell"
    || label === "electron" || label === "electronapp"
}

function webAppHost(value) {
  var text = String(value || "").toLowerCase()
  var match = text.match(/^(?:chrome|chromium|brave|edge)-([a-z0-9.-]+?)(?:__|_[^.]|-(?:default|profile))/)
  return match ? match[1].replace(/^www\./, "") : ""
}

function steamAppId(value) {
  var match = String(value || "").toLowerCase().match(/(?:steam_app_|steam[-:]?)(\d{3,})/)
  return match ? match[1] : ""
}

function hostStem(host) {
  var parts = String(host || "").split(".")
  if (parts.length < 2) return parts[0] || ""
  return parts[parts.length - 2]
}

function containsWord(text, word) {
  if (!word || word.length < 3) return false
  return identityWords(text).indexOf(String(word).toLowerCase()) >= 0
}

function scoreDesktopEntry(entry, appId, title, initialClass) {
  if (!entry) return -100000

  var entryId = String(entry.id || "").replace(/\.desktop$/i, "")
  var entryName = String(entry.name || "")
  var startupClass = String(entry.startupClass || "")
  var execString = String(entry.execString || "").toLowerCase()
  var appRaw = String(appId || "")
  var initialRaw = String(initialClass || "")
  var app = normalizeIdentity(appRaw)
  var initial = normalizeIdentity(initialRaw)
  var id = normalizeIdentity(entryId)
  var name = normalizeIdentity(entryName)
  var startup = normalizeIdentity(startupClass)
  var host = webAppHost(appRaw) || webAppHost(initialRaw)
  var stem = hostStem(host)
  var steamId = steamAppId(appRaw) || steamAppId(initialRaw)
  var score = 0

  if (isGenericLabel(entryId) || isGenericLabel(entryName)) score -= 1400

  if (app && id === app) score += 2400
  if (app && name === app) score += 2200
  if (app && startup === app) score += 2600
  if (initial && id === initial) score += 2300
  if (initial && startup === initial) score += 2500

  if (host) {
    if (execString.indexOf(host) >= 0) score += 3200
    if (id === normalizeIdentity(stem)) score += 1800
    if (name === normalizeIdentity(stem)) score += 1700
    if (containsWord(entryId, stem) || containsWord(entryName, stem)) score += 700
  }

  if (steamId) {
    if (entryId.indexOf(steamId) >= 0) score += 3000
    if (execString.indexOf("-applaunch " + steamId) >= 0
        || execString.indexOf("rungameid/" + steamId) >= 0) score += 3400
  }

  if (id.length >= 4 && app.indexOf(id) >= 0) score += 520
  if (name.length >= 4 && app.indexOf(name) >= 0) score += 460
  if (startup.length >= 4 && app.indexOf(startup) >= 0) score += 560
  if (id.length >= 4 && initial.indexOf(id) >= 0) score += 480

  if (isGenericLabel(appRaw) || isGenericLabel(initialRaw)) {
    if (containsWord(title, entryId)) score += 480
    if (containsWord(title, entryName)) score += 520
  }

  return score
}

function bestDesktopEntry(entries, appId, title, initialClass, heuristicEntry) {
  var values = entries || []
  var best = null
  var bestScore = -100000

  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry) continue
    var score = scoreDesktopEntry(entry, appId, title, initialClass)
    if (score > bestScore) {
      best = entry
      bestScore = score
    }
  }

  var heuristicScore = scoreDesktopEntry(heuristicEntry, appId, title, initialClass)
  if (heuristicEntry && heuristicScore > bestScore) {
    best = heuristicEntry
    bestScore = heuristicScore
  }

  return bestScore >= 400 ? best : null
}

function displayName(entry, appId, title) {
  var entryName = String((entry && entry.name) || "").trim()
  if (entryName && !isGenericLabel(entryName)) return entryName

  if (isGenericLabel(appId)) {
    var cleanTitle = String(title || "")
      .replace(/^\s*\(\d+\)\s*/, "")
      .replace(/^\s+|\s+$/g, "")
    if (cleanTitle) return cleanTitle.length > 42 ? cleanTitle.slice(0, 41) + "…" : cleanTitle
  }

  return humanizeAppId(appId)
}

function foldSearch(value) {
  var text = String(value || "").toLowerCase()
  if (typeof text.normalize === "function")
    text = text.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
  return text.replace(/\s+/g, " ").trim()
}

function wordStartsWith(text, token) {
  var words = foldSearch(text).split(/[^a-z0-9]+/)
  for (var i = 0; i < words.length; i++) {
    if (words[i].indexOf(token) === 0) return true
  }
  return false
}

function fieldTokenScore(value, token, exactScore, prefixScore, wordScore, containsScore) {
  var field = foldSearch(value)
  if (!field) return -1
  if (field === token) return exactScore
  if (field.indexOf(token) === 0) return prefixScore
  if (wordStartsWith(field, token)) return wordScore
  if (field.indexOf(token) >= 0) return containsScore
  var fuzzy = fuzzySubsequenceScore(field, token)
  if (fuzzy >= 0) return Math.max(1, containsScore - 260 + fuzzy)
  return -1
}

function fuzzySubsequenceScore(value, token) {
  var field = foldSearch(value)
  var needle = foldSearch(token)
  if (!field || !needle) return -1

  var position = -1
  var first = -1
  var gaps = 0
  var consecutive = 0
  for (var i = 0; i < needle.length; i++) {
    var next = field.indexOf(needle.charAt(i), position + 1)
    if (next < 0) return -1
    if (first < 0) first = next
    if (position >= 0) {
      var gap = next - position - 1
      gaps += gap
      if (gap === 0) consecutive += 1
    }
    position = next
  }

  // Prefer compact matches near the beginning while keeping the score small
  // enough that exact, prefix, word and substring matches always win.
  return Math.max(0, 180 - first * 8 - gaps * 12 + consecutive * 8)
}

function searchScore(query, appName, title, appId, workspaceName, monitorName) {
  var needle = foldSearch(query)
  if (!needle) return 0

  var tokens = needle.split(/\s+/)
  var total = foldSearch(appName) === needle ? 10000 : 0

  for (var i = 0; i < tokens.length; i++) {
    var token = tokens[i]
    var best = Math.max(
      fieldTokenScore(appName, token, 2400, 2100, 1900, 1700),
      fieldTokenScore(title, token, 1500, 1350, 1200, 1050),
      fieldTokenScore(appId, token, 900, 820, 740, 660),
      fieldTokenScore(workspaceName, token, 520, 470, 420, 370),
      fieldTokenScore(monitorName, token, 320, 290, 260, 230))
    if (best < 0) return -1
    total += best
  }

  return total
}

function moveSpatial(index, count, columns, direction) {
  if (count <= 0) return -1

  var current = Math.max(0, Math.min(Number(index) || 0, count - 1))
  var columnCount = Math.max(1, Number(columns) || 1)
  var row = Math.floor(current / columnCount)
  var column = current % columnCount

  if (direction === "left") {
    return column > 0 ? current - 1 : current
  }
  if (direction === "right") {
    return column + 1 < columnCount && current + 1 < count ? current + 1 : current
  }
  if (direction === "up") {
    if (row === 0) return current
    return Math.min((row - 1) * columnCount + column, count - 1)
  }
  if (direction === "down") {
    var nextRowStart = (row + 1) * columnCount
    if (nextRowStart >= count) return current
    return Math.min(nextRowStart + column, count - 1)
  }

  return current
}

function stepWrapped(index, count, delta) {
  if (count <= 0) return -1
  var current = Math.max(0, Math.min(Number(index) || 0, count - 1))
  return (current + delta + count) % count
}

function humanizeAppId(value) {
  var text = String(value || "").replace(/\.desktop$/i, "")
  var parts = text.split(/[._-]+/)
  var useful = parts.length > 1 ? parts[parts.length - 1] : parts[0]
  if (!useful) return "Application"
  return useful.charAt(0).toUpperCase() + useful.slice(1)
}

if (typeof module !== "undefined") {
  module.exports = {
    chooseColumns: chooseColumns,
    gridMetrics: gridMetrics,
    moveSpatial: moveSpatial,
    stepWrapped: stepWrapped,
    humanizeAppId: humanizeAppId,
    normalizeIdentity: normalizeIdentity,
    webAppHost: webAppHost,
    steamAppId: steamAppId,
    scoreDesktopEntry: scoreDesktopEntry,
    bestDesktopEntry: bestDesktopEntry,
    displayName: displayName,
    fuzzySubsequenceScore: fuzzySubsequenceScore,
    searchScore: searchScore
  }
}
