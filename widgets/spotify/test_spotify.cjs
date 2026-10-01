#!/usr/bin/env node
// Logic tests for the Spotify widget. Stdlib only.
//
// Run from the repo root:  node --test widgets/spotify/test_spotify.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const S = require("./spotify.js");

const omaspotify = {
  dbusName: "org.mpris.MediaPlayer2.OmaSpotify.instance192429",
  desktopEntry: "omaspotify",
  identity: "OmaSpotify (librespot)",
  isPlaying: false,
};
const official = { dbusName: "org.mpris.MediaPlayer2.spotify", desktopEntry: "spotify", identity: "Spotify", isPlaying: false };
const spotifyd = { dbusName: "org.mpris.MediaPlayer2.spotifyd", desktopEntry: "", identity: "librespot", isPlaying: false };
const browser = { dbusName: "org.mpris.MediaPlayer2.brave.instance42356", desktopEntry: "brave-browser", identity: "Brave", isPlaying: true };

test("recognizes Spotify players and skips browsers", () => {
  assert.equal(S.isSpotifyPlayer(omaspotify), true);
  assert.equal(S.isSpotifyPlayer(official), true);
  assert.equal(S.isSpotifyPlayer(spotifyd), true);
  assert.equal(S.isSpotifyPlayer(browser), false);
  assert.equal(S.isSpotifyPlayer(null), false);
});

test("only librespot backends count as the local engine", () => {
  assert.equal(S.isLocalEngine(omaspotify), true);
  assert.equal(S.isLocalEngine(spotifyd), true);
  assert.equal(S.isLocalEngine(official), false);
});

test("picks OmaSpotify over the official client when neither plays", () => {
  assert.equal(S.pickPlayer([browser, official, omaspotify]), omaspotify);
});

test("picks whichever Spotify player is playing", () => {
  const playing = { ...official, isPlaying: true };
  assert.equal(S.pickPlayer([omaspotify, playing]), playing);
});

test("returns null with no Spotify player", () => {
  assert.equal(S.pickPlayer([browser]), null);
  assert.equal(S.pickPlayer([]), null);
  assert.equal(S.pickPlayer(undefined), null);
});

test("formats track times", () => {
  assert.equal(S.fmtTime(0), "0:00");
  assert.equal(S.fmtTime(9.9), "0:09");
  assert.equal(S.fmtTime(193.826), "3:13");
  assert.equal(S.fmtTime(3600 + 62), "1:01:02");
  assert.equal(S.fmtTime(-5), "0:00");
  assert.equal(S.fmtTime(NaN), "0:00");
});

test("clamps progress", () => {
  assert.equal(S.progress(30, 120), 0.25);
  assert.equal(S.progress(200, 120), 1);
  assert.equal(S.progress(-1, 120), 0);
  assert.equal(S.progress(10, 0), 0);
});

test("maps a click on the bar to a position", () => {
  assert.equal(S.seekTarget(50, 200, 180), 45);
  assert.equal(S.seekTarget(250, 200, 180), 180);
  assert.equal(S.seekTarget(-4, 200, 180), 0);
  assert.equal(S.seekTarget(10, 0, 180), 0);
});

test("cycles repeat off, context, track", () => {
  const NONE = 0, TRACK = 1, PLAYLIST = 2;
  assert.equal(S.nextLoop(NONE, NONE, PLAYLIST, TRACK), PLAYLIST);
  assert.equal(S.nextLoop(PLAYLIST, NONE, PLAYLIST, TRACK), TRACK);
  assert.equal(S.nextLoop(TRACK, NONE, PLAYLIST, TRACK), NONE);
});
