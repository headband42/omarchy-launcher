#!/usr/bin/env python3
"""Tests for the system sampler shared by sysmon and sysdisk. Stdlib only.

Run from the repo root:  python3 widgets/_kit/test_system.py
"""

import json
import os
import random
import subprocess
import sys
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch

import system

HERE = Path(__file__).resolve().parent


@contextmanager
def commands_print(command_text=""):
    """Every command system.py runs prints command_text, so the parsers
    are tested against the shipped code without root or hardware."""

    class Out:
        def __init__(self, text):
            self.stdout = text

    class FakeSubprocess:
        class SubprocessError(Exception):
            pass

        def run(self, *args, **kwargs):
            return Out(command_text)

    with patch.object(system, "subprocess", FakeSubprocess()):
        yield


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
                with commands_print(fixture):
                    self.assertEqual(system.memory_config(), want)


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
                with commands_print("\n".join(lines) + "\n"):
                    got = system.memory_config()
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
                with commands_print(blob):
                    self.assertIsInstance(system.memory_config(), str)


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
    def test_strip_mount_suffixes(self):
        for source, want in STRIP_CASES:
            with self.subTest(source):
                self.assertEqual(system.strip_mount_suffix(source), want)

    def test_parent_disk_names(self):
        for partition, want in PARENT_CASES:
            with self.subTest(partition):
                self.assertEqual(system.parent_name(partition), want)

    def test_find_disk_node(self):
        for name, disk, want_model in FIND_CASES:
            with self.subTest(name):
                hit = system.find_disk_node(LSBLK_TREE, disk)
                self.assertEqual(hit["model"] if hit else None, want_model)

    def test_pcie_label_generations(self):
        for (speed, width), want in PCIE_CASES:
            with self.subTest(speed or "empty"):
                self.assertEqual(system.pcie_label(speed, width), want)

    def test_sata_label_speeds(self):
        for spd, want in SATA_CASES:
            with self.subTest(spd or "empty"):
                self.assertEqual(system.sata_label(spd), want)


PROC_STAT_A = "cpu  100 0 50 800 10 0 0 0 0 0\ncpu0 50 0 25 400 5 0 0 0 0 0\n"
PROC_STAT_B = "cpu  130 0 60 860 10 0 0 0 0 0\ncpu0 65 0 30 430 5 0 0 0 0 0\n"

CPUINFO = """processor\t: 0
cpu MHz\t\t: 3000.000
processor\t: 1
cpu MHz\t\t: 4001.000
"""

MEMINFO = """MemTotal:       65536 kB
MemFree:         1024 kB
MemAvailable:   16384 kB
"""

SCLK = "0: 500Mhz\n1: 2100Mhz *\n2: 2600Mhz\n"


