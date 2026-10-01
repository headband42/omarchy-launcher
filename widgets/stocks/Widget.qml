import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../_kit"
import "stocks.js" as Stocks

// A watchlist in Omafinance's style: symbol and name, the day's sparkline,
// price, and a change pill. With no tickers in the settings it follows
// Omafinance's own watchlist. A row opens that ticker on Yahoo Finance;
// the header and margins launch Opens.
Item {
  id: root
  clip: true
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({})
  // The sample came from stocks.py this session, not from the cache file.
  property bool live: false
  // The last poll got no answer, so the rows are the previous ones.
  property bool offline: false

  // Omafinance's tones, so the tile matches its bar pill and panel.
  readonly property color upColor: Qt.rgba(0.22, 0.50, 0.30, 1)
  readonly property color downColor: Qt.rgba(0.62, 0.22, 0.22, 1)

  readonly property string request: Stocks.requestKey(root.tile && root.tile.settings)
  readonly property var quotes: {
    var s = root.sample
    if (!s || s.ok !== true || String(s.request || "") !== root.request) return []
    return Stocks.toList(s.quotes)
  }
  readonly property string market: root.quotes.length > 0 ? String(root.sample.market || "") : ""
  readonly property bool trading: root.market === "regular" || root.market === "pre"
    || root.market === "post" || root.market === "live"
  readonly property string statusText: {
    if (root.quotes.length > 0) return ""
    if (root.sample && root.sample.ok === false && String(root.sample.request || "") === root.request)
      return String(root.sample.error || "Quotes unavailable")
    return "Loading quotes…"
  }
  readonly property string cachePath: {
    var base = String(Quickshell.env("XDG_CACHE_HOME") || "")
    if (!base) base = String(Quickshell.env("HOME") || "") + "/.cache"
    return base + "/ande.launcher/stocks.json"
  }

  readonly property var widest: Stocks.widest(root.quotes)
  readonly property int rowInset: Style.space(4)
  readonly property int gap: Style.space(8)
  readonly property int priceWidth: Math.ceil(Math.max(priceMetric.advanceWidth,
    changeMetric.advanceWidth + Style.space(12)))
  readonly property int roomWidth: Math.max(0, list.width - root.rowInset * 2 - root.priceWidth - root.gap)
  // The sparkline takes what the symbol column leaves, up to Omafinance's size.
  readonly property int sparkWidth: {
    var spare = root.roomWidth - Math.max(Math.ceil(symbolMetric.advanceWidth), Style.space(48)) - root.gap
    var w = Math.min(Style.space(76), spare)
    return w >= Style.space(32) ? w : 0
  }
  readonly property int nameWidth: root.roomWidth - (root.sparkWidth > 0 ? root.sparkWidth + root.gap : 0)
  // Price over pill, and symbol over name: the taller stack sets the
  // shortest row, so a full list is cut at the bottom before rows overlap.
  readonly property int priceStack: Math.ceil(priceMetric.height + Style.space(3) + changeMetric.height + Style.space(4))
  readonly property int nameStack: Math.ceil(symbolMetric.height + 1 + nameMetric.height)
  readonly property int minRow: Math.max(root.priceStack, root.nameStack) + Style.space(4)

  function toneColor(pct) {
    var tone = Stocks.changeTone(pct)
    if (tone === "up") return root.upColor
    if (tone === "down") return root.downColor
    return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
  }

  function pillColor(pct) {
    var tone = Stocks.changeTone(pct)
    if (tone === "up") return root.upColor
    if (tone === "down") return root.downColor
    return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
  }

  function openQuote(symbol) {
    var url = Stocks.quoteUrl(symbol)
    if (url && root.host && typeof root.host.openUrl === "function") root.host.openUrl(url)
    else if (root.host && typeof root.host.launchDefault === "function") root.host.launchDefault()
  }

  function applyLive(data) {
    if (data && data.ok === true) {
      root.sample = data
      root.live = true
      root.offline = false
      return
    }
    // No answer. Rows already drawn stay up, marked offline.
    if (root.quotes.length > 0) root.offline = true
    else if (data) root.sample = data
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("stocks.py")
    args: root.request ? ["--symbols", root.request] : []
    interval: Number(root.sample && root.sample.pollMs) || 60000
    active: root.visible
    onSampled: function(data) { root.applyLive(data) }
  }

  // The last good reply, drawn while the first poll is out.
  FileView {
    path: root.cachePath
    printErrors: false
    watchChanges: false
    onLoaded: {
      if (root.live) return
      var cached = Stocks.fromCache(text(), root.request)
      if (cached) root.sample = cached
    }
  }

  TextMetrics {
    id: symbolMetric
    font.family: root.fontFamily
    font.pixelSize: Style.font.title
    font.bold: true
    text: root.widest.symbol
  }

  TextMetrics {
    id: nameMetric
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "Ag"
  }

  TextMetrics {
    id: priceMetric
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    text: root.widest.price
  }

  TextMetrics {
    id: changeMetric
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
    text: root.widest.change
  }

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      title: "STOCKS"
      trailing: root.offline ? "offline" : Stocks.marketLabel(root.market)
      dotColor: root.trading && !root.offline ? Color.accent : root.foreground
      dotOpacity: root.trading && !root.offline ? 1 : 0.35
      pulse: root.trading && root.live && !root.offline
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    Item {
      id: list
      anchors.top: header.bottom
      anchors.topMargin: Style.space(4)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: -root.rowInset
      anchors.rightMargin: -root.rowInset

      readonly property var plan: Stocks.rowPlan(root.quotes.length, list.height,
        root.minRow, Math.max(root.minRow, Style.space(56)), root.nameStack + Style.space(6))

      Column {
        width: parent.width

        Repeater {
          model: root.quotes.slice(0, list.plan.rows)

          Item {
            id: row
            required property var modelData
            readonly property var quote: row.modelData || ({})
            readonly property bool missing: Stocks.isMissing(row.quote)
            readonly property color tone: root.toneColor(row.quote.changePercent)

            width: list.width
            height: list.plan.height

            Rectangle {
              anchors.fill: parent
              radius: Style.space(6)
              color: root.foreground
              opacity: rowMouse.containsMouse ? 0.07 : 0
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openQuote(row.quote.symbol)
            }

            Column {
              anchors.left: parent.left
              anchors.leftMargin: root.rowInset
              anchors.verticalCenter: parent.verticalCenter
              width: root.nameWidth
              spacing: 1

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: String(row.quote.symbol || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                visible: list.plan.names
                width: parent.width
                textFormat: Text.PlainText
                text: row.missing ? "No quote" : String(row.quote.name || "")
                color: root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Sparkline {
              visible: root.sparkWidth > 0 && !row.missing
              anchors.right: priceColumn.left
              anchors.rightMargin: root.gap
              anchors.verticalCenter: parent.verticalCenter
              width: root.sparkWidth
              height: Math.min(Style.space(28), row.height - Style.space(10))
              values: row.quote.closes || []
              previousClose: row.quote.previousClose === null || row.quote.previousClose === undefined
                ? NaN : Number(row.quote.previousClose)
              showPreviousClose: Stocks.changeTone(row.quote.changePercent) === "down"
              lineColor: row.tone
              fillColor: Qt.rgba(row.tone.r, row.tone.g, row.tone.b, 0.2)
              previousCloseColor: root.foreground
            }

            Column {
              id: priceColumn
              anchors.right: parent.right
              anchors.rightMargin: root.rowInset
              anchors.verticalCenter: parent.verticalCenter
              width: root.priceWidth
              spacing: Style.space(3)

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: Stocks.formatPrice(row.quote.price, row.quote.currency, row.quote.priceHint)
                color: root.foreground
                opacity: row.missing ? 0.45 : 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.features: ({ "tnum": 1 })
              }

              Rectangle {
                visible: !row.missing
                anchors.right: parent.right
                radius: Style.space(6)
                color: root.pillColor(row.quote.changePercent)
                implicitWidth: changeLabel.implicitWidth + Style.space(12)
                implicitHeight: changeLabel.implicitHeight + Style.space(4)

                Text {
                  id: changeLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: Stocks.formatPercent(row.quote.changePercent)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }
          }
        }
      }

      Text {
        visible: root.quotes.length === 0
        anchors.centerIn: parent
        width: parent.width - Style.space(16)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.statusText
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
