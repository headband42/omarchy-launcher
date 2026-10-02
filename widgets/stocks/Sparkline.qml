import QtQuick
import "stocks.js" as Stocks

// The day's closes as a line over a soft fill, after Omafinance's watchlist.
// A falling quote also gets a dashed line at the previous close.
Item {
  id: spark

  property var values: []
  property real previousClose: NaN
  property bool showPreviousClose: false
  property color lineColor: "white"
  property color fillColor: Qt.rgba(spark.lineColor.r, spark.lineColor.g, spark.lineColor.b, 0.2)
  property color previousCloseColor: "white"

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var g = Stocks.sparkGeometry(spark.values, width, height, 2, spark.previousClose, spark.showPreviousClose)
      var count = g.xs.length
      ctx.lineWidth = 1.5
      ctx.lineJoin = "round"
      ctx.lineCap = "round"

      if (count === 0) {
        ctx.globalAlpha = 0.35
        ctx.strokeStyle = spark.lineColor
        ctx.beginPath()
        ctx.moveTo(g.left, height / 2)
        ctx.lineTo(g.right, height / 2)
        ctx.stroke()
        ctx.globalAlpha = 1
        return
      }

      if (isFinite(g.closeY)) {
        ctx.save()
        ctx.lineWidth = 1
        ctx.globalAlpha = 0.55
        ctx.strokeStyle = spark.previousCloseColor
        ctx.setLineDash([2, 3])
        ctx.beginPath()
        ctx.moveTo(g.left, g.closeY)
        ctx.lineTo(g.right, g.closeY)
        ctx.stroke()
        ctx.restore()
      }

      var i
      ctx.beginPath()
      ctx.moveTo(g.xs[0], g.ys[0])
      for (i = 1; i < count; i++) ctx.lineTo(g.xs[i], g.ys[i])
      ctx.lineTo(g.xs[count - 1], g.bottom)
      ctx.lineTo(g.xs[0], g.bottom)
      ctx.closePath()
      ctx.fillStyle = spark.fillColor
      ctx.fill()

      ctx.beginPath()
      ctx.moveTo(g.xs[0], g.ys[0])
      for (i = 1; i < count; i++) ctx.lineTo(g.xs[i], g.ys[i])
      ctx.strokeStyle = spark.lineColor
      ctx.stroke()
    }
  }

  onValuesChanged: canvas.requestPaint()
  onPreviousCloseChanged: canvas.requestPaint()
  onShowPreviousCloseChanged: canvas.requestPaint()
  onLineColorChanged: canvas.requestPaint()
  onFillColorChanged: canvas.requestPaint()
  onPreviousCloseColorChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()
}