class UsageParserTest(unittest.TestCase):
    def test_cpu_percent_from_two_stat_reads(self):
        before = system.parse_cpu_times(PROC_STAT_A)
        after = system.parse_cpu_times(PROC_STAT_B)
        self.assertEqual(before, (960, 800))
        # 100 jiffies passed, 60 of them idle.
        self.assertEqual(system.cpu_percent_between(before, after), 40.0)

    def test_cpu_percent_without_stat(self):
        self.assertIsNone(system.parse_cpu_times(""))
        self.assertEqual(system.cpu_percent_between(None, None), 0.0)

    def test_cpu_mhz_averages_cores(self):
        self.assertEqual(system.parse_cpu_mhz(CPUINFO), "3500")
        self.assertEqual(system.parse_cpu_mhz("processor\t: 0\n"), "")

    def test_meminfo_counts_available_as_free(self):
        used, total, pct = system.parse_meminfo(MEMINFO)
        self.assertEqual(total, 65536 * 1024.0)
        self.assertEqual(used, (65536 - 16384) * 1024.0)
        self.assertEqual(pct, 75.0)
        self.assertEqual(system.parse_meminfo(""), (0.0, 0.0, 0.0))

    def test_nvidia_query_line(self):
        got = system.parse_nvidia_query("37, 4096, 16303, 2520, 61")
        self.assertEqual(got, {"load": "37", "vramUsed": str(4096 * 1048576),
                               "vramTotal": str(16303 * 1048576), "mhz": "2520", "temp": "61"})

    def test_nvidia_query_without_output_or_with_na(self):
        self.assertEqual(system.parse_nvidia_query(""),
                         {"load": "", "vramUsed": "0", "vramTotal": "0", "mhz": "", "temp": ""})
        got = system.parse_nvidia_query("[N/A], [N/A], 8192, [N/A], [N/A]")
        self.assertEqual(got["vramUsed"], "")
        self.assertEqual(system.num(got["load"]), 0.0)
        self.assertIsNone(system.num_or_none(got["load"]))
        self.assertIsNone(system.num_or_none(got["temp"]))

    def test_nvidia_is_one_query(self):
        calls = []

        def run(argv):
            calls.append(argv)
            return "12, 1024, 8192, 1500, 48\n"

        got = system.nvidia_gpu(run)
        self.assertEqual(len(calls), 1)
        self.assertEqual((got["load"], got["temp"]), ("12", "48"))

    def test_sclk_marked_line(self):
        self.assertEqual(system.parse_sclk(SCLK), "2100")
        self.assertEqual(system.parse_sclk("0: 500Mhz\n"), "")

    def test_sysfs_gpu_reads_first_busy_card(self):
        with tempfile.TemporaryDirectory() as tmp:
            quiet = os.path.join(tmp, "card0", "device")
            busy = os.path.join(tmp, "card1", "device")
            os.makedirs(quiet)
            os.makedirs(busy)
            for name, text in (("gpu_busy_percent", "12\n"), ("pp_dpm_sclk", SCLK),
                               ("mem_info_vram_used", "1024\n"), ("mem_info_vram_total", "4096\n")):
                with open(os.path.join(busy, name), "w") as fh:
                    fh.write(text)
            got = system.sysfs_gpu([quiet, busy])
        self.assertEqual(got, {"load": "12", "mhz": "2100", "vramUsed": "1024", "vramTotal": "4096"})
        self.assertIsNone(system.sysfs_gpu([]))


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


def pci_gpu(root, address, vendor, status):
    device = os.path.join(root, address)
    write(os.path.join(device, "vendor"), vendor + "\n")
    write(os.path.join(device, "class"), "0x030000\n")
    write(os.path.join(device, "power", "runtime_status"), status + "\n")
    return device


class SleepingGpuTest(unittest.TestCase):
    """A runtime-suspended GPU is reported asleep without asking its driver,
    which would wake it."""

    def test_sleeping_nvidia_skips_nvidia_smi(self):
        with tempfile.TemporaryDirectory() as pci:
            pci_gpu(pci, "0000:01:00.0", "0x10de", "suspended")
            pci_gpu(pci, "0000:65:00.0", "0x1002", "active")
            calls = []
            got = system.gpu_usage(run=lambda argv: calls.append(argv) or "",
                                   which=lambda name: "/usr/bin/" + name, pci=pci, cards=[])
        self.assertTrue(got["asleep"])
        self.assertEqual(calls, [])

    def test_awake_nvidia_is_asked(self):
        with tempfile.TemporaryDirectory() as pci:
            pci_gpu(pci, "0000:01:00.0", "0x10de", "active")
            got = system.gpu_usage(run=lambda argv: "7, 512, 8192, 900, 44\n",
                                   which=lambda name: "/usr/bin/" + name, pci=pci, cards=[])
        self.assertFalse(got["asleep"])
        self.assertEqual((got["load"], got["mhz"], got["temp"]), ("7", "900", "44"))

    def test_desktop_nvidia_without_runtime_pm_is_awake(self):
        with tempfile.TemporaryDirectory() as pci:
            pci_gpu(pci, "0000:01:00.0", "0x10de", "unsupported")
            self.assertFalse(system.nvidia_asleep(pci))
        self.assertFalse(system.nvidia_asleep("/nonexistent"))

    def test_sleeping_amd_card_is_not_read(self):
        with tempfile.TemporaryDirectory() as tmp:
            card = os.path.join(tmp, "card1", "device")
            write(os.path.join(card, "gpu_busy_percent"), "99\n")
            write(os.path.join(card, "power", "runtime_status"), "suspended\n")
            self.assertEqual(system.sysfs_gpu([card]), {"asleep": True})

    def test_amd_card_temperature(self):
        with tempfile.TemporaryDirectory() as tmp:
            card = os.path.join(tmp, "card0", "device")
            write(os.path.join(card, "gpu_busy_percent"), "12\n")
            write(os.path.join(card, "hwmon", "hwmon3", "temp1_input"), "45000\n")
            write(os.path.join(card, "hwmon", "hwmon3", "temp1_label"), "edge\n")
            write(os.path.join(card, "hwmon", "hwmon3", "temp2_input"), "53000\n")
            write(os.path.join(card, "hwmon", "hwmon3", "temp2_label"), "junction\n")
            got = system.sysfs_gpu([card])
        self.assertEqual((got["load"], got["temp"]), ("12", "45.0"))


