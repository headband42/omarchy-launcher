#!/usr/bin/env python3
"""Regression tests for the audio tile logic. Stdlib only.

Run from the repo root:  python3 widgets/audio/test_audio.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import audio


VOLUME = """\
Volume: front-left: 64646 /  99% / -0.36 dB,   front-right: 64646 /  99% / -0.36 dB
        balance 0.00
"""

SINKS = """\
[
  {
    "name": "alsa_output.usb-Generic_USB_Audio-00.HiFi__Speaker__sink",
    "description": "Generic USB Audio Speaker",
    "mute": false,
    "ports": [{"name": "analog-output", "availability": "available"}]
  },
  {
    "name": "alsa_output.pci-0000_00_1f.3.analog-stereo",
    "description": "Built-in Audio",
    "mute": false,
    "ports": [{"name": "analog-output-speaker", "availability": "not available"}]
  },
  {
    "name": "easyeffects_sink",
    "description": "EasyEffects Sink",
    "mute": false,
    "ports": []
  },
  {
    "name": "alsa_output.hdmi-stereo-extra1",
    "description": "HDMI / DisplayPort",
    "mute": false,
    "properties": {"device.description": "HDMI fallback"}
  }
]
"""


class ParseTests(unittest.TestCase):
    def test_parse_volume(self):
        self.assertEqual(audio.parse_volume(VOLUME), 99)
        self.assertEqual(audio.parse_volume("Volume: front-left: 0 /   0% / -inf dB\n"), 0)
        self.assertEqual(audio.parse_volume(""), 0)
        self.assertEqual(audio.parse_volume("garbage"), 0)

    def test_parse_mute(self):
        self.assertTrue(audio.parse_mute("Mute: yes\n"))
        self.assertFalse(audio.parse_mute("Mute: no\n"))
        self.assertFalse(audio.parse_mute(""))
        self.assertFalse(audio.parse_mute("Mute: maybe"))

    def test_parse_sinks_drops_unavailable_ports(self):
        rows = audio.parse_sinks(SINKS)
        self.assertEqual([row["name"] for row in rows], [
            "alsa_output.usb-Generic_USB_Audio-00.HiFi__Speaker__sink",
            "easyeffects_sink",
            "alsa_output.hdmi-stereo-extra1",
        ])

    def test_parse_sinks_skips_fronted_tuning(self):
        rows = audio.parse_sinks(SINKS, fronted="easyeffects_sink")
        self.assertEqual([row["name"] for row in rows], [
            "alsa_output.usb-Generic_USB_Audio-00.HiFi__Speaker__sink",
            "alsa_output.hdmi-stereo-extra1",
        ])

    def test_parse_sinks_description_fallback(self):
        rows = audio.parse_sinks(SINKS)
        self.assertEqual(rows[0]["description"], "Generic USB Audio Speaker")
        self.assertEqual(rows[2]["description"], "HDMI / DisplayPort")
        rows = audio.parse_sinks('[{"name": "x"}]')
        self.assertEqual(rows[0]["description"], "x")
        self.assertEqual(audio.parse_sinks(""), [])
        self.assertEqual(audio.parse_sinks("not json"), [])
        self.assertEqual(audio.parse_sinks("{}"), [])


class GatherTests(unittest.TestCase):
    def test_gather(self):
        def run(argv, timeout):
            answers = {
                ("pactl", "get-default-sink"): (0, "easyeffects_sink\n"),
                ("omarchy-audio-output-sink",): (0, "alsa_output.usb-Generic_USB_Audio-00.HiFi__Speaker__sink\n"),
                ("pactl", "get-sink-volume", "alsa_output.usb-Generic_USB_Audio-00.HiFi__Speaker__sink"): (0, VOLUME),
                ("pactl", "get-sink-mute", "alsa_output.usb-Generic_USB_Audio-00.HiFi__Speaker__sink"): (0, "Mute: no\n"),
                ("omarchy-audio-tuning", "fronted-sink"): (1, ""),
                ("pactl", "-f", "json", "list", "sinks"): (0, SINKS),
            }
            return answers[tuple(argv)]

        payload = audio.gather(run)
        self.assertEqual(payload["volume"], 99)
        self.assertFalse(payload["muted"])
        self.assertEqual(payload["sink"], "EasyEffects Sink")
        self.assertEqual(payload["index"], 1)

    def test_gather_without_outputs(self):
        def run(argv, timeout):
            return 1, ""

        payload = audio.gather(run)
        self.assertEqual(payload, {"volume": 0, "muted": False, "sink": "",
                                   "sinks": [], "index": -1})


if __name__ == "__main__":
    unittest.main()
