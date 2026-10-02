#!/usr/bin/env python3
"""Tests for the network sampler. Stdlib only; nothing here runs a real command.

Run from the repo root:  python3 widgets/network/test_network.py
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import network

ROUTE = [{"dst": "1.1.1.1", "gateway": "192.168.0.1", "dev": "wlan0", "prefsrc": "192.168.0.50"}]

LINKS = [
    {"ifname": "lo", "flags": ["LOOPBACK", "UP", "LOWER_UP"], "operstate": "UNKNOWN", "link_type": "loopback"},
    {"ifname": "wlan0", "flags": ["BROADCAST", "UP", "LOWER_UP"], "operstate": "UP", "link_type": "ether",
     "addr_info": [
         {"family": "inet", "local": "192.168.0.50", "prefixlen": 24, "scope": "global"},
         {"family": "inet6", "local": "fe80::1", "scope": "link"},
         {"family": "inet6", "local": "2001:db8::5", "scope": "global", "temporary": True},
         {"family": "inet6", "local": "2001:db8::1", "scope": "global"},
     ]},
    {"ifname": "docker0", "flags": ["UP", "LOWER_UP"], "operstate": "UP", "linkinfo": {"info_kind": "bridge"}},
    {"ifname": "tailscale0", "flags": ["UP", "LOWER_UP"], "operstate": "UNKNOWN", "linkinfo": {"info_kind": "tun"}},
    {"ifname": "wg-home", "flags": ["UP", "LOWER_UP"], "operstate": "UNKNOWN", "linkinfo": {"info_kind": "wireguard"}},
    {"ifname": "tun0", "flags": ["UP"], "operstate": "DOWN", "linkinfo": {"info_kind": "tun"}},
]

NMCLI = "\n".join([
    " :Neighbors:100:2412 MHz:WPA2",
    "*:Cafe\\: Upstairs:72:5180 MHz:WPA2 WPA3",
    " :Open:40:2437 MHz:--",
])

IW_LINK = """Connected to aa:bb:cc:dd:ee:ff (on wlan0)
\tSSID: Caf\\xc3\\xa9
\tfreq: 5955
\tsignal: -61 dBm
\ttx bitrate: 1200.9 MBit/s
"""

IWCTL = """\x1b[0m                                 Station: wlan0
--------------------------------------------------------------------------------
  Settable  Property              Value
--------------------------------------------------------------------------------
            Scanning              no
            State                 connected
            Connected network     Home Net 5G
            IPv4 address          192.168.0.50
            RSSI                  -48 dBm
            AverageRSSI           -50 dBm
            Frequency             5745
"""

TAILSCALE_EXIT = {
    "BackendState": "Running",
    "CurrentTailnet": {"Name": "example.github"},
    "Peer": {
        "a": {"HostName": "laptop", "ExitNode": False},
        "b": {"HostName": "nas", "DNSName": "nas.tail1234.ts.net.", "ExitNode": True},
    },
}


def fake_runner(responses):
    def runner(argv, timeout=None):
        return responses.get(argv[0] + " " + argv[1], "") if len(argv) > 1 else ""
    return runner


def make_sys(root, device, kind="wifi", rx=1000, tx=500, speed=None, arphrd=1):
    base = os.path.join(root, device)
    os.makedirs(os.path.join(base, "statistics"), exist_ok=True)
    if kind == "wifi":
        os.makedirs(os.path.join(base, "wireless"), exist_ok=True)
    with open(os.path.join(base, "type"), "w") as handle:
        handle.write(str(arphrd))
    with open(os.path.join(base, "statistics", "rx_bytes"), "w") as handle:
        handle.write(str(rx))
    with open(os.path.join(base, "statistics", "tx_bytes"), "w") as handle:
        handle.write(str(tx))
    if speed is not None:
        with open(os.path.join(base, "speed"), "w") as handle:
            handle.write(str(speed))


class Clock:
    """A monotonic clock that only moves when sleep() is called."""

    def __init__(self):
        self.now = 100.0

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class ParseTests(unittest.TestCase):
    def test_route_device(self):
        self.assertEqual(network.route_device(ROUTE), ("wlan0", "192.168.0.1", "192.168.0.50"))
        self.assertEqual(network.route_device([]), ("", "", ""))
        self.assertEqual(network.route_device(None), ("", "", ""))
        self.assertEqual(network.route_device([{"dst": "1.1.1.1"}]), ("", "", ""))

    def test_addresses_skip_link_local_and_temporary(self):
        self.assertEqual(network.addresses(LINKS, "wlan0"), ("192.168.0.50", "2001:db8::1"))
        self.assertEqual(network.addresses(LINKS, "eth9"), ("", ""))

    def test_vpns_are_up_tunnels_not_bridges(self):
        found = network.vpns(LINKS)
        self.assertEqual([v["device"] for v in found], ["tailscale0", "wg-home"])
        self.assertEqual([v["name"] for v in found], ["Tailscale", "WireGuard"])

    def test_vpn_name(self):
        self.assertEqual(network.vpn_name("nordlynx", "wireguard"), "NordVPN")
        self.assertEqual(network.vpn_name("proton0", "wireguard"), "Proton VPN")
        self.assertEqual(network.vpn_name("custom7", "wireguard"), "WireGuard")
        self.assertEqual(network.vpn_name("docker0", "tun"), "")
        self.assertEqual(network.vpn_name("veth1234", ""), "")
        self.assertEqual(network.vpn_name("eth0", ""), "")

    def test_split_terse_keeps_escaped_colons(self):
        self.assertEqual(network.split_terse("*:a\\:b:72"), ["*", "a:b", "72"])
        self.assertEqual(network.split_terse("x\\\\y:z"), ["x\\y", "z"])

    def test_wifi_from_nmcli(self):
        self.assertEqual(network.wifi_from_nmcli(NMCLI), {"ssid": "Cafe: Upstairs", "signal": 72, "freq": 5180, "secure": True})
        self.assertIsNone(network.wifi_from_nmcli(" :x:10:2412 MHz:WPA2"))
        self.assertIsNone(network.wifi_from_nmcli(""))
        self.assertEqual(network.wifi_from_nmcli("*:Open:40:2437 MHz:--")["secure"], False)

    def test_wifi_from_iw_decodes_escaped_ssid(self):
        found = network.wifi_from_iw(IW_LINK)
        self.assertEqual(found["ssid"], "Café")
        self.assertEqual(found["freq"], 5955)
        self.assertEqual(found["signal"], 78)
        self.assertIsNone(network.wifi_from_iw("Not connected.\n"))
        self.assertIsNone(network.wifi_from_iw(""))

    def test_wifi_from_iwctl(self):
        found = network.wifi_from_iwctl(IWCTL)
        self.assertEqual(found["ssid"], "Home Net 5G")
        self.assertEqual(found["signal"], 100)
        self.assertEqual(found["freq"], 5745)
        self.assertIsNone(network.wifi_from_iwctl("            State                 disconnected\n"))

    def test_wifi_details_falls_through_the_stacks(self):
        only_iw = fake_runner({"iw dev": IW_LINK})
        self.assertEqual(network.wifi_details("wlan0", only_iw)["ssid"], "Café")
        nm_first = fake_runner({"nmcli -t": NMCLI, "iw dev": IW_LINK})
        self.assertEqual(network.wifi_details("wlan0", nm_first)["ssid"], "Cafe: Upstairs")
        self.assertIsNone(network.wifi_details("wlan0", fake_runner({})))

    def test_dbm_to_percent(self):
        self.assertEqual(network.dbm_to_percent(-100), 0)
        self.assertEqual(network.dbm_to_percent(-50), 100)
        self.assertEqual(network.dbm_to_percent(-30), 100)
        self.assertEqual(network.dbm_to_percent(-75), 50)
        self.assertIsNone(network.dbm_to_percent(None))

    def test_band(self):
        self.assertEqual(network.band(2437), "2.4 GHz")
        self.assertEqual(network.band(5180), "5 GHz")
        self.assertEqual(network.band(6135), "6 GHz")
        self.assertEqual(network.band(None), "")

    def test_tailscale_detail(self):
        self.assertEqual(network.tailscale_detail(TAILSCALE_EXIT), "exit via nas")
        self.assertEqual(network.tailscale_detail({"BackendState": "Running", "CurrentTailnet": {"Name": "me.github"}}), "me.github")
        self.assertEqual(network.tailscale_detail({"BackendState": "Stopped"}), "")
        self.assertEqual(network.tailscale_detail(None), "")

    def test_parse_ping(self):
        line = "64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=12.74 ms"
        self.assertEqual(network.parse_ping(line), 12.7)
        self.assertEqual(network.parse_ping("time<1 ms"), 1.0)
        self.assertIsNone(network.parse_ping("100% packet loss"))
        self.assertIsNone(network.parse_ping(""))


class SampleTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.sys = self.dir.name

    def tearDown(self):
        self.dir.cleanup()

    def run_sample(self, responses, grow=(0, 0)):
        clock = Clock()

        def sleep(seconds):
            clock.sleep(seconds)
            # Traffic arrives while the sampler waits.
            for name, add in (("rx_bytes", grow[0]), ("tx_bytes", grow[1])):
                path = os.path.join(self.sys, "wlan0", "statistics", name)
                if os.path.exists(path):
                    with open(path) as handle:
                        value = int(handle.read())
                    with open(path, "w") as handle:
                        handle.write(str(value + add))

        return network.sample(fake_runner(responses), self.sys, wall=lambda: 1_700_000_000.0 + clock.now,
                              sleep=sleep, clock=clock)

    def test_wifi_sample(self):
        make_sys(self.sys, "wlan0", "wifi", rx=10_000, tx=2_000)
        out = self.run_sample({
            "ip -j": json.dumps(ROUTE),
            "nmcli -t": NMCLI,
        }, grow=(5_000, 1_000))
        # `ip -j route` and `ip -j -d addr` share a key in the fake runner.
        self.assertEqual(out["kind"], "wifi")
        self.assertEqual(out["device"], "wlan0")
        self.assertEqual(out["name"], "Cafe: Upstairs")
        self.assertEqual(out["band"], "5 GHz")
        self.assertEqual(out["rate"], {"down": 10_000, "up": 2_000})
        self.assertEqual((out["rx"], out["tx"]), (15_000, 3_000))
        self.assertEqual(out["gateway"], "192.168.0.1")

    def test_offline(self):
        out = self.run_sample({"ip -j": "[]"})
        self.assertEqual(out["kind"], "offline")
        self.assertEqual(out["device"], "")
        self.assertIsNone(out["rate"])

    def test_ethernet_speed(self):
        make_sys(self.sys, "eth0", "ethernet", speed=2500)
        route = [{"dev": "eth0", "gateway": "10.0.0.1", "prefsrc": "10.0.0.9"}]
        out = self.run_sample({"ip -j": json.dumps(route)})
        self.assertEqual(out["kind"], "ethernet")
        self.assertEqual(out["speed"], 2500)
        # No global address in the links answer: the route's source stands in.
        self.assertEqual(out["ipv4"], "10.0.0.9")

    def test_unknown_link_speed_is_none(self):
        make_sys(self.sys, "eth0", "ethernet", speed=-1)
        out = self.run_sample({"ip -j": json.dumps([{"dev": "eth0"}])})
        self.assertIsNone(out["speed"])

    def test_counter_reset_gives_no_rate(self):
        make_sys(self.sys, "wlan0", "wifi", rx=10_000, tx=2_000)
        out = self.run_sample({"ip -j": json.dumps(ROUTE)}, grow=(-5_000, 0))
        self.assertIsNone(out["rate"])

    def test_tunnel_names_the_link_underneath(self):
        make_sys(self.sys, "wg0", "tunnel", arphrd=65534)
        links = [
            {"ifname": "wg0", "flags": ["UP", "LOWER_UP"], "linkinfo": {"info_kind": "wireguard"}},
            {"ifname": "docker0", "flags": ["UP", "LOWER_UP"], "link_type": "ether"},
            {"ifname": "enp3s0", "flags": ["UP", "LOWER_UP"], "link_type": "ether"},
        ]
        runner = fake_runner({})

        def both(argv, timeout=None):
            if argv[:3] == ["ip", "-j", "route"]:
                return json.dumps([{"dev": "wg0"}])
            if argv[:3] == ["ip", "-j", "-d"]:
                return json.dumps(links)
            return runner(argv)

        clock = Clock()
        out = network.sample(both, self.sys, wall=lambda: 0.0, sleep=clock.sleep, clock=clock)
        self.assertEqual(out["kind"], "tunnel")
        self.assertEqual(out["name"], "WireGuard")
        self.assertEqual(out["via"], "enp3s0")

    def test_tailscale_signed_out_is_not_listed(self):
        make_sys(self.sys, "wlan0", "wifi")

        def runner(argv, timeout=None):
            if argv[:3] == ["ip", "-j", "route"]:
                return json.dumps(ROUTE)
            if argv[:3] == ["ip", "-j", "-d"]:
                return json.dumps(LINKS)
            if argv[0] == "tailscale":
                return json.dumps({"BackendState": "NeedsLogin"})
            return ""

        clock = Clock()
        out = network.sample(runner, self.sys, wall=lambda: 0.0, sleep=clock.sleep, clock=clock)
        self.assertEqual([v["name"] for v in out["vpns"]], ["WireGuard"])

    def test_tailscale_exit_node_is_the_detail(self):
        make_sys(self.sys, "wlan0", "wifi")

        def runner(argv, timeout=None):
            if argv[:3] == ["ip", "-j", "route"]:
                return json.dumps(ROUTE)
            if argv[:3] == ["ip", "-j", "-d"]:
                return json.dumps(LINKS)
            if argv[0] == "tailscale":
                return json.dumps(TAILSCALE_EXIT)
            return ""

        clock = Clock()
        out = network.sample(runner, self.sys, wall=lambda: 0.0, sleep=clock.sleep, clock=clock)
        self.assertEqual(out["vpns"][0], {"device": "tailscale0", "name": "Tailscale", "detail": "exit via nas"})

    def test_missing_tool_is_empty(self):
        self.assertEqual(network.run(["definitely-not-a-command-xyz"]), "")


if __name__ == "__main__":
    unittest.main()