class IntelGpuTest(unittest.TestCase):
    def card(self, tmp, name, driver):
        drivers = os.path.join(tmp, "drivers", driver)
        os.makedirs(drivers, exist_ok=True)
        device = os.path.join(tmp, "devices", name)
        os.makedirs(device, exist_ok=True)
        os.symlink(drivers, os.path.join(device, "driver"))
        card = os.path.join(tmp, "drm", name)
        os.makedirs(card)
        os.symlink(device, os.path.join(card, "device"))
        return card

    def test_i915_clock(self):
        with tempfile.TemporaryDirectory() as tmp:
            card = self.card(tmp, "card0", "i915")
            write(os.path.join(card, "gt_act_freq_mhz"), "1300\n")
            os.makedirs(os.path.join(tmp, "drm", "card0-eDP-1"))
            self.assertEqual(system.intel_gpu(os.path.join(tmp, "drm")), {"mhz": "1300"})

    def test_xe_clock(self):
        with tempfile.TemporaryDirectory() as tmp:
            card = self.card(tmp, "card0", "xe")
            write(os.path.join(card, "device", "tile0", "gt0", "freq0", "act_freq"), "850\n")
            self.assertEqual(system.intel_gpu(os.path.join(tmp, "drm")), {"mhz": "850"})

    def test_idle_or_other_drivers_have_no_clock(self):
        with tempfile.TemporaryDirectory() as tmp:
            card = self.card(tmp, "card0", "i915")
            write(os.path.join(card, "gt_act_freq_mhz"), "0\n")
            self.card(tmp, "card1", "amdgpu")
            self.assertIsNone(system.intel_gpu(os.path.join(tmp, "drm")))


CPU_TEMP_CASES = [
    ("Ryzen reports Tctl", {"k10temp": {"Tctl": 57375, "Tccd1": 52750}}, [], 57.4),
    ("early Ryzen prefers Tdie", {"k10temp": {"Tctl": 70000, "Tdie": 50000}}, [], 50.0),
    ("Intel package", {"coretemp": {"Core 0": 40000, "Package id 0": 48000}}, [], 48.0),
    ("other sensors are not the CPU", {"nvme": {"Composite": 44850}, "amdgpu": {"edge": 45000}}, [], None),
    ("thermal zone fallback", {"acpitz": {"": 30000}}, [("x86_pkg_temp", 61000)], 61.0),
    ("no sensors", {}, [], None),
]


