// Meters for the system and disk tiles (sysmon, sysdisk, disks). QML imports
// this file as "../_kit/system.js"; node tests require it. fill() reads the
// global Qt, so its test sets globalThis.Qt first.

// A meter is calm below HOT_FROM and fully hot at HOT_AT.
var HOT_FROM = 0.75
var HOT_AT = 0.9
// Two CPU readings further apart than this are not compared: the tile was
// closed in between, and the average would cover the time it was shut.
var CPU_GAP_MS = 5000
// How far a peak marker falls back toward the bar on each sample.
var PEAK_DECAY = 0.02

function clamp01(v) {
  var x = Number(v)
  if (!isFinite(x)) return 0
  return Math.max(0, Math.min(1, x))
}

// A reading the sampler gave, or null for one it did not.
function reading(v) {
  if (v === null || v === undefined || v === "") return null
  var x = Number(v)
  return isFinite(x) ? x : null
}

// 0 while a meter is comfortable, rising to 1 as it runs hot.
function heat(value) {
  var x = clamp01(value)
  if (x <= HOT_FROM) return 0
  if (x >= HOT_AT) return 1
  return (x - HOT_FROM) / (HOT_AT - HOT_FROM)
}

function isHot(value) {
  return clamp01(value) >= HOT_FROM
}

// A meter's fill: the text color while it is comfortable, blending into the
// theme's urgent color as it runs hot. Not the accent: on a theme whose
// accent is orange, every idle bar would already read as a warning.
function fill(value, calm, hot) {
  var t = heat(value)
  return Qt.rgba(calm.r + (hot.r - calm.r) * t,
                 calm.g + (hot.g - calm.g) * t,
                 calm.b + (hot.b - calm.b) * t, 1)
}

function validTicks(ticks) {
  if (!ticks || ticks.length < 2) return null
  var total = Number(ticks[0])
  var idle = Number(ticks[1])
  if (!isFinite(total) || !isFinite(idle) || total < 0 || idle < 0) return null
  return [total, idle]
}

// The CPU reading after one more sample. `state` is { ticks, at, cpu }, the
// last /proc/stat counters ([total, idle] jiffies), when they arrived, and
// the CPU % shown. A sample's own `cpu` (a --warm run) is taken as it is;
// otherwise CPU % is the busy share of the jiffies since the last sample.
// Counters older than the ones held are a run that finished late and are
// dropped, so the next sample still compares with the newest.
function cpuStep(state, sample, now) {
  var prev = state || {}
  var out = { ticks: prev.ticks || null, at: Number(prev.at) || 0, cpu: reading(prev.cpu) }
  var s = sample || {}
  var own = reading(s.cpu)
  var ticks = validTicks(s.cpuTicks)
  if (own !== null) out.cpu = Math.max(0, Math.min(100, own))
  if (!ticks) return out
  if (out.ticks && now - out.at <= CPU_GAP_MS) {
    var spent = ticks[0] - out.ticks[0]
    if (spent <= 0) return out
    if (own === null) {
      var idle = Math.max(0, Math.min(spent, ticks[1] - out.ticks[1]))
      out.cpu = Math.round(1000 * (spent - idle) / spent) / 10
    }
  }
  out.ticks = ticks
  out.at = now
  return out
}

// 3.9 GHz, 885 MHz, or "" with no clock.
function clock(mhz) {
  var v = Number(mhz)
  if (!(v > 0)) return ""
  if (v >= 1000) return (v / 1000).toFixed(1) + " GHz"
  return Math.round(v) + " MHz"
}

function temp(celsius) {
  var v = reading(celsius)
  if (v === null || v <= 0) return ""
  return Math.round(v) + "°C"
}

// "51.3 / 60.4 GiB", or MiB under a GiB in all. "" without a total.
function bytesPair(used, total) {
  var t = Number(total) || 0
  var u = Math.max(0, Number(used) || 0)
  if (!(t > 0)) return ""
  var gib = 1073741824
  if (t >= gib) return (u / gib).toFixed(1) + " / " + (t / gib).toFixed(1) + " GiB"
  var mib = 1048576
  return Math.round(u / mib) + " / " + Math.round(t / mib) + " MiB"
}

