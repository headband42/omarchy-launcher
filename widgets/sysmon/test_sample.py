#!/usr/bin/env python3
"""Tests for the sysmon sampler. Stdlib only.

Run from the repo root:  python3 widgets/sysmon/test_sample.py
"""

import json
import os
import random
import re
import subprocess
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


def sampler_functions(command_text=""):
    """Exec the pure-python helpers shipped inside sample.sh with a
    stubbed subprocess, so the parsers are tested against the real
    code without needing root or hardware."""

    class Out:
        def __init__(self, text):
            self.stdout = text

    class FakeSubprocess:
        class SubprocessError(Exception):
            pass

        def run(self, *args, **kwargs):
            return Out(command_text)

    src = (HERE / "sample.sh").read_text()
    code = src[src.index("def fmt_gb(mb):"):src.index("cpu_model, cpu_threads")]
    ns = {"json": json, "os": os, "re": re, "subprocess": FakeSubprocess()}
    exec(code, ns)
    return ns


DUAL_DDR4 = """Handle 0x001A, DMI type 17, 92 bytes
Memory Device
\tSize: 16384 MB
\tLocator: DIMM 1
\tBank Locator: ChannelA-DIMM0
\tType: DDR4
\tSpeed: 3200 MT/s
\tConfigured Memory Speed: 3200 MT/s
Handle 0x001C, DMI type 17, 92 bytes
Memory Device
\tSize: 16384 MB
\tLocator: DIMM 2
\tBank Locator: ChannelB-DIMM0
\tType: DDR4
\tSpeed: 3200 MT/s
\tConfigured Memory Speed: 3200 MT/s
Handle 0x001E, DMI type 17, 92 bytes
Memory Device
\tSize: No Module Installed
\tType: Unknown
\tSpeed: Unknown
"""

SINGLE_DDR4 = """Handle 0x002A, DMI type 17, 40 bytes
Memory Device
\tSize: 8192 MB
\tLocator: DIMM0
\tBank Locator: P0-DIMM0
\tType: DDR4
\tSpeed: Unknown
\tConfigured Memory Speed: 2400 MT/s
"""

UDEV_DUAL_DDR5 = """P: /devices/virtual/dmi/id
E: DEVPATH=/devices/virtual/dmi/id
E: MEMORY_ARRAY_LOCATION=System Board Or Motherboard
E: MEMORY_DEVICE_0_PRESENT=0
E: MEMORY_DEVICE_0_LOCATOR=DIMM 0
E: MEMORY_DEVICE_0_BANK_LOCATOR=P0 CHANNEL A
E: MEMORY_DEVICE_1_SIZE=17179869184
E: MEMORY_DEVICE_1_LOCATOR=DIMM 1
E: MEMORY_DEVICE_1_BANK_LOCATOR=P0 CHANNEL A
E: MEMORY_DEVICE_1_TYPE=DDR5
E: MEMORY_DEVICE_1_SPEED_MTS=5200
E: MEMORY_DEVICE_1_CONFIGURED_SPEED_MTS=5200
E: MEMORY_DEVICE_2_PRESENT=0
E: MEMORY_DEVICE_2_LOCATOR=DIMM 0
E: MEMORY_DEVICE_2_BANK_LOCATOR=P0 CHANNEL B
E: MEMORY_DEVICE_3_SIZE=17179869184
E: MEMORY_DEVICE_3_LOCATOR=DIMM 1
E: MEMORY_DEVICE_3_BANK_LOCATOR=P0 CHANNEL B
E: MEMORY_DEVICE_3_TYPE=DDR5
E: MEMORY_DEVICE_3_SPEED_MTS=5200
E: MEMORY_DEVICE_3_CONFIGURED_SPEED_MTS=5200
"""


MEM_CONFIG_CASES = [
    ("dual-channel DDR4", DUAL_DDR4, "2×16G DDR4-3200 dual-channel"),
    ("single DDR4 at configured speed", SINGLE_DDR4, "1×8G DDR4-2400"),
    ("no dmidecode output hides spec", "", ""),
    ("udev DMI properties need no root", UDEV_DUAL_DDR5,
     "2×16G DDR5-5200 dual-channel"),
]


