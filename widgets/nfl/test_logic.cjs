// Logic tests for the NFL tile's formatters. Stdlib only.
//
// nfl.js is the shipped file that Widget.qml and Settings.qml import, so this
// exercises that exact code rather than a copy of it.
//
// Run from the repo root:  node --test widgets/nfl/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Nfl = require("./nfl.js");

const away = { id: 14, abbr: "LAR", city: "Los Angeles", nickname: "Rams", score: 10, record: "1-1" };
const home = { id: 7, abbr: "DEN", city: "Denver", nickname: "Broncos", score: 7, record: "1-1" };

const live = {
  id: "401872962",
  url: "https://www.nfl.com/games/rams-at-broncos-2026-reg-3",
  state: "in",
  live: true,
  finished: false,
  time: "2nd 6:33",
  quarter: "2nd",
  clock: "6:33",
  down: 2,
  distance: 15,
  downDistance: "2nd & 15",
  ball: "DEN 20",
  possession: "DEN",
  lastPlay: "  (Shotgun) M.Stafford  pass incomplete   short left. ",
  network: "NBC",
  neutral: false,
  favorite: "home",
  away,
  home,
};

const kickoff = {
  id: "401872976",
  url: "https://www.nfl.com/games/raiders-at-chiefs-2026-reg-4",
  state: "pre",
  live: false,
  finished: false,
  time: "Oct 4 8:25 PM",
  day: "Oct 4",
  kickoff: "8:25 PM",
  network: "FOX",
  away: { id: 13, abbr: "LV", city: "Las Vegas", nickname: "Raiders", score: null },
  home: { id: 12, abbr: "KC", city: "Kansas City", nickname: "Chiefs", score: null },
};

test("a side shows a score, or a dash before kickoff", () => {
  assert.equal(Nfl.sideScore({ score: 24 }), "24");
  assert.equal(Nfl.sideScore({ score: "0" }), "0");
  assert.equal(Nfl.sideScore({ score: 10.4 }), "10");
  assert.equal(Nfl.sideScore({ score: null }), "—");
  assert.equal(Nfl.sideScore({}), "—");
  assert.equal(Nfl.sideScore(null), "—");
  assert.equal(Nfl.sideScore({ score: "bad" }), "—");
  assert.equal(Nfl.teamAbbr(null), "");
});

test("the ball marker follows possession", () => {
  assert.equal(Nfl.hasBall(live, home), true);
  assert.equal(Nfl.hasBall(live, away), false);
  assert.equal(Nfl.hasBall(kickoff, home), false);
  assert.equal(Nfl.hasBall(null, home), false);
  assert.equal(Nfl.hasBall(live, null), false);
});

test("the leading side is the one ahead", () => {
  assert.equal(Nfl.isLeader(live, away), true);
  assert.equal(Nfl.isLeader(live, home), false);
  assert.equal(Nfl.isLeader(kickoff, away), false);
  assert.equal(Nfl.isLeader({ away, home }, away), true);
  const tied = { away: { abbr: "LAR", score: 7 }, home: { abbr: "DEN", score: 7 } };
  assert.equal(Nfl.isLeader(tied, tied.away), false);
});

test("the drive reads as down and distance plus field position", () => {
  assert.equal(Nfl.situationLine(live), "2nd & 15 at DEN 20");
  assert.equal(Nfl.situationLine({ live: true, downDistance: "3rd & 4", ball: "KC 38" }),
               "3rd & 4 at KC 38");
  assert.equal(Nfl.situationLine({ live: true, downDistance: "1st & 10", ball: "" }), "1st & 10");
  assert.equal(Nfl.situationLine({ live: true, downDistance: "", ball: "DET 47" }), "DET 47");
  assert.equal(Nfl.situationLine({ live: true }), "");
  // Nothing before kickoff or after the whistle.
  assert.equal(Nfl.situationLine(kickoff), "");
});

test("the last play collapses its whitespace", () => {
  assert.equal(Nfl.lastPlay(live), "(Shotgun) M.Stafford pass incomplete short left.");
  assert.equal(Nfl.lastPlay(kickoff), "");
  assert.equal(Nfl.lastPlay(null), "");
});

