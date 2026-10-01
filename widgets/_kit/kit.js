// Helpers for widget QML. Import as "../_kit/kit.js"; node tests require it.

// A file:// URL from Qt.resolvedUrl() as a local path for a Process argv.
// Call Qt.resolvedUrl() in the widget so it resolves next to that widget.
function localPath(url) {
  var value = (url && url.toString) ? url.toString() : String(url || "")
  if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
  return value
}

if (typeof module !== "undefined") module.exports = { localPath: localPath }
