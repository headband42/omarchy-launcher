#!/usr/bin/env python3
"""Tests for the sysmon sampler. Stdlib only.

Run from the repo root:  python3 widgets/sysmon/test_sample.py
"""

import json
import re
import subprocess
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


def sampler_functions(dmidecode_text):
    """Exec the pure-python helpers shipped inside sample.sh with a
    stubbed subprocess, so the dmidecode parser is tested against the
    real code without needing root."""

    class Out:
        def __init__(self, text):
            self.stdout = text

    class FakeSubprocess:
        class SubprocessError(Exception):
            pass

        def run(self, *args, **kwargs):
            return Out(dmidecode_text)

    src = (HERE / "sample.sh").read_text()
    code = src[src.index("def fmt_gb(mb):"):src.index("cpu_model, cpu_threads")]
    ns = {"re": re, "subprocess": FakeSubprocess()}
    exec(code, ns)
    return ns


DUAL_DDR5 = """Handle 0x001A, DMI type 17, 92 bytes
Memory Device
\tSize: 32768 MB
\tLocator: DIMM 1
\tBank Locator: ChannelA-DIMM0
\tType: DDR5
\tSpeed: 5600 MT/s
\tConfigured Memory Speed: 5600 MT/s
Handle 0x001C, DMI type 17, 92 bytes
Memory Device
\tSize: 32768 MB
\tLocator: DIMM 2
\tBank Locator: ChannelB-DIMM0
\tType: DDR5
\tSpeed: 5600 MT/s
\tConfigured Memory Speed: 5600 MT/s
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
E: MEMORY_DEVICE_1_SIZE=34359738368
E: MEMORY_DEVICE_1_LOCATOR=DIMM 1
E: MEMORY_DEVICE_1_BANK_LOCATOR=P0 CHANNEL A
E: MEMORY_DEVICE_1_TYPE=DDR5
E: MEMORY_DEVICE_1_SPEED_MTS=5600
E: MEMORY_DEVICE_1_CONFIGURED_SPEED_MTS=6000
E: MEMORY_DEVICE_2_PRESENT=0
E: MEMORY_DEVICE_2_LOCATOR=DIMM 0
E: MEMORY_DEVICE_2_BANK_LOCATOR=P0 CHANNEL B
E: MEMORY_DEVICE_3_SIZE=34359738368
E: MEMORY_DEVICE_3_LOCATOR=DIMM 1
E: MEMORY_DEVICE_3_BANK_LOCATOR=P0 CHANNEL B
E: MEMORY_DEVICE_3_TYPE=DDR5
E: MEMORY_DEVICE_3_SPEED_MTS=5600
E: MEMORY_DEVICE_3_CONFIGURED_SPEED_MTS=6000
"""


class MemoryParserTest(unittest.TestCase):
    def test_dual_channel_ddr5(self):
        ns = sampler_functions(DUAL_DDR5)
        self.assertEqual(ns["memory_config"](), "2×32G DDR5-5600 dual-channel")

    def test_single_ddr4_configured_speed(self):
        ns = sampler_functions(SINGLE_DDR4)
        self.assertEqual(ns["memory_config"](), "1×8G DDR4-2400")

    def test_no_dmidecode_output_hides_spec(self):
        ns = sampler_functions("")
        self.assertEqual(ns["memory_config"](), "")

    def test_udev_dmi_properties_need_no_root(self):
        ns = sampler_functions(UDEV_DUAL_DDR5)
        self.assertEqual(ns["memory_config"](),
                         "2×32G DDR5-6000 dual-channel")


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


if __name__ == "__main__":
    unittest.main()
