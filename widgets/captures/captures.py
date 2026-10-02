#!/usr/bin/env python3
"""The newest screenshot and screen recording, for the captures tile. Stdlib only.

Folders are the ones Omarchy's capture commands write to:
$OMARCHY_SCREENSHOT_DIR, else XDG_PICTURES_DIR, else ~/Pictures, and
$OMARCHY_SCREENRECORD_DIR, else XDG_VIDEOS_DIR, else ~/Videos. A capture is a
file named the way those commands name them (screenshot-*.png,
screenrecording-*.mp4), so other pictures in the same folder are left alone.
A recording is in progress while gpu-screen-recorder runs.
"""

import json
import os
import re
import struct
import sys
import time

SCREENSHOT = re.compile(r"(?i)^screenshot.*\.(png|jpe?g|webp)$")
RECORDING = re.compile(r"(?i)^screenrecording.*\.(mp4|mkv|webm)$")
RECORDER = "gpu-screen-recorder"
RECORDING_FILE = "/tmp/omarchy-screenrecord-filename"
DAY = 86400


def user_dirs(home, text):
    """XDG_*_DIR values from user-dirs.dirs, with $HOME expanded."""
    out = {}
    for line in (text or "").splitlines():
        match = re.match(r'\s*(XDG_[A-Z]+_DIR)\s*=\s*"(.*)"\s*$', line)
        if match:
            out[match.group(1)] = match.group(2).replace("$HOME", home)
    return out


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return ""


def folders(env=None, home=None):
    env = os.environ if env is None else env
    home = home or os.path.expanduser("~")
    config = env.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    dirs = user_dirs(home, read_text(os.path.join(config, "user-dirs.dirs")))
    shots = env.get("OMARCHY_SCREENSHOT_DIR") or dirs.get("XDG_PICTURES_DIR") or os.path.join(home, "Pictures")
    videos = env.get("OMARCHY_SCREENRECORD_DIR") or dirs.get("XDG_VIDEOS_DIR") or os.path.join(home, "Videos")
    return shots, videos


def scan(folder, pattern):
    """(newest, count today) of the files in folder whose names match."""
    newest = None
    stamps = []
    try:
        entries = list(os.scandir(folder))
    except OSError:
        return None, []
    for entry in entries:
        if not pattern.match(entry.name):
            continue
        try:
            if not entry.is_file():
                continue
            info = entry.stat()
        except OSError:
            continue
        stamps.append(info.st_mtime)
        if newest is None or info.st_mtime > newest["mtime"]:
            newest = {"path": entry.path, "name": entry.name, "mtime": info.st_mtime, "size": info.st_size}
    return newest, stamps


def png_size(path):
    """(width, height) from a PNG's header, or None."""
    try:
        with open(path, "rb") as handle:
            head = handle.read(24)
    except OSError:
        return None
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    width, height = struct.unpack(">II", head[16:24])
    return width, height


def recorder_running(proc="/proc"):
    """True while a gpu-screen-recorder process is alive."""
    try:
        pids = [name for name in os.listdir(proc) if name.isdigit()]
    except OSError:
        return False
    for pid in pids:
        try:
            with open(os.path.join(proc, pid, "cmdline"), "rb") as handle:
                argv0 = handle.read().split(b"\0", 1)[0].decode("utf-8", "replace")
        except OSError:
            continue
        if os.path.basename(argv0) == RECORDER:
            return True
    return False


def recording_started(path=RECORDING_FILE):
    """When the recording in progress began: the time its marker was written."""
    try:
        return os.path.getmtime(path)
    except OSError:
        return None


def today_start(now):
    local = time.localtime(now)
    return time.mktime((local.tm_year, local.tm_mon, local.tm_mday, 0, 0, 0, 0, 0, -1))


def collect(env=None, home=None, now=None, proc="/proc", marker=RECORDING_FILE):
    now = time.time() if now is None else now
    shots_dir, videos_dir = folders(env, home)
    shot, shot_times = scan(shots_dir, SCREENSHOT)
    video, _ = scan(videos_dir, RECORDING)
    midnight = today_start(now)
    if shot:
        size = png_size(shot["path"]) if shot["name"].lower().endswith(".png") else None
        shot["width"], shot["height"] = size if size else (None, None)
    recording = recorder_running(proc)
    return {
        "ok": True,
        "screenshotDir": shots_dir,
        "videoDir": videos_dir,
        "screenshot": shot,
        "recording": video,
        "today": sum(1 for stamp in shot_times if stamp >= midnight),
        "recordingActive": recording,
        "recordingSince": recording_started(marker) if recording else None,
    }


def main():
    json.dump(collect(), sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
