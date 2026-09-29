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

test("the leading side is the one ahead", () => {
  assert.equal(Nfl.isLeader(live, away), true);
  assert.equal(Nfl.isLeader(live, home), false);
  assert.equal(Nfl.isLeader(kickoff, away), false);
  assert.equal(Nfl.isLeader({ away, home }, away), true);
  const tied = { away: { abbr: "LAR", score: 7 }, home: { abbr: "DEN", score: 7 } };
  assert.equal(Nfl.isLeader(tied, tied.away), false);
});

test("the drive reads as down and distance plus field position", () => {
  assert.equal(Nfl.driveLine(live), "2nd & 15  ·  DEN 20");
  assert.equal(Nfl.driveLine({ live: true, downDistance: "3rd & 4", ball: "KC 38" }),
               "3rd & 4  ·  KC 38");
  assert.equal(Nfl.driveLine({ live: true, downDistance: "1st & 10", ball: "" }), "1st & 10");
  assert.equal(Nfl.driveLine({ live: true, downDistance: "", ball: "DET 47" }), "DET 47");
  assert.equal(Nfl.driveLine({ live: true }), "");
  // Nothing before kickoff or after the whistle.
  assert.equal(Nfl.driveLine(kickoff), "");
  assert.equal(Nfl.driveLine(null), "");
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

test("the seed stands on its own", () => {
  assert.equal(Nfl.seedLine({ seed: 1, record: "11-5" }), "#1");
  assert.equal(Nfl.seedLine({ seed: 0, conferenceRank: 9, conference: "NFC" }), "#9 NFC");
  assert.equal(Nfl.seedLine({ conferenceRank: 9 }), "#9");
  assert.equal(Nfl.seedLine({ seed: 7 }), "#7");
  assert.equal(Nfl.seedLine({ record: "3-0" }), "");
  assert.equal(Nfl.seedLine({}), "");
  assert.equal(Nfl.seedLine(null), "");
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

test("the opponent is the side without the favorite", () => {
  assert.equal(Nfl.opponentSide(live), away);
  assert.equal(Nfl.opponentSide({ away, home, favorite: "away" }), home);
  assert.equal(Nfl.opponentSide({ away, home, favorite: "home" }), away);
  assert.equal(Nfl.opponentSide({ away, home }), null);
  assert.equal(Nfl.opponentSide(null), null);
});

test("a final reads from the club's side", () => {
  const mia = { abbr: "MIA", score: 21 };
  const kc = { abbr: "KC", score: 27 };
  assert.equal(Nfl.resultLine({ away: mia, home: kc, favorite: "home", won: "home" }),
               "W 27–21 vs MIA");
  assert.equal(Nfl.resultLine({ away: kc, home: mia, favorite: "away", won: "home" }),
               "L 27–21 @ MIA");
  const tiedAway = { abbr: "MIA", score: 20 };
  const tiedHome = { abbr: "KC", score: 20 };
  assert.equal(Nfl.resultLine({ away: tiedAway, home: tiedHome, favorite: "home", won: "tie" }),
               "T 20–20 vs MIA");
  // Without a favorite there is no W or L to give.
  assert.equal(Nfl.resultLine({ away, home }), "LAR 10  @  DEN 7");
  assert.equal(Nfl.resultLine(null), "");
});

test("a header names the week, or the season", () => {
  assert.equal(Nfl.weekLine({ week: 4, seasonType: 2 }), "WEEK 4");
  assert.equal(Nfl.weekLine({ week: 2, seasonType: 1 }), "PRESEASON");
  assert.equal(Nfl.weekLine({ seasonType: 3 }), "PLAYOFFS");
  assert.equal(Nfl.weekLine({}), "");
  assert.equal(Nfl.weekLine(null), "");
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

test("the ball sits on one number from the offence's goal", () => {
  // ESPN measures the line of scrimmage from the offence's own goal line,
  // and the strip is drawn from that same perspective, so their 33 is 33.
  const driving = { live: true, possession: "LAR", yardLine: 33 };
  assert.equal(Nfl.ballYard(driving), 33);
  assert.equal(Nfl.ballYard({ live: true, possession: "DEN", yardLine: 67 }), 67);
  assert.equal(Nfl.isOffense(driving, away), true);
  assert.equal(Nfl.isOffense(driving, home), false);
  assert.equal(Nfl.hasField(driving), true);
});

test("the field is absent rather than wrong", () => {
  // No possession, no line, or a game that is not running means there is no
  // field to draw, and inventing one would put a ball where nobody is.
  for (const game of [null, {}, { live: false, possession: "LAR", yardLine: 33 },
                      { live: true, yardLine: 33 },
                      { live: true, possession: "LAR" },
                      { live: true, possession: "LAR", yardLine: null },
                      { live: true, possession: "LAR", yardLine: "x" },
                      // An empty possession is not "the other side".
                      { live: true, possession: "", yardLine: 33 }]) {
    assert.equal(Nfl.hasField(game), false, JSON.stringify(game));
    assert.equal(Nfl.ballYard(game), null);
  }
});

test("a yard line outside the field is pulled back to the end", () => {
  const at = (yard) => ({ live: true, possession: "LAR", yardLine: yard });
  assert.equal(Nfl.ballYard(at(0)), 0);
  assert.equal(Nfl.ballYard(at(100)), 100);
  assert.equal(Nfl.ballYard(at(-4)), 0);
  assert.equal(Nfl.ballYard(at(140)), 100);
  assert.equal(Nfl.ballYard(at(50.5)), 50.5);
});
