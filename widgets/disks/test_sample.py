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


class DetectTest(unittest.TestCase):
    def rows(self, nodes):
        sample.mounts_for_device = lambda dev: []
        return sample.collapse(sample.walk(nodes))

    def labels(self, nodes):
        return [r["label"] for r in self.rows(nodes)]

    def test_mounted_iso9660_usb_shows(self):
        nodes = [node(name="sda1", path="/dev/sda1", fstype="iso9660",
                      label="MANJARO", mountpoint="/run/media/ande/MANJARO",
                      size=2761502720, fsused=2761502720, fssize=2761502720,
                      uuid="u1", rm=True)]
        self.assertEqual(self.labels(nodes), ["MANJARO"])

    def test_unmounted_iso9660_stays_hidden(self):
        nodes = [node(name="sda1", path="/dev/sda1", fstype="iso9660",
                      label="MANJARO", size=2761502720, uuid="u1", rm=True)]
        self.assertEqual(self.rows(nodes), [])

    def test_superfloppy_usb_shows(self):
        nodes = [{"name": "sdb", "path": "/dev/sdb", "fstype": "exfat",
                  "label": "", "mountpoint": "", "size": 16000000000,
                  "fsused": 0, "fssize": 0, "type": "disk", "uuid": "u2",
                  "hotplug": True, "rm": True, "model": "Flash"}]
        self.assertEqual(self.labels(nodes), ["Flash"])

    def test_snap_loop_never_shows(self):
        nodes = [node(name="loop0", path="/dev/loop0", fstype="squashfs",
                      mountpoint="/snap/core/1", size=100000000, type="loop")]
        self.assertEqual(self.rows(nodes), [])

    def test_swap_pseudo_mount_never_shows(self):
        nodes = [node(name="zram0", path="/dev/zram0", fstype="swap",
                      mountpoint="[SWAP]", size=8000000000, type="disk")]
        self.assertEqual(self.rows(nodes), [])

    def test_mounted_ntfs_data_shows(self):
        nodes = [node(name="n1", path="/dev/n1", fstype="ntfs", label="Games",
                      mountpoint="/run/media/ande/Games", size=4000000000000,
                      fsused=3600000000000, fssize=4000000000000, uuid="u3")]
        self.assertEqual(self.labels(nodes), ["Games"])

    def test_internal_esp_stays_hidden(self):
        nodes = [node(name="e1", path="/dev/e1", fstype="vfat", label="ESP",
                      mountpoint="/boot/efi", size=500000000)]
        self.assertEqual(self.rows(nodes), [])

    def test_tiny_usb_stub_stays_hidden(self):
        nodes = [node(name="sda2", path="/dev/sda2", fstype="vfat",
                      label="MISO_EFI", size=4194304, rm=True)]
        self.assertEqual(self.rows(nodes), [])

    def test_mounted_udf_dvd_shows(self):
        nodes = [node(name="sr0", path="/dev/sr0", fstype="udf", label="MOVIE",
                      mountpoint="/run/media/ande/MOVIE", size=8000000000,
                      fsused=8000000000, fssize=8000000000, type="rom")]
        self.assertEqual(self.labels(nodes), ["MOVIE"])


if __name__ == "__main__":
    unittest.main()