test("kickoff lines name the day only when it helps", () => {
  assert.equal(Nfl.kickoffLine(live), "2nd 6:33");
  assert.equal(Nfl.kickoffLine(kickoff), "Oct 4 8:25 PM");
  assert.equal(Nfl.kickoffLine({ day: "TODAY", kickoff: "1:00 PM" }), "1:00 PM");
  assert.equal(Nfl.kickoffLine({ day: "SUN", kickoff: "4:25 PM" }), "SUN 4:25 PM");
  assert.equal(Nfl.kickoffLine({ finished: true, time: "FINAL" }), "FINAL");
  assert.equal(Nfl.kickoffLine(null), "");
});

test("the playoff seed leads, the record fills in", () => {
  assert.equal(Nfl.standingLine({ seed: 1, record: "11-5", conference: "AFC" }), "#1 · 11-5");
  assert.equal(Nfl.standingLine({ seed: 0, conferenceRank: 9, conference: "NFC", record: "3-9" }),
               "9 NFC · 3-9");
  assert.equal(Nfl.standingLine({ record: "3-0" }), "3-0");
  assert.equal(Nfl.standingLine({ seed: 7 }), "#7");
  assert.equal(Nfl.standingLine({}), "");
  assert.equal(Nfl.standingLine(null), "");
});

test("point differential is signed and rounded", () => {
  assert.equal(Nfl.differential(38), "+38");
  assert.equal(Nfl.differential(-12), "−12");
  assert.equal(Nfl.differential(0), "0");
  assert.equal(Nfl.differential(7.6), "+8");
  assert.equal(Nfl.differential("bad"), "0");
  assert.equal(Nfl.differential(null), "0");
});

test("the club name is uppercased for the tile header", () => {
  assert.equal(Nfl.teamLine({ city: "Kansas City", nickname: "Chiefs" }), "KANSAS CITY CHIEFS");
  assert.equal(Nfl.teamLine({ city: "", nickname: "Raiders" }), "RAIDERS");
  assert.equal(Nfl.teamLine({ abbr: "WSH" }), "WSH");
  assert.equal(Nfl.teamLine({}), "");
  assert.equal(Nfl.teamLine(null), "");
});

test("the opponent line reads as away or home", () => {
  assert.equal(Nfl.opponentLine(live, ""), "vs LOS ANGELES RAMS");
  assert.equal(Nfl.opponentLine({ away: away, home: home, favorite: "away" }, ""), "@ DENVER BRONCOS");
  assert.equal(Nfl.opponentLine({ away: away, home: home, favorite: "home" }, ""), "vs LOS ANGELES RAMS");
  assert.equal(Nfl.opponentLine(null, ""), "");
});

test("a slate row is terse and keeps its own state", () => {
  assert.equal(Nfl.boardLine(live), "LAR 10  @  DEN 7");
  assert.equal(Nfl.boardLine(kickoff), "LV —  @  KC —");
  assert.equal(Nfl.boardLine(null), "");
  assert.equal(Nfl.boardState(live), "2nd 6:33");
  assert.equal(Nfl.boardState(kickoff), "Oct 4 8:25 PM");
  assert.equal(Nfl.boardState({ finished: true, time: "FINAL" }), "FINAL");
  assert.equal(Nfl.boardState(null), "");
});

test("a club's own game is marked on the slate", () => {
  assert.equal(Nfl.isFavorite(live, "KC"), true);
  assert.equal(Nfl.isFavorite(kickoff, "KC"), true);
  assert.equal(Nfl.isFavorite(kickoff, "SF"), false);
  assert.equal(Nfl.isFavorite({ away, home }, "DEN"), true);
  assert.equal(Nfl.isFavorite({ away, home }, "KC"), false);
  assert.equal(Nfl.isFavorite(null, "KC"), false);
  assert.equal(Nfl.isNeutral({ neutral: true }), true);
  assert.equal(Nfl.isNeutral({}), false);
});

