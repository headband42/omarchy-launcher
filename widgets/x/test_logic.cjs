const test = require("node:test")
const assert = require("node:assert/strict")
const X = require("./x.js")

test("normalizedSettings defaults", () => {
  const options = X.normalizedSettings({})
  assert.equal(options.woeid, 1)
  assert.equal(options.placeName, "Worldwide")
  assert.equal(options.maxHeadlines, 8)
  assert.equal(options.cookiesPath, "")
})

test("settingsFor omits empty cookies path", () => {
  const saved = X.settingsFor(23424977, "United States", 5, "", "US")
  assert.equal(saved.woeid, 23424977)
  assert.equal(saved.maxHeadlines, 5)
  assert.equal(saved.countryCode, "US")
  assert.equal("cookiesPath" in saved, false)
})

test("volumeLabel scales", () => {
  assert.equal(X.volumeLabel(120000), "120K")
  assert.equal(X.volumeLabel(1500000), "1.5M")
  assert.equal(X.volumeLabel(null), "")
})

test("notificationLabel hides zeros and failures", () => {
  assert.equal(X.notificationLabel({ ok: true, count: 3 }), "3")
  assert.equal(X.notificationLabel({ ok: true, count: 0 }), "")
  assert.equal(X.notificationLabel({ ok: false, count: 9 }), "")
  assert.equal(X.notificationLabel({ ok: true, count: 120 }), "99+")
})

test("effectiveCookiesPath falls back to default", () => {
  assert.equal(X.effectiveCookiesPath(""), X.DEFAULT_COOKIES_PATH)
  assert.equal(X.effectiveCookiesPath(" ~/c.json "), "~/c.json")
})