class MemoryParserTest(unittest.TestCase):
    def test_config_table(self):
        for name, fixture, want in MEM_CONFIG_CASES:
            with self.subTest(name):
                ns = sampler_functions(fixture)
                self.assertEqual(ns["memory_config"](), want)


class MemoryFuzzTest(unittest.TestCase):
    """Random DIMM populations on arbitrary boards must produce a sane
    config string, and corrupt input must never raise."""

    def test_random_populations(self):
        rng = random.Random(20260923)
        for trial in range(200):
            with self.subTest(trial=trial):
                uniform = rng.random() < 0.7
                base_mb = rng.choice([4096, 8192, 16384, 32768])
                chan_style = rng.choice(["none", "ab", "abcd"])
                lines = ["P: /devices/virtual/dmi/id"]
                populated = 0
                sizes = set()
                chans = set()
                for idx in range(rng.randrange(0, 6)):
                    if rng.random() < 0.25:
                        lines.append("E: MEMORY_DEVICE_%d_PRESENT=0" % idx)
                        continue
                    mb = (base_mb if uniform
                          else rng.choice([4096, 8192, 16384, 32768]))
                    sizes.add(mb)
                    lines.append("E: MEMORY_DEVICE_%d_SIZE=%d"
                                 % (idx, mb * 1048576))
                    lines.append("E: MEMORY_DEVICE_%d_TYPE=%s"
                                 % (idx, rng.choice(["DDR4", "DDR5", ""])))
                    spec = rng.choice([2400, 3200, 4800, 5200, 5600])
                    lines.append("E: MEMORY_DEVICE_%d_SPEED_MTS=%d" % (idx, spec))
                    if rng.random() < 0.8:
                        lines.append("E: MEMORY_DEVICE_%d_CONFIGURED_SPEED_MTS=%d"
                                     % (idx, spec))
                    if chan_style == "ab":
                        ch = rng.choice(["A", "B"])
                        lines.append("E: MEMORY_DEVICE_%d_BANK_LOCATOR=P0 CHANNEL %s"
                                     % (idx, ch))
                        chans.add(ch)
                    elif chan_style == "abcd":
                        ch = rng.choice(["A", "B", "C", "D"])
                        lines.append("E: MEMORY_DEVICE_%d_LOCATOR=Channel%s-DIMM0"
                                     % (idx, ch))
                        chans.add(ch)
                    populated += 1
                ns = sampler_functions("\n".join(lines) + "\n")
                got = ns["memory_config"]()
                if populated == 0:
                    self.assertEqual(got, "")
                elif len(sizes) == 1:
                    self.assertTrue(got.startswith("%d×" % populated), got)
                else:
                    self.assertIn("mixed", got)
                self.assertEqual("channel" in got, len(chans) > 1)

    def test_corrupt_input_never_raises(self):
        rng = random.Random(7)
        alphabet = "ABCabc012 \t:=_-[]()"
        for trial in range(100):
            with self.subTest(trial=trial):
                blob = "\n".join(
                    "".join(rng.choice(alphabet)
                            for _ in range(rng.randrange(0, 60)))
                    for _ in range(rng.randrange(0, 10)))
                ns = sampler_functions(blob)
                self.assertIsInstance(ns["memory_config"](), str)


LSBLK_TREE = [
    {"name": "nvme0n1", "path": "/dev/nvme0n1", "type": "disk",
     "model": "ACME NVME 4000", "size": 4000787030016, "tran": "nvme",
     "children": [
         {"name": "nvme0n1p2", "path": "/dev/nvme0n1p2", "type": "part",
          "model": None, "size": 3998636572672, "tran": "nvme"},
     ]},
    {"name": "sda", "path": "/dev/sda", "type": "disk",
     "model": "ACME USB Stick", "size": 4102887936, "tran": "usb"},
]