test("the layout answers to the tile it lands in", () => {
  assert.equal(Nfl.compact(220), true);
  assert.equal(Nfl.compact(240), false);
  assert.equal(Nfl.roomy(280), true);
  assert.equal(Nfl.roomy(260), false);
  assert.ok(Nfl.heroSize(300, 300) > Nfl.heroSize(160, 160));
  assert.ok(Nfl.heroSize(0, 0) >= 26);
  assert.ok(Nfl.heroSize("bad", 300) >= 26);
});

test("the placeholder says something useful", () => {
  assert.equal(Nfl.emptyHeadline("empty", "error", true), "Scores unavailable");
  assert.equal(Nfl.emptyHeadline("closed", "", true), "Season complete");
  assert.equal(Nfl.emptyHeadline("upcoming", "", true), "No game found");
  assert.equal(Nfl.emptyHeadline("board", "", true), "NFL");
  assert.equal(Nfl.emptyBody("empty", "error", true), "Check the network, then try again.");
  assert.equal(Nfl.emptyBody("closed", "", true), "Nothing left on the schedule.");
  assert.equal(Nfl.emptyBody("upcoming", "", true), "Choose a club in settings.");
  // Before the first fetch the tile is still working, not idle.
  assert.equal(Nfl.emptyHeadline("", "", false), "NFL");
  assert.equal(Nfl.emptyBody("", "", false), "Fetching the schedule…");
  assert.equal(Nfl.emptyBody("", "error", false), "Check the network, then try again.");
});

test("the slate sorts by kickoff", () => {
  const earlier = { date: "2026-09-28T00:20Z" };
  const later = { date: "2026-10-04T20:25Z" };
  assert.equal(Nfl.byKickoff(earlier, later), -1);
  assert.equal(Nfl.byKickoff(later, earlier), 1);
  assert.equal(Nfl.byKickoff(earlier, earlier), 0);
  assert.equal(Nfl.byKickoff(null, later), -1);
  assert.equal(Nfl.byKickoff(later, null), 1);
});

test("a block of the field places both sides on one number", () => {
  // ESPN measures the line of scrimmage from the offence's own goal line, so
  // their 33 is 33 and the other side is at 67. The strip reads the ball as
  // sitting between the two.
  // The fixture's own tickers: LAR is away, DEN is home.
  const driving = { live: true, possession: "LAR", yardLine: 33, away, home };
  const atHome = { live: true, possession: "DEN", yardLine: 67, away, home };
  assert.equal(Nfl.fieldYard(driving, away), 33);
  assert.equal(Nfl.fieldYard(driving, home), 67);
  assert.equal(Nfl.fieldYard(atHome, home), 67);
  assert.equal(Nfl.fieldYard(atHome, away), 33);
  assert.equal(Nfl.isOffense(driving, away), true);
  assert.equal(Nfl.isOffense(driving, home), false);
  assert.equal(Nfl.hasField(driving), true);
  assert.equal(Nfl.fieldLabel(driving, away), "LAR");
});

test("the field is absent rather than wrong", () => {
  // No possession, no line, or a game that is not running means there is no
  // field to draw, and inventing one would put a ball where nobody is.
  for (const game of [null, {}, { live: false, possession: "LAR", yardLine: 33 },
                      { live: true, yardLine: 33 },
                      { live: true, possession: "LAR" },
                      { live: true, possession: "LAR", yardLine: null },
                      { live: true, possession: "LAR", yardLine: "x" }]) {
    assert.equal(Nfl.hasField(game), false, JSON.stringify(game));
    assert.equal(Nfl.fieldYard(game, away), null);
  }
  assert.equal(Nfl.fieldYard({ live: true, possession: "LAR", yardLine: 33 }, null), null);
  // An empty possession is not "the other side", it is no answer at all.
  assert.equal(Nfl.fieldYard({ live: true, possession: "", yardLine: 33 }, away), null);
});

test("a yard line outside the field is pulled back to the end", () => {
  const at = (yard) => ({ live: true, possession: "LAR", yardLine: yard });
  assert.equal(Nfl.fieldYard(at(0), away), 0);
  assert.equal(Nfl.fieldYard(at(100), away), 100);
  assert.equal(Nfl.fieldYard(at(-4), away), 0);
  assert.equal(Nfl.fieldYard(at(140), away), 100);
  assert.equal(Nfl.fieldYard(at(50.5), away), 50.5);
});
