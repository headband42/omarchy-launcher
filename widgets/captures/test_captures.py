#!/usr/bin/env python3
"""Tests for the captures sampler. Stdlib only; works on a temporary folder.

Run from the repo root:  python3 widgets/captures/test_captures.py
"""

import os
import struct
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import captures


def png(path, width, height, mtime):
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", width, height) + b"\x08\x06\x00\x00\x00")
    os.utime(path, (mtime, mtime))


class FolderTests(unittest.TestCase):
    def test_user_dirs_expands_home(self):
        text = 'XDG_PICTURES_DIR="$HOME/Pics"\n# comment\nXDG_VIDEOS_DIR="/media/v"\n'
        self.assertEqual(captures.user_dirs("/home/u", text), {"XDG_PICTURES_DIR": "/home/u/Pics", "XDG_VIDEOS_DIR": "/media/v"})

    def test_omarchy_env_wins(self):
        with tempfile.TemporaryDirectory() as home:
            os.makedirs(os.path.join(home, ".config"))
            with open(os.path.join(home, ".config", "user-dirs.dirs"), "w") as handle:
                handle.write('XDG_PICTURES_DIR="$HOME/Bilder"\n')
            self.assertEqual(captures.folders({}, home), (os.path.join(home, "Bilder"), os.path.join(home, "Videos")))
            env = {"OMARCHY_SCREENSHOT_DIR": "/shots", "OMARCHY_SCREENRECORD_DIR": "/recs"}
            self.assertEqual(captures.folders(env, home), ("/shots", "/recs"))

    def test_defaults_without_user_dirs(self):
        self.assertEqual(captures.folders({}, "/nowhere"), ("/nowhere/Pictures", "/nowhere/Videos"))


class ScanTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.home = self.dir.name
        self.pics = os.path.join(self.home, "Pictures")
        self.videos = os.path.join(self.home, "Videos")
        os.makedirs(self.pics)
        os.makedirs(self.videos)

    def tearDown(self):
        self.dir.cleanup()

    def test_newest_screenshot_and_today_count(self):
        now = time.time()
        png(os.path.join(self.pics, "screenshot-old.png"), 10, 10, now - 3 * 86400)
        png(os.path.join(self.pics, "screenshot-new.png"), 1920, 1080, now - 5)
        png(os.path.join(self.pics, "holiday.png"), 10, 10, now)
        os.makedirs(os.path.join(self.pics, "screenshot-folder.png"))
        out = captures.collect({}, self.home, now, proc=self.home, marker="/nonexistent")
        self.assertEqual(out["screenshot"]["name"], "screenshot-new.png")
        self.assertEqual((out["screenshot"]["width"], out["screenshot"]["height"]), (1920, 1080))
        self.assertEqual(out["today"], 1)
        self.assertIsNone(out["recording"])
        self.assertFalse(out["recordingActive"])

    def test_missing_folders(self):
        out = captures.collect({"OMARCHY_SCREENSHOT_DIR": "/nope/a", "OMARCHY_SCREENRECORD_DIR": "/nope/b"}, self.home, proc=self.home)
        self.assertIsNone(out["screenshot"])
        self.assertEqual(out["today"], 0)

    def test_recording_files(self):
        path = os.path.join(self.videos, "screenrecording-2026.mp4")
        with open(path, "wb") as handle:
            handle.write(b"x" * 10)
        with open(os.path.join(self.videos, "movie.mp4"), "wb") as handle:
            handle.write(b"x")
        out = captures.collect({}, self.home, proc=self.home)
        self.assertEqual(out["recording"]["name"], "screenrecording-2026.mp4")
        self.assertEqual(out["recording"]["size"], 10)

    def test_png_size_rejects_other_files(self):
        path = os.path.join(self.pics, "screenshot-x.jpg")
        with open(path, "wb") as handle:
            handle.write(b"\xff\xd8\xff" + b"0" * 30)
        self.assertIsNone(captures.png_size(path))
        self.assertIsNone(captures.png_size("/nonexistent"))


class RecorderTests(unittest.TestCase):
    def test_recorder_found_in_proc(self):
        with tempfile.TemporaryDirectory() as proc:
            for pid, argv in (("12", b"bash\0-c\0x\0"), ("40", b"/usr/bin/gpu-screen-recorder\0-w\0region\0"), ("self", b"x")):
                os.makedirs(os.path.join(proc, pid))
                with open(os.path.join(proc, pid, "cmdline"), "wb") as handle:
                    handle.write(argv)
            self.assertTrue(captures.recorder_running(proc))

    def test_recorder_not_running(self):
        with tempfile.TemporaryDirectory() as proc:
            os.makedirs(os.path.join(proc, "7"))
            with open(os.path.join(proc, "7", "cmdline"), "wb") as handle:
                handle.write(b"pgrep\0-f\0gpu-screen-recorder\0")
            self.assertFalse(captures.recorder_running(proc))
            self.assertFalse(captures.recorder_running("/nonexistent"))

    def test_recording_since_comes_from_the_marker(self):
        with tempfile.TemporaryDirectory() as proc:
            os.makedirs(os.path.join(proc, "40"))
            with open(os.path.join(proc, "40", "cmdline"), "wb") as handle:
                handle.write(b"gpu-screen-recorder\0")
            marker = os.path.join(proc, "marker")
            with open(marker, "w") as handle:
                handle.write("/x.mp4")
            os.utime(marker, (1000, 1000))
            out = captures.collect({}, proc, proc=proc, marker=marker)
            self.assertTrue(out["recordingActive"])
            self.assertEqual(out["recordingSince"], 1000)


if __name__ == "__main__":
    unittest.main()
