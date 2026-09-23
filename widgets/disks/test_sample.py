#!/usr/bin/env python3
"""Regression tests for sample.py volume detection. Stdlib only.

Run from the repo root:  python3 widgets/disks/test_sample.py
"""

import unittest

import sample


def node(**kw):
    base = {"name": "x", "path": "/dev/x", "fstype": "", "label": "",
            "mountpoint": "", "size": 0, "fsused": 0, "fssize": 0,
            "type": "part", "uuid": "", "hotplug": False, "rm": False,
            "model": ""}
    base.update(kw)
    return base


CASES = [
    ("mounted iso9660 USB shows",
     [node(name="sda1", path="/dev/sda1", fstype="iso9660",
           label="MANJARO", mountpoint="/run/media/ande/MANJARO",
           size=2761502720, fsused=2761502720, fssize=2761502720,
           uuid="u1", rm=True)],
     ["MANJARO"]),
    ("unmounted iso9660 stays hidden",
     [node(name="sda1", path="/dev/sda1", fstype="iso9660",
           label="MANJARO", size=2761502720, uuid="u1", rm=True)],
     []),
    ("superfloppy USB shows",
     [{"name": "sdb", "path": "/dev/sdb", "fstype": "exfat",
       "label": "", "mountpoint": "", "size": 16000000000,
       "fsused": 0, "fssize": 0, "type": "disk", "uuid": "u2",
       "hotplug": True, "rm": True, "model": "Flash"}],
     ["Flash"]),
    ("snap loop never shows",
     [node(name="loop0", path="/dev/loop0", fstype="squashfs",
           mountpoint="/snap/core/1", size=100000000, type="loop")],
     []),
    ("swap pseudo-mount never shows",
     [node(name="zram0", path="/dev/zram0", fstype="swap",
           mountpoint="[SWAP]", size=8000000000, type="disk")],
     []),
    ("mounted ntfs data shows",
     [node(name="n1", path="/dev/n1", fstype="ntfs", label="Games",
           mountpoint="/run/media/ande/Games", size=4000000000000,
           fsused=3600000000000, fssize=4000000000000, uuid="u3")],
     ["Games"]),
    ("internal ESP stays hidden",
     [node(name="e1", path="/dev/e1", fstype="vfat", label="ESP",
           mountpoint="/boot/efi", size=500000000)],
     []),
    ("tiny USB stub stays hidden",
     [node(name="sda2", path="/dev/sda2", fstype="vfat",
           label="MISO_EFI", size=4194304, rm=True)],
     []),
    ("mounted udf DVD shows",
     [node(name="sr0", path="/dev/sr0", fstype="udf", label="MOVIE",
           mountpoint="/run/media/ande/MOVIE", size=8000000000,
           fsused=8000000000, fssize=8000000000, type="rom")],
     ["MOVIE"]),
]


class DetectTest(unittest.TestCase):
    def test_detection_table(self):
        sample.mounts_for_device = lambda dev: []
        for name, nodes, want_labels in CASES:
            with self.subTest(name):
                rows = sample.collapse(sample.walk(nodes))
                self.assertEqual([r["label"] for r in rows], want_labels)


if __name__ == "__main__":
    unittest.main()