class CpuTempTest(unittest.TestCase):
    def test_cpu_sensor_table(self):
        for name, chips, zones, want in CPU_TEMP_CASES:
            with self.subTest(name), tempfile.TemporaryDirectory() as tmp:
                hwmon = os.path.join(tmp, "hwmon")
                thermal = os.path.join(tmp, "thermal")
                os.makedirs(hwmon)
                os.makedirs(thermal)
                for index, (chip, temps) in enumerate(chips.items()):
                    folder = os.path.join(hwmon, "hwmon%d" % index)
                    write(os.path.join(folder, "name"), chip + "\n")
                    for slot, (label, value) in enumerate(temps.items(), start=1):
                        write(os.path.join(folder, "temp%d_input" % slot), "%d\n" % value)
                        if label:
                            write(os.path.join(folder, "temp%d_label" % slot), label + "\n")
                for index, (kind, value) in enumerate(zones):
                    zone = os.path.join(thermal, "thermal_zone%d" % index)
                    write(os.path.join(zone, "type"), kind + "\n")
                    write(os.path.join(zone, "temp"), "%d\n" % value)
                self.assertEqual(system.cpu_temp(hwmon, thermal), want)

    def test_implausible_readings_are_dropped(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "temp1_input")
            for text in ("0", "-5000", "200000", "junk"):
                write(path, text)
                self.assertIsNone(system.milli_celsius(path), text)


CPU_MODEL_CASES = [
    ("AMD Ryzen 9 9950X 16-Core Processor", "AMD Ryzen 9 9950X"),
    ("AMD Ryzen 7 1700 Eight-Core Processor", "AMD Ryzen 7 1700"),
    ("13th Gen Intel(R) Core(TM) i7-1360P", "13th Gen Intel Core i7-1360P"),
    ("Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz", "Intel Core i5-8250U"),
]


class SpecsTest(unittest.TestCase):
    def test_cpu_model_leaves_the_core_count_to_its_own_spec(self):
        for model, want in CPU_MODEL_CASES:
            with self.subTest(model):
                text = "processor\t: 0\nmodel name\t: %s\ncpu cores\t: 8\n" % model
                self.assertEqual(system.cpu_info(text)[0], want)

    def test_gpu_name_from_nvidia_proc_without_waking_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            write(os.path.join(tmp, "0000:01:00.0", "information"),
                  "Model: \t\t NVIDIA GeForce RTX 4060 Laptop GPU\nIRQ:   \t\t 104\n")
            calls = []
            name = system.gpu_model(run=lambda argv: calls.append(argv) or "", proc=tmp)
        self.assertEqual(name, "NVIDIA GeForce RTX 4060 Laptop GPU")
        self.assertEqual(calls, [])

    def test_memory_config_never_asks_sudo(self):
        argvs = []

        class Out:
            stdout = ""

        class Recording:
            class SubprocessError(Exception):
                pass

            def run(self, argv, **kwargs):
                argvs.append(argv)
                return Out()

        with patch.object(system, "subprocess", Recording()):
            self.assertEqual(system.memory_config(), "")
        self.assertTrue(argvs)
        self.assertFalse(any("sudo" in argv for argv in argvs))


class SamplerSchemaTest(unittest.TestCase):
    """The sampler on this machine. Everything it runs only reads."""

    @classmethod
    def setUpClass(cls):
        def sample(*flags):
            proc = subprocess.run([sys.executable, str(HERE / "system.py"), *flags],
                                  capture_output=True, text=True, timeout=120)
            assert proc.returncode == 0, proc.stderr[-2000:]
            return json.loads(proc.stdout)

        cls.plain = sample()
        cls.data = sample("--warm", "--specs")

    def test_plain_run_is_usage_only(self):
        self.assertNotIn("cpu", self.plain)
        self.assertNotIn("cpuModel", self.plain)
        ticks = self.plain["cpuTicks"]
        self.assertEqual(len(ticks), 2)
        self.assertLessEqual(ticks[1], ticks[0])
        for key in ("cpuTemp", "gpu", "gpuTemp"):
            self.assertTrue(self.plain[key] is None or isinstance(self.plain[key], float), key)
        self.assertIsInstance(self.plain["gpuAsleep"], bool)

    def test_usage_ranges(self):
        for key in ("cpu", "mem", "gpu", "vram"):
            if self.data[key] is None:
                continue
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