function joined(bits) {
  return bits.filter(function(bit) { return bit && bit.length > 0 }).join(" · ")
}

function percentText(v) {
  var x = reading(v)
  return x === null ? "—" : Math.round(Math.max(0, Math.min(100, x))) + "%"
}

// The rows a system tile draws: { key, label, value (0-1), pct, sub }.
// CPU and RAM always. GPU when the sampler can read a load or a clock, or
// says the GPU is asleep. VRAM only for a GPU with memory of its own.
function meters(sample, cpu) {
  var s = sample || {}
  var rows = []
  var cpuNow = reading(cpu)
  rows.push({
    key: "cpu", label: "CPU", value: cpuNow === null ? 0 : clamp01(cpuNow / 100),
    pct: percentText(cpuNow), sub: joined([clock(s.cpuMHz), temp(s.cpuTemp)])
  })
  var mem = Number(s.memTotal) > 0 ? reading(s.mem) : null
  rows.push({
    key: "mem", label: "RAM", value: mem === null ? 0 : clamp01(mem / 100),
    pct: percentText(mem), sub: bytesPair(s.memUsed, s.memTotal)
  })
  var load = reading(s.gpu)
  if (s.gpuAsleep) {
    rows.push({ key: "gpu", label: "GPU", value: 0, pct: "0%", sub: "asleep" })
  } else if (load !== null || Number(s.gpuMHz) > 0) {
    rows.push({
      key: "gpu", label: "GPU", value: load === null ? 0 : clamp01(load / 100),
      pct: percentText(load), sub: joined([clock(s.gpuMHz), temp(s.gpuTemp)])
    })
  }
  if (Number(s.vramTotal) > 0) {
    rows.push({
      key: "vram", label: "VRAM", value: clamp01((Number(s.vram) || 0) / 100),
      pct: percentText(s.vram), sub: bytesPair(s.vramUsed, s.vramTotal)
    })
  }
  return rows
}

// The fullest meter, for the header dot.
function hottest(rows) {
  var most = 0
  for (var i = 0; i < (rows || []).length; i++) most = Math.max(most, clamp01(rows[i].value))
  return most
}

// Peak-hold markers: each row's recent maximum, falling back slowly.
function peaksStep(peaks, rows) {
  var out = {}
  for (var i = 0; i < (rows || []).length; i++) {
    var row = rows[i]
    var old = Number(peaks && peaks[row.key]) || 0
    out[row.key] = Math.max(clamp01(row.value), old - PEAK_DECAY)
  }
  return out
}

// The hardware lines under the meters; only known specs appear.
function specLines(specs) {
  var s = specs || {}
  var out = []
  var cpuBits = []
  if (s.cpuModel) cpuBits.push(String(s.cpuModel))
  var cores = Math.round(Number(s.cpuCores) || 0)
  var threads = Math.round(Number(s.cpuThreads) || 0)
  if (cores > 0 && threads > 0) cpuBits.push(cores + "C/" + threads + "T")
  else if (threads > 0) cpuBits.push(threads + "T")
  if (cpuBits.length > 0) out.push(cpuBits.join(" · "))
  if (s.memConfig) out.push(String(s.memConfig))
  if (s.gpuModel) out.push(String(s.gpuModel))
  if (s.sysDrive) out.push(String(s.sysDrive))
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    HOT_FROM: HOT_FROM, HOT_AT: HOT_AT, CPU_GAP_MS: CPU_GAP_MS, clamp01: clamp01, heat: heat,
    isHot: isHot, fill: fill, cpuStep: cpuStep, clock: clock, temp: temp, bytesPair: bytesPair,
    meters: meters, hottest: hottest, peaksStep: peaksStep, specLines: specLines
  }
}
