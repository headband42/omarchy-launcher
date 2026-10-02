// Logic tests for the NFL tile's formatters. Stdlib only.
//
// nfl.js is the shipped file that Widget.qml and Settings.qml import, so this
// exercises that exact code rather than a copy of it.
//
// Run from the repo root:  node --test widgets/nfl/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Nfl = require("./nfl.js");

const away = { id: 14, abbr: "LAR", city: "Los Angeles", nickname: "Rams", score: 10, record: "1-1",
               color: "#003594", alt: "#ffd100", timeouts: 2, lines: [3, 7] };
const home = { id: 7, abbr: "DEN", city: "Denver", nickname: "Broncos", score: 7, record: "1-1",
               color: "#0a2343", alt: "#fc4c02", timeouts: 3, lines: [7, 0] };

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
  fieldYard: 20,
  firstDownYard: 35,
  winChance: { away: 41, home: 59 },
  lastPlay: "  (Shotgun) M.Stafford  pass incomplete   short left. ",
  network: "NBC",
  neutral: false,
  favorite: "home",
  week: 3,
  seasonType: 2,
  away,
  home,
};

const kickoff = {
  id: "401872976",
  url: "https://www.nfl.com/games/raiders-at-chiefs-2026-reg-4",
  state: "pre",
  live: false,
  finished: false,
  time: "OCT 4 8:25 PM",
  day: "OCT 4",
  dateLabel: "SUN OCT 4",
  kickoff: "8:25 PM",
  network: "FOX",
  venue: "GEHA Field at Arrowhead Stadium",
  city: "Kansas City",
  odds: "KC -6.5",
  overUnder: 47.5,
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

test("the leading side is the one ahead, and the other one reads quieter", () => {
  assert.equal(Nfl.isLeader(live, away), true);
  assert.equal(Nfl.isLeader(live, home), false);
  assert.equal(Nfl.isLeader(kickoff, kickoff.away), false);
  assert.equal(Nfl.trailing(live, home), true);
  assert.equal(Nfl.trailing(live, away), false);
  // Before kickoff nobody is behind, even with a stray score.
  assert.equal(Nfl.trailing({ away, home }, home), false);
  const tied = { live: true, away: { abbr: "LAR", score: 7 }, home: { abbr: "DEN", score: 7 } };
  assert.equal(Nfl.isLeader(tied, tied.away), false);
  assert.equal(Nfl.trailing(tied, tied.away), false);
});

test("the drive reads as down and distance plus field position", () => {
  assert.equal(Nfl.driveLine(live), "2nd & 15 · DEN 20");
  assert.equal(Nfl.driveLine({ live: true, downDistance: "1st & 10", ball: "" }), "1st & 10");
  assert.equal(Nfl.driveLine({ live: true, downDistance: "", ball: "DET 47" }), "DET 47");
  assert.equal(Nfl.driveLine({ live: true }), "");
  // Nothing before kickoff or after the whistle.
  assert.equal(Nfl.driveLine(kickoff), "");
  assert.equal(Nfl.driveLine(null), "");
});

test("win probability names whoever is favored", () => {
  assert.equal(Nfl.winLine(live), "DEN 59%");
  assert.equal(Nfl.winLine({ ...live, winChance: { away: 80, home: 20 } }), "LAR 80%");
  assert.equal(Nfl.winLine({ ...live, winChance: { away: 50, home: 50 } }), "");
  assert.equal(Nfl.winLine({ ...live, winChance: null }), "");
  assert.equal(Nfl.winLine(kickoff), "");
});

test("the last play collapses its whitespace and drops the formation", () => {
  assert.equal(Nfl.lastPlay(live), "M.Stafford pass incomplete short left.");
  assert.equal(Nfl.lastPlay({ live: true, lastPlay: "J.Allen kneels." }), "J.Allen kneels.");
  assert.equal(Nfl.lastPlay(kickoff), "");
  assert.equal(Nfl.lastPlay(null), "");
});

test("kickoff lines name the day only when it helps", () => {
  assert.equal(Nfl.kickoffLine(live), "2nd 6:33");
  assert.equal(Nfl.kickoffLine(kickoff), "OCT 4 8:25 PM");
  assert.equal(Nfl.kickoffLine({ day: "TODAY", kickoff: "1:00 PM" }), "1:00 PM");
  assert.equal(Nfl.kickoffLine({ day: "SUN", kickoff: "4:25 PM" }), "SUN 4:25 PM");
  assert.equal(Nfl.kickoffLine({ finished: true }), "FINAL");
  assert.equal(Nfl.kickoffLine({ finished: true, overtime: true }), "FINAL/OT");
  assert.equal(Nfl.kickoffLine(null), "");
});

test("the next-game card gives the date as well as the weekday", () => {
  assert.equal(Nfl.whenLine(kickoff), "SUN OCT 4 · 8:25 PM");
  assert.equal(Nfl.whenLine({ ...kickoff, day: "TODAY" }), "TODAY · 8:25 PM");
  assert.equal(Nfl.whenLine({ ...kickoff, day: "TOM" }), "TOMORROW · 8:25 PM");
  assert.equal(Nfl.whenLine({ day: "SUN", kickoff: "" }), "SUN");
  assert.equal(Nfl.whenLine(null), "");
});

test("the line, the total and the venue read the way a book and a ticket do", () => {
  assert.equal(Nfl.oddsLine(kickoff), "KC −6.5 · O/U 47.5");
  assert.equal(Nfl.oddsLine({ odds: "EVEN" }), "EVEN");
  assert.equal(Nfl.oddsLine({ overUnder: 41 }), "O/U 41");
  assert.equal(Nfl.oddsLine({ odds: "", overUnder: null }), "");
  assert.equal(Nfl.oddsLine(null), "");
  assert.equal(Nfl.venueLine(kickoff), "GEHA Field at Arrowhead Stadium");
  assert.equal(Nfl.venueLine({ venue: "Tottenham Hotspur Stadium", city: "London", neutral: true }),
               "Tottenham Hotspur Stadium, London");
  assert.equal(Nfl.venueLine({ city: "Chicago" }), "Chicago");
  assert.equal(Nfl.venueLine(null), "");
});

test("the seed stands on its own", () => {
  assert.equal(Nfl.seedLine({ seed: 1, record: "11-5" }), "#1");
  assert.equal(Nfl.seedLine({ seed: 7 }), "#7");
  assert.equal(Nfl.seedLine({ seed: 0 }), "");
  assert.equal(Nfl.seedLine({ record: "3-0" }), "");
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

test("the club name is uppercased for the season card", () => {
  assert.equal(Nfl.teamLine({ city: "Kansas City", nickname: "Chiefs" }), "KANSAS CITY CHIEFS");
  assert.equal(Nfl.teamLine({ city: "", nickname: "Raiders" }), "RAIDERS");
  assert.equal(Nfl.teamLine({ abbr: "WSH" }), "WSH");
  assert.equal(Nfl.teamLine(null), "");
});

test("the opponent reads from the club's side", () => {
  assert.equal(Nfl.opponentLine(live), "vs LAR");
  assert.equal(Nfl.opponentLine({ away, home, favorite: "away" }), "@ DEN");
  assert.equal(Nfl.opponentLine({ away, home }), "LAR @ DEN");
  assert.equal(Nfl.opponentLine(null), "");
});

test("a slate row has no score before kickoff", () => {
  assert.equal(Nfl.boardLine(live), "LAR 10 @ DEN 7");
  assert.equal(Nfl.boardLine(kickoff), "LV @ KC");
  assert.equal(Nfl.boardLine(null), "");
  assert.equal(Nfl.boardState(live), "2nd 6:33");
  assert.equal(Nfl.boardState(kickoff), "OCT 4 8:25 PM");
  assert.equal(Nfl.boardState(kickoff, true), "OCT 4 8:25p");
  assert.equal(Nfl.boardState({ day: "SUN", kickoff: "9:30 AM" }, true), "SUN 9:30a");
  assert.equal(Nfl.boardState({ finished: true }), "FINAL");
  assert.equal(Nfl.boardState({ finished: true, overtime: true }), "F/OT");
  assert.equal(Nfl.boardState(null), "");
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
  assert.equal(Nfl.resultLine({ live: true, away, home }), "LAR 10 @ DEN 7");
  assert.equal(Nfl.resultLine(null), "");
});

test("a header names the week, the preseason, or the playoff round", () => {
  assert.equal(Nfl.weekLine({ week: 4, seasonType: 2 }), "WEEK 4");
  assert.equal(Nfl.weekLine({ week: 2, seasonType: 1 }), "PRESEASON WK 2");
  assert.equal(Nfl.weekLine({ seasonType: 1 }), "PRESEASON");
  assert.equal(Nfl.weekLine({ week: 1, seasonType: 3 }), "WILD CARD");
  assert.equal(Nfl.weekLine({ week: 5, seasonType: 3 }), "SUPER BOWL");
  assert.equal(Nfl.weekLine({ seasonType: 3 }), "PLAYOFFS");
  assert.equal(Nfl.weekLine({}), "");
  assert.equal(Nfl.weekLine(null), "");
});

test("the line score pads to four quarters and names overtime", () => {
  const table = Nfl.lineTable(live);
  assert.deepEqual(table.labels, ["1", "2", "3", "4"]);
  assert.deepEqual(table.away, ["3", "7", "", ""]);
  assert.deepEqual(table.home, ["7", "0", "", ""]);
  assert.equal(table.played, 2);

  const long = Nfl.lineTable({ away: { lines: [0, 7, 3, 7, 0, 3] }, home: { lines: [7, 0, 7, 3, 0, 0] } });
  assert.deepEqual(long.labels, ["1", "2", "3", "4", "OT", "2OT"]);
  assert.equal(long.played, 6);

  const none = Nfl.lineTable(kickoff);
  assert.deepEqual(none.away, ["", "", "", ""]);
  assert.equal(none.played, 0);
  assert.equal(Nfl.lineTable(null).played, 0);
});

test("leaders and the division table skip anything half-filled", () => {
  const game = { leaders: [
    { cat: "PASS", name: "J. Allen", team: "BUF", line: "24/31, 281 YDS" },
    { cat: "RUSH", name: "", team: "BUF", line: "12 CAR" },
    null,
    { cat: "REC", name: "K. Shakir", team: "BUF", line: "7 REC, 92 YDS" },
    { cat: "XTRA", name: "Extra", team: "BUF", line: "1" },
  ] };
  assert.deepEqual(Nfl.leaderRows(game).map((row) => row.cat), ["PASS", "REC", "XTRA"]);
  assert.deepEqual(Nfl.leaderRows(null), []);

  const team = { table: [{ abbr: "MIN" }, { abbr: "" }, null, { abbr: "DET" }, { abbr: "CHI" }, { abbr: "GB" }, { abbr: "XX" }] };
  assert.deepEqual(Nfl.divisionRows(team).map((row) => row.abbr), ["MIN", "DET", "CHI", "GB"]);
  assert.deepEqual(Nfl.divisionRows(null), []);
});

test("timeouts are 0 to 3, or unknown", () => {
  assert.equal(Nfl.timeoutsLeft(away), 2);
  assert.equal(Nfl.timeoutsLeft({ timeouts: 9 }), 3);
  assert.equal(Nfl.timeoutsLeft({ timeouts: -1 }), 0);
  assert.equal(Nfl.timeoutsLeft({ timeouts: null }), -1);
  assert.equal(Nfl.timeoutsLeft({}), -1);
  assert.equal(Nfl.timeoutsLeft(null), -1);
});

test("the ball and the line to gain sit on the offence's own scale", () => {
  // nfl.py has already turned "DEN 20" into yards from Denver's goal line.
  assert.deepEqual(Nfl.fieldMarks(live), { ball: 20, line: 35 });
  assert.deepEqual(Nfl.fieldMarks({ ...live, firstDownYard: null }), { ball: 20, line: null });
  assert.deepEqual(Nfl.fieldMarks({ ...live, fieldYard: 140, firstDownYard: 150 }), { ball: 100, line: 100 });
  assert.equal(Nfl.isOffense(live, home), true);
  assert.equal(Nfl.isOffense(live, away), false);
});

test("the field is absent rather than wrong", () => {
  // No possession, no spot, or a game that is not running means there is no
  // field to draw, and inventing one would put a ball where nobody is.
  for (const game of [null, {}, { ...live, live: false },
                      { ...live, possession: "" },
                      { ...live, fieldYard: null },
                      { ...live, fieldYard: "x" }]) {
    assert.equal(Nfl.fieldMarks(game), null, JSON.stringify(game));
  }
  assert.equal(Nfl.isOffense({ ...live, possession: "" }, away), false);
});

test("club colors give way when they vanish into the tile", () => {
  const navy = "#05182e";
  // Chicago's navy is the tile's navy; its orange is not.
  assert.equal(Nfl.tint({ color: "#0b1c3a", alt: "#e64100" }, navy, "#f0d9b0"), "#e64100");
  // Kansas City's red reads fine as it is.
  assert.equal(Nfl.tint({ color: "#e31837", alt: "#ffb612" }, navy, "#f0d9b0"), "#e31837");
  // Neither color reads, so the ink does.
  assert.equal(Nfl.tint({ color: "#0b1c3a", alt: "#000000" }, navy, "#f0d9b0"), "#f0d9b0");
  assert.equal(Nfl.tint(null, navy, "#f0d9b0"), "#f0d9b0");
  assert.equal(Nfl.inkOn("#ffffff"), "#111111");
  assert.equal(Nfl.inkOn("#0b1c3a"), "#ffffff");
  assert.equal(Nfl.inkOn("bad"), "#ffffff");
  assert.equal(Nfl.colorHex({ r: 1, g: 0.5, b: 0 }), "#ff8000");
  assert.equal(Nfl.isDark(navy), true);
  assert.equal(Nfl.isDark("#fafafa"), false);
});

test("logos switch to the dark-background mark only where ESPN drew one", () => {
  assert.equal(Nfl.logoPath({ abbr: "NYJ" }, true), "logos/dark/NYJ.png");
  assert.equal(Nfl.logoPath({ abbr: "NYJ" }, false), "logos/NYJ.png");
  assert.equal(Nfl.logoPath({ abbr: "CHI" }, true), "logos/CHI.png");
  // Anything that is not a ticker never becomes a path.
  assert.equal(Nfl.logoPath({ abbr: "../x" }, true), "");
  assert.equal(Nfl.logoPath({ abbr: "" }, true), "");
  assert.equal(Nfl.logoPath(null, true), "");

  const fs = require("node:fs");
  const path = require("node:path");
  for (const abbr of Object.keys(Nfl.DARK_LOGOS)) {
    assert.ok(fs.existsSync(path.join(__dirname, "logos", "dark", abbr + ".png")), abbr);
    assert.ok(fs.existsSync(path.join(__dirname, "logos", abbr + ".png")), abbr);
  }
});

test("the placeholder says something useful", () => {
  assert.equal(Nfl.emptyHeadline("empty", "error", true), "Scores unavailable");
  assert.equal(Nfl.emptyHeadline("closed", "", true), "Season complete");
  assert.equal(Nfl.emptyHeadline("upcoming", "", true), "No game found");
  assert.equal(Nfl.emptyHeadline("empty", "", true), "No games this week");
  assert.equal(Nfl.emptyBody("empty", "error", true), "ESPN did not answer. The tile tries again on its own.");
  assert.equal(Nfl.emptyBody("closed", "", true), "Nothing left on the schedule.");
  assert.equal(Nfl.emptyBody("upcoming", "", true), "Choose a club in settings.");
  // Before the first fetch the tile is still working, not idle.
  assert.equal(Nfl.emptyHeadline("", "", false), "NFL");
  assert.equal(Nfl.emptyBody("", "", false), "Fetching the schedule…");
});

test("the football glyph is the Material Design one the menu font carries", () => {
  assert.equal(Nfl.FOOTBALL.codePointAt(0), 0xf025d);
});