STRIP_CASES = [
    ("/dev/mapper/root[/@]", "/dev/mapper/root"),
    ("/dev/nvme0n1p2", "/dev/nvme0n1p2"),
    ("", ""),
]

PARENT_CASES = [
    ("nvme2n1p2", "nvme2n1"),
    ("sda1", "sda"),
    ("mmcblk0p1", "mmcblk0"),
]

FIND_CASES = [
    ("top-level disk", "nvme0n1", "ACME NVME 4000"),
    ("missing disk", "nope", None),
]

PCIE_CASES = [
    (("32.0 GT/s PCIe", "4"), "PCIe 5.0 x4"),
    (("16.0 GT/s PCIe", "4"), "PCIe 4.0 x4"),
    (("8.0 GT/s PCIe", "2"), "PCIe 3.0 x2"),
    (("16.0 GT/s PCIe", ""), "PCIe 4.0"),
    (("Unknown", "4"), ""),
    (("", ""), ""),
]

SATA_CASES = [
    ("6.0 Gbps", "SATA 6Gb/s"),
    ("3.0 Gbps", "SATA 3Gb/s"),
    ("<unknown>", ""),
    ("", ""),
]


class SystemDriveTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ns = sampler_functions()

    def test_strip_mount_suffixes(self):
        for source, want in STRIP_CASES:
            with self.subTest(source):
                self.assertEqual(self.ns["strip_mount_suffix"](source), want)

    def test_parent_disk_names(self):
        for partition, want in PARENT_CASES:
            with self.subTest(partition):
                self.assertEqual(self.ns["parent_name"](partition), want)

    def test_find_disk_node(self):
        for name, disk, want_model in FIND_CASES:
            with self.subTest(name):
                hit = self.ns["find_disk_node"](LSBLK_TREE, disk)
                self.assertEqual(hit["model"] if hit else None, want_model)

    def test_pcie_label_generations(self):
        for (speed, width), want in PCIE_CASES:
            with self.subTest(speed or "empty"):
                self.assertEqual(self.ns["pcie_label"](speed, width), want)

    def test_sata_label_speeds(self):
        for spd, want in SATA_CASES:
            with self.subTest(spd or "empty"):
                self.assertEqual(self.ns["sata_label"](spd), want)


class SamplerSchemaTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        proc = subprocess.run(["bash", str(HERE / "sample.sh")],
                              capture_output=True, text=True, timeout=120)
        assert proc.returncode == 0, proc.stderr[-2000:]
        cls.data = json.loads(proc.stdout)

    def test_usage_ranges(self):
        for key in ("cpu", "mem", "gpu", "vram"):
            self.assertGreaterEqual(self.data[key], 0, key)
            self.assertLessEqual(self.data[key], 100, key)
        self.assertLessEqual(self.data["memUsed"], self.data["memTotal"])
        if self.data["vramTotal"] > 0:
            self.assertLessEqual(self.data["vramUsed"], self.data["vramTotal"])

    def test_cpu_identity_types(self):
        self.assertIsInstance(self.data["cpuModel"], str)
        self.assertIsInstance(self.data["cpuCores"], int)
        self.assertIsInstance(self.data["cpuThreads"], int)
        self.assertGreaterEqual(self.data["cpuThreads"], 1)
        self.assertGreaterEqual(self.data["cpuCores"], 1)
        self.assertLessEqual(self.data["cpuCores"], self.data["cpuThreads"])

    def test_gpu_model_is_a_name_not_an_error(self):
        model = self.data["gpuModel"]
        self.assertIsInstance(model, str)
        self.assertNotRegex(model, r"fail|error|unable|no dev|not found|mismatch")

    def test_mem_config_shape(self):
        config = self.data["memConfig"]
        self.assertIsInstance(config, str)
        if config:
            self.assertRegex(config, r"^(\d+×\S+|\S+ mixed)")

    def test_sys_drive_shape(self):
        drive = self.data["sysDrive"]
        self.assertIsInstance(drive, str)
        if drive:
            self.assertRegex(drive, r"^[0-9.]+[KMGT] · ")


if __name__ == "__main__":
    unittest.main()
