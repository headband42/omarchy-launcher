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

test("sessionAt is kept only when set", () => {
  assert.equal(X.normalizedSettings({}).sessionAt, 0)
  const saved = X.settingsFor(1, "Worldwide", 8, X.DEFAULT_COOKIES_PATH, "", 1700000000000)
  assert.equal(saved.sessionAt, 1700000000000)
  assert.equal("sessionAt" in X.settingsFor(1, "Worldwide", 8, "", ""), false)
})

test("a Worldwide place stores no place keys", () => {
  const saved = X.settingsFor(1, "Worldwide", 8, X.DEFAULT_COOKIES_PATH, "US", 1700000000000)
  assert.equal("woeid" in saved, false)
  assert.equal("placeName" in saved, false)
  assert.equal("countryCode" in saved, false)
  assert.equal(saved.cookiesPath, X.DEFAULT_COOKIES_PATH)
  assert.equal(saved.sessionAt, 1700000000000)
  const options = X.normalizedSettings(saved)
  assert.equal(options.woeid, 1)
  assert.equal(options.placeName, "Worldwide")
  assert.equal(X.isWorldwide(options.woeid), true)
  assert.equal(X.isWorldwide(2490383), false)
})

test("the place shows over trends and not over Today's News", () => {
  const options = X.normalizedSettings({ woeid: 2490383, placeName: "Seattle" })
  const place = { woeid: 2490383, name: "Seattle" }
  assert.equal(X.placeCaption({ ok: true, source: "trends", place }, options), "Seattle")
  assert.equal(X.placeCaption({ ok: true, source: "trends" }, options), "Seattle")
  assert.equal(X.placeCaption({ ok: true, source: "news", place }, options), "")
  assert.equal(X.placeCaption({ ok: false, place }, options), "")
  assert.equal(X.placeCaption(null, options), "")
})

test("headerTitle names the feed", () => {
  assert.equal(X.headerTitle({ source: "news" }), "X · TODAY'S NEWS")
  assert.equal(X.headerTitle({ source: "trends" }), "X · TRENDING")
  assert.equal(X.headerTitle({}), "X")
})

test("headlineMeta prefers post count, then category", () => {
  assert.equal(X.headlineMeta({ title: "a", volume: 120000 }), "120K posts")
  assert.equal(X.headlineMeta({ title: "a", volume: null, category: " Technology " }), "Technology")
  assert.equal(X.headlineMeta({ title: "a" }), "")
  assert.equal(X.headlineMeta(null), "")
})

test("signInHint only for guest trends", () => {
  assert.equal(X.signInHint({ ok: true, source: "trends" }), true)
  assert.equal(X.signInHint({ ok: true, source: "trends", signedIn: true }), false)
  assert.equal(X.signInHint({ ok: true, source: "news", signedIn: true }), false)
  assert.equal(X.signInHint({ ok: false, source: "trends" }), false)
})

test("headlinesOf tolerates missing rows", () => {
  assert.deepEqual(X.headlinesOf({}), [])
  assert.deepEqual(X.headlinesOf(null), [])
  assert.equal(X.headlinesOf({ headlines: [{ title: "a" }] }).length, 1)
})
