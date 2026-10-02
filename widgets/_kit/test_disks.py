#!/usr/bin/env python3
"""Regression tests for disks.py volume detection. Stdlib only.

Run from the repo root:  python3 widgets/_kit/test_disks.py
"""

import random
import re
import unittest

import disks


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
           label="LIVEUSB", mountpoint="/run/media/u/LIVEUSB",
           size=2761502720, fsused=2761502720, fssize=2761502720,
           uuid="u1", rm=True)],
     ["LIVEUSB"]),
    ("unmounted iso9660 stays hidden",
     [node(name="sda1", path="/dev/sda1", fstype="iso9660",
           label="LIVEUSB", size=2761502720, uuid="u1", rm=True)],
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
     [node(name="n1", path="/dev/n1", fstype="ntfs", label="Data",
           mountpoint="/run/media/u/Data", size=4000000000000,
           fsused=3600000000000, fssize=4000000000000, uuid="u3")],
     ["Data"]),
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
           mountpoint="/run/media/u/MOVIE", size=8000000000,
           fsused=8000000000, fssize=8000000000, type="rom")],
     ["MOVIE"]),
]


class DetectTest(unittest.TestCase):
    def test_detection_table(self):
        disks.mounts_for_device = lambda dev: []
        for name, nodes, want_labels in CASES:
            with self.subTest(name):
                rows = disks.collapse(disks.walk(nodes))
                self.assertEqual([r["label"] for r in rows], want_labels)


ROW_KEYS = {"device", "source", "path", "label", "fstype", "size",
            "used", "pct", "mounted", "removable"}
MIN_SIZE = 2 * 1024 * 1024 * 1024
SKIP_LABEL = re.compile(r"^(recovery|system reserved|efi|esp|microsoft.*reserved)$", re.I)


class DetectFuzzTest(unittest.TestCase):
    """Random device trees from any imaginable system must satisfy the
    same invariants: no crash, no swap/loop rows, sane numbers."""

    def test_random_trees(self):
        rng = random.Random(20260923)
        disks.mounts_for_device = lambda dev: []
        fss = ["", "ext4", "btrfs", "xfs", "ntfs", "exfat", "vfat",
               "iso9660", "udf", "squashfs", "swap", "crypto_LUKS",
               "LVM2_member", "hfsplus", "weird9"]
        labels = ["", "System", "Data", "Backup", "EFI", "ESP", "Recovery",
                  "System Reserved", "efi", "MYUSB"]
        mpts = ["", "/", "/home", "/boot/efi", "/run/media/u/X",
                "/snap/x", "[SWAP]"]
        counter = [0]

        def mknode(depth):
            counter[0] += 1
            i = counter[0]
            tiny = rng.random() < 0.3
            size = (rng.randrange(1, 300) * 1048576 if tiny
                    else rng.randrange(3, 60) * 1073741824)
            mp = rng.choice(mpts)
            d = {"name": "n%d" % i, "path": "/dev/n%d" % i,
                 "fstype": rng.choice(fss), "label": rng.choice(labels),
                 "mountpoint": mp, "size": size, "fsused": 0, "fssize": 0,
                 "type": rng.choice(["part"] * 8 + ["disk", "loop", "rom",
                                                    "lvm", "crypt"]),
                 "uuid": "u%d" % rng.randrange(1, 5),
                 "hotplug": rng.random() < 0.3, "rm": rng.random() < 0.3,
                 "model": rng.choice(["", "SYSDISK"])}
            if mp and mp != "[SWAP]":
                d["fsused"] = rng.randrange(0, size + 1)
                d["fssize"] = size
            if d["type"] == "disk" and depth < 2 and rng.random() < 0.7:
                d["children"] = [mknode(depth + 1)
                                 for _ in range(rng.randrange(1, 4))]
                for child in d["children"]:
                    child["type"] = "part"
            for key in list(d):
                if key != "name" and rng.random() < 0.05:
                    del d[key]
            return d

        for trial in range(300):
            with self.subTest(trial=trial):
                nodes = [mknode(0) for _ in range(rng.randrange(1, 4))]
                rows = disks.collapse(disks.walk(nodes))
                self.assertEqual(rows, disks.collapse(disks.walk(nodes)))
                for row in rows:
                    self.assertEqual(set(row), ROW_KEYS)
                    self.assertEqual(row["mounted"], bool(row["path"]))
                    if not row["mounted"]:
                        self.assertEqual(row["pct"], 0)
                        self.assertEqual(row["used"], 0)
                    self.assertGreaterEqual(row["pct"], 0)
                    self.assertLessEqual(row["pct"], 100)
                    self.assertLessEqual(row["used"], row["size"])
                    self.assertGreaterEqual(row["size"], MIN_SIZE)
                    self.assertNotEqual(row["fstype"], "swap")
                    self.assertIsNone(SKIP_LABEL.match(row["label"]))


if __name__ == "__main__":
    unittest.main()
