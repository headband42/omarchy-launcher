#!/usr/bin/env node
// Logic tests for the media tile. Stdlib only.
//
// Run from the repo root:  node --test widgets/media/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Media = require("./media.js");

const firefox = { dbusName: "org.mpris.MediaPlayer2.firefox.instance_1_23", identity: "Firefox", trackTitle: "A talk", isPlaying: false, canControl: true };
const mpv = { dbusName: "org.mpris.MediaPlayer2.mpv", identity: "mpv", trackTitle: "movie.mkv", isPlaying: true, canControl: true };
const idle = { dbusName: "org.mpris.MediaPlayer2.chromium.instance99", identity: "", trackTitle: "", isPlaying: false, canControl: true };
const spotify = { dbusName: "org.mpris.MediaPlayer2.spotify", identity: "Spotify", trackTitle: "Song", isPlaying: false, canControl: true };

test("playing wins, then a loaded track, then MPRIS order", () => {
  assert.equal(Media.pickPlayer([idle, firefox, mpv], ""), mpv);
  assert.equal(Media.pickPlayer([idle, firefox, spotify], ""), firefox);
  assert.equal(Media.pickPlayer([idle], ""), idle);
  assert.equal(Media.pickPlayer([], ""), null);
  assert.equal(Media.pickPlayer(null, ""), null);
});

test("a pinned player wins while it has a track", () => {
  assert.equal(Media.pickPlayer([firefox, mpv], Media.playerKey(firefox)), firefox);
  assert.equal(Media.pickPlayer([idle, mpv], Media.playerKey(idle)), mpv);
  assert.equal(Media.pickPlayer([firefox, mpv], "gone"), mpv);
});

test("switching cycles players with a track", () => {
  const players = [firefox, idle, mpv, spotify];
  assert.equal(Media.switchable(players).length, 3);
  const first = Media.playerKey(Media.pickPlayer(players, ""));
  assert.equal(first, Media.playerKey(mpv));
  const second = Media.nextKey(players, first);
  assert.equal(second, Media.playerKey(firefox));
  const third = Media.nextKey(players, second);
  assert.equal(third, Media.playerKey(spotify));
  assert.equal(Media.nextKey(players, third), first);
  assert.equal(Media.nextKey([idle], ""), "");
});

test("reads a Quickshell-style list", () => {
  assert.equal(Media.pickPlayer({ length: 2, 0: firefox, 1: mpv }, ""), mpv);
});

test("player names", () => {
  assert.equal(Media.playerName(firefox), "Firefox");
  assert.equal(Media.playerName(idle), "Chromium");
  assert.equal(Media.playerName({ desktopEntry: "org.gnome.Rhythmbox3" }), "Rhythmbox3");
  assert.equal(Media.playerName(null), "");
});

test("artist line", () => {
  assert.equal(Media.artistLine("M83", "Hurry Up"), "M83 · Hurry Up");
  assert.equal(Media.artistLine("", "Album"), "Album");
  assert.equal(Media.artistLine(" ", ""), "");
});

test("times and progress", () => {
  assert.equal(Media.fmtTime(0), "0:00");
  assert.equal(Media.fmtTime(65.9), "1:05");
  assert.equal(Media.fmtTime(3725), "1:02:05");
  assert.equal(Media.progress(30, 120), 0.25);
  assert.equal(Media.progress(200, 120), 1);
  assert.equal(Media.progress(10, 0), 0);
  assert.equal(Media.seekTarget(50, 200, 120), 30);
  assert.equal(Media.seekTarget(50, 0, 120), 0);
});

test("volume steps stay in range", () => {
  assert.equal(Media.stepVolume(0.5, 120), 0.55);
  assert.equal(Media.stepVolume(0.5, -120), 0.45);
  assert.equal(Media.stepVolume(0.98, 120), 1);
  assert.equal(Media.stepVolume(0.02, -120), 0);
  assert.equal(Media.stepVolume(NaN, 120), 0.05);
  assert.equal(Media.stepVolume(0.5, 0), 0.5);
});
