function chooseColumns(width, height, count, gap, minWidth, maxWidth, previewAspect, footerHeight) {
  if (count <= 1) return 1

  var usableWidth = Math.max(1, Number(width) || 1)
  var usableHeight = Math.max(1, Number(height) || 1)
  var spacing = Math.max(0, Number(gap) || 0)
  var minimum = Math.max(1, Number(minWidth) || 1)
  var maximum = Math.max(minimum, Number(maxWidth) || minimum)
  var aspect = Math.max(0.1, Number(previewAspect) || 1.6)
  var footer = Math.max(0, Number(footerHeight) || 0)
  var maxColumns = Math.min(count, 6)
  var best = null

  for (var columns = 1; columns <= maxColumns; columns++) {
    var rows = Math.ceil(count / columns)
    var widthLimit = (usableWidth - spacing * (columns - 1)) / columns
    var rowHeightLimit = (usableHeight - spacing * (rows - 1)) / rows
    var heightWidthLimit = Math.max(0, rowHeightLimit - footer) * aspect
    var cardWidth = Math.min(maximum, widthLimit, heightWidthLimit)
    var cardHeight = cardWidth / aspect + footer
    var totalHeight = rows * cardHeight + spacing * (rows - 1)
    var fits = cardWidth >= minimum && totalHeight <= usableHeight

    if (!fits) continue

    var emptySlots = rows * columns - count
    var score = cardWidth * cardHeight - emptySlots * 250
    if (!best || score > best.score || (score === best.score && rows < best.rows)) {
      best = { columns: columns, score: score, rows: rows }
    }
  }

  if (best) return best.columns

  return Math.max(1, Math.min(maxColumns,
    Math.floor((usableWidth + spacing) / (minimum + spacing))))
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
    moveSpatial: moveSpatial,
    stepWrapped: stepWrapped,
    humanizeAppId: humanizeAppId
  }
}
