// Club colors for the MLB tile only. QML imports this file; node tests require it.
// background is the tile fill, text sits on it, accent marks the live state.

var COLORS = {
  "108": { background: "#BA0021", text: "#FFFFFF", accent: "#003263" },
  "109": { background: "#A71930", text: "#FFFFFF", accent: "#E3D4AD" },
  "110": { background: "#DF4601", text: "#FFFFFF", accent: "#000000" },
  "111": { background: "#BD3039", text: "#FFFFFF", accent: "#0C2340" },
  "112": { background: "#0E3386", text: "#FFFFFF", accent: "#CC3433" },
  "113": { background: "#C6011F", text: "#FFFFFF", accent: "#000000" },
  "114": { background: "#00385D", text: "#FFFFFF", accent: "#E31937" },
  "115": { background: "#33006F", text: "#FFFFFF", accent: "#C4CED4" },
  "116": { background: "#0C2340", text: "#FFFFFF", accent: "#FA4616" },
  "117": { background: "#002D62", text: "#FFFFFF", accent: "#EB6E1F" },
  "118": { background: "#004687", text: "#FFFFFF", accent: "#C09A5B" },
  "119": { background: "#005A9C", text: "#FFFFFF", accent: "#EF3E42" },
  "120": { background: "#AB0003", text: "#FFFFFF", accent: "#14225A" },
  "121": { background: "#002D72", text: "#FFFFFF", accent: "#FF5910" },
  "133": { background: "#003831", text: "#FFFFFF", accent: "#EFB21E" },
  "134": { background: "#27251F", text: "#FFFFFF", accent: "#FDB827" },
  "135": { background: "#2F241D", text: "#FFFFFF", accent: "#FFC425" },
  "136": { background: "#0C2C56", text: "#FFFFFF", accent: "#005C5C" },
  "137": { background: "#27251F", text: "#FFFFFF", accent: "#FD5A1E" },
  "138": { background: "#C41E3A", text: "#FFFFFF", accent: "#FEDB00" },
  "139": { background: "#092C5C", text: "#FFFFFF", accent: "#8FBCE6" },
  "140": { background: "#003278", text: "#FFFFFF", accent: "#C0111F" },
  "141": { background: "#134A8E", text: "#FFFFFF", accent: "#1D2D5C" },
  "142": { background: "#002B5C", text: "#FFFFFF", accent: "#D31145" },
  "143": { background: "#E81828", text: "#FFFFFF", accent: "#002D72" },
  "144": { background: "#CE1141", text: "#FFFFFF", accent: "#13274F" },
  "145": { background: "#27251F", text: "#FFFFFF", accent: "#C4CED4" },
  "146": { background: "#00A3E0", text: "#FFFFFF", accent: "#EF3340" },
  "147": { background: "#0C2340", text: "#FFFFFF", accent: "#C4CED4" },
  "158": { background: "#12284B", text: "#FFFFFF", accent: "#FFC52F" }
}

function palette(id) {
  var key = String(Math.round(Number(id)))
  var row = COLORS[key]
  if (!row) return null
  return { background: row.background, text: row.text, accent: row.accent }
}

if (typeof module !== "undefined") module.exports = { palette: palette, COLORS: COLORS }
