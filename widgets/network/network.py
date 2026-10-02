#!/usr/bin/env python3
"""The connection this machine is using, for the launcher tile. Stdlib only.

    network.py            the link: kind, name, address, byte counters, VPNs
    network.py --ping     round-trip time to 1.1.1.1, in ms

The interface is the one the kernel routes 1.1.1.1 through, so a VPN that
takes the default route is the interface, and the physical link underneath is
named in `via`. Wi-Fi details come from whichever stack is present:
NetworkManager (`nmcli`), iwd (`iwctl`), or the bare `iw` tool. The byte
counters are the kernel's own totals; the tile turns two of them into a rate.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time

PROBE = "1.1.1.1"
TIMEOUT = 4
SYS_NET = "/sys/class/net"
# Seconds between the two counter reads that give a first sample its rate.
RATE_WINDOW = 0.5

# Interface kinds and name prefixes that are a VPN or an overlay network, and
# the name to show for each. Docker, libvirt and container bridges are not.
VPN_KINDS = {"wireguard": "WireGuard", "tun": "VPN", "tap": "VPN", "ppp": "VPN", "ipip": "Tunnel", "gre": "Tunnel"}
VPN_NAMES = (
    ("tailscale", "Tailscale"),
    ("nordlynx", "NordVPN"),
    ("nordtun", "NordVPN"),
    ("proton", "Proton VPN"),
    ("pvpn", "Proton VPN"),
    ("mullvad", "Mullvad"),
    ("wg", "WireGuard"),
    ("zt", "ZeroTier"),
    ("tun", "VPN"),
    ("tap", "VPN"),
    ("ppp", "VPN"),
    ("cscotun", "Cisco VPN"),
    ("gpd", "GlobalProtect"),
    ("utun", "VPN"),
    ("netbird", "NetBird"),
    ("wt", "NetBird"),
)
NOT_VPN = ("docker", "br-", "veth", "virbr", "vnet", "lo", "podman", "cni", "flannel", "lxc", "incus")

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def run(argv, timeout=TIMEOUT):
    """stdout of argv, or "" when it is missing, fails, or hangs."""
    if not shutil.which(argv[0]):
        return ""
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                              env=dict(os.environ, LC_ALL="C"))
    except (OSError, subprocess.SubprocessError):
        return ""
    return proc.stdout if proc.returncode == 0 else ""


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def read_int(path):
    try:
        return int(read_text(path))
    except ValueError:
        return None


# —— Route and addresses ——


def route_device(routes):
    """(device, gateway, source) from `ip -j route get`."""
    for row in routes if isinstance(routes, list) else []:
        if isinstance(row, dict) and row.get("dev"):
            return str(row["dev"]), str(row.get("gateway") or ""), str(row.get("prefsrc") or "")
    return "", "", ""


def addresses(links, device):
    """The first global IPv4 and IPv6 address on device, from `ip -j addr`."""
    ipv4 = ipv6 = ""
    for link in links if isinstance(links, list) else []:
        if not isinstance(link, dict) or link.get("ifname") != device:
            continue
        for info in link.get("addr_info") or []:
            if not isinstance(info, dict) or info.get("scope") != "global":
                continue
            if info.get("family") == "inet" and not ipv4:
                ipv4 = str(info.get("local") or "")
            elif info.get("family") == "inet6" and not ipv6 and not info.get("temporary"):
                ipv6 = str(info.get("local") or "")
    return ipv4, ipv6


def vpn_name(name, kind):
    lower = name.lower()
    if lower.startswith(NOT_VPN):
        return ""
    for prefix, label in VPN_NAMES:
        if lower.startswith(prefix):
            return label
    return VPN_KINDS.get(kind or "", "")


def vpns(links):
    """Every interface that is up and is a VPN or an overlay, from `ip -j -d link`."""
    out = []
    for link in links if isinstance(links, list) else []:
        if not isinstance(link, dict):
            continue
        name = str(link.get("ifname") or "")
        flags = link.get("flags") or []
        if not name or "UP" not in flags or link.get("operstate") == "DOWN":
            continue
        kind = str((link.get("linkinfo") or {}).get("info_kind") or "")
        label = vpn_name(name, kind)
        if label:
            out.append({"device": name, "name": label})
    return out


# —— Wi-Fi ——


def split_terse(line):
    """One `nmcli -t` line: fields split on ':', with '\\:' kept as a colon."""
    fields, current, escaped = [], [], False
    for char in line:
        if escaped:
            current.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == ":":
            fields.append("".join(current))
            current = []
        else:
            current.append(char)
    fields.append("".join(current))
    return fields


def wifi_from_nmcli(text):
    """The row marked in use in `nmcli -t -f IN-USE,SSID,SIGNAL,FREQ,SECURITY dev wifi list`."""
    for line in (text or "").splitlines():
        fields = split_terse(line)
        if len(fields) < 5 or fields[0].strip() != "*":
            continue
        signal = None
        try:
            signal = max(0, min(100, int(fields[2])))
        except ValueError:
            pass
        freq = None
        match = re.match(r"\s*(\d+)", fields[3])
        if match:
            freq = int(match.group(1))
        security = fields[4].strip()
        return {"ssid": fields[1], "signal": signal, "freq": freq, "secure": bool(security and security != "--")}
    return None


def dbm_to_percent(dbm):
    """NetworkManager's own scale: -100 dBm is 0%, -50 dBm and up is 100%."""
    if dbm is None:
        return None
    return max(0, min(100, int(round(2 * (dbm + 100)))))


def wifi_from_iw(text):
    """`iw dev X link`: 'SSID: name', 'freq: 5180', 'signal: -54 dBm'."""
    if not text or "Not connected" in text:
        return None
    ssid = freq = dbm = None
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("SSID:"):
            ssid = line[5:].strip()
            # iw writes bytes outside printable ASCII as \xNN.
            try:
                ssid = ssid.encode("latin-1").decode("unicode_escape").encode("latin-1").decode("utf-8")
            except (UnicodeError, ValueError):
                pass
        elif line.startswith("freq:"):
            match = re.match(r"freq:\s*(\d+)", line)
            freq = int(match.group(1)) if match else None
        elif line.startswith("signal:"):
            match = re.match(r"signal:\s*(-?\d+)", line)
            dbm = int(match.group(1)) if match else None
    if ssid is None:
        return None
    return {"ssid": ssid, "signal": dbm_to_percent(dbm), "freq": freq, "secure": None}


def wifi_from_iwctl(text):
    """`iwctl station X show`, a table: 'Connected network  name', 'RSSI  -54 dBm'."""
    if not text:
        return None
    ssid = freq = dbm = None
    for raw in ANSI.sub("", text).splitlines():
        line = raw.strip()
        match = re.match(r"Connected network\s{2,}(.+?)\s*$", line)
        if match:
            ssid = match.group(1)
            continue
        match = re.match(r"(?:Average )?RSSI\s{2,}(-?\d+)", line)
        if match and dbm is None:
            dbm = int(match.group(1))
            continue
        match = re.match(r"Frequency\s{2,}(\d+)", line)
        if match:
            freq = int(match.group(1))
    if ssid is None:
        return None
    return {"ssid": ssid, "signal": dbm_to_percent(dbm), "freq": freq, "secure": None}


def band(freq):
    if not freq:
        return ""
    if freq < 3000:
        return "2.4 GHz"
    if freq < 5925:
        return "5 GHz"
    return "6 GHz"


def wifi_details(device, runner=run):
    nm = runner(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,FREQ,SECURITY", "dev", "wifi", "list", "ifname", device, "--rescan", "no"])
    found = wifi_from_nmcli(nm)
    if found:
        return found
    found = wifi_from_iwctl(runner(["iwctl", "station", device, "show"]))
    if found:
        return found
    return wifi_from_iw(runner(["iw", "dev", device, "link"]))


# —— Tailscale ——


def tailscale_detail(status):
    """'exit via host' or the tailnet's own name, from `tailscale status --json`."""
    if not isinstance(status, dict) or status.get("BackendState") != "Running":
        return ""
    for peer in (status.get("Peer") or {}).values():
        if isinstance(peer, dict) and peer.get("ExitNode"):
            name = str(peer.get("HostName") or peer.get("DNSName") or "").split(".")[0]
            return "exit via " + name if name else "exit node"
    tailnet = status.get("CurrentTailnet") or {}
    return str(tailnet.get("Name") or "") if isinstance(tailnet, dict) else ""


# —— The sample ——


def link_kind(device, sys_net=SYS_NET):
    if not device:
        return "offline"
    if os.path.isdir(os.path.join(sys_net, device, "wireless")) or os.path.isdir(os.path.join(sys_net, device, "phy80211")):
        return "wifi"
    kind_type = read_int(os.path.join(sys_net, device, "type"))
    # ARPHRD_ETHER is 1. A tun device is 65534, WireGuard 65534 too, PPP 512.
    if kind_type == 1:
        return "ethernet"
    return "tunnel"


def physical_via(links, device):
    """For a VPN that took the default route: the up, non-VPN link it rides on."""
    best = ""
    for link in links if isinstance(links, list) else []:
        if not isinstance(link, dict):
            continue
        name = str(link.get("ifname") or "")
        if not name or name == device or name == "lo" or name.lower().startswith(NOT_VPN):
            continue
        if "LOWER_UP" not in (link.get("flags") or []) or vpn_name(name, str((link.get("linkinfo") or {}).get("info_kind") or "")):
            continue
        if link.get("link_type") == "ether":
            best = best or name
    return best


def sample(runner=run, sys_net=SYS_NET, wall=time.time, sleep=time.sleep, clock=time.monotonic):
    device, gateway, source = route_device(run_json_with(runner, ["ip", "-j", "route", "get", PROBE]))
    links = run_json_with(runner, ["ip", "-j", "-d", "addr", "show"])
    up_vpns = vpns(links)
    out = {
        "ok": True,
        "at": int(wall() * 1000),
        "kind": link_kind(device, sys_net),
        "device": device,
        "via": "",
        "name": "",
        "signal": None,
        "freq": None,
        "band": "",
        "secure": None,
        "speed": None,
        "ipv4": "",
        "ipv6": "",
        "gateway": gateway,
        "rx": None,
        "tx": None,
        "rate": None,
        "vpns": up_vpns,
    }
    if not device:
        return out
    ipv4, ipv6 = addresses(links, device)
    out["ipv4"] = ipv4 or source
    out["ipv6"] = ipv6
    out["rx"] = read_int(os.path.join(sys_net, device, "statistics", "rx_bytes"))
    out["tx"] = read_int(os.path.join(sys_net, device, "statistics", "tx_bytes"))
    counted = clock()
    out["at"] = int(wall() * 1000)
    if out["kind"] == "wifi":
        wifi = wifi_details(device, runner) or {}
        out["name"] = wifi.get("ssid") or ""
        out["signal"] = wifi.get("signal")
        out["freq"] = wifi.get("freq")
        out["band"] = band(wifi.get("freq"))
        out["secure"] = wifi.get("secure")
    elif out["kind"] == "ethernet":
        speed = read_int(os.path.join(sys_net, device, "speed"))
        out["speed"] = speed if speed and speed > 0 else None
    else:
        label = vpn_name(device, "") or "Tunnel"
        out["name"] = label
        out["via"] = physical_via(links, device)
    tailscale = [vpn for vpn in up_vpns if vpn["name"] == "Tailscale"]
    if tailscale:
        status = run_json_with(runner, ["tailscale", "status", "--json"])
        # tailscale0 stays up while tailscaled runs signed out or stopped.
        if isinstance(status, dict) and status.get("BackendState") != "Running":
            out["vpns"] = [vpn for vpn in up_vpns if vpn["name"] != "Tailscale"]
        else:
            for vpn in tailscale:
                vpn["detail"] = tailscale_detail(status)
    if out["rx"] is not None and out["tx"] is not None:
        out["rate"] = measure_rate(device, out, sys_net, counted, sleep, clock, wall)
    return out


def measure_rate(device, out, sys_net, counted, sleep, clock, wall, window=RATE_WINDOW):
    """Bytes a second over a short window, so the tile has a rate on its first
    sample. The counters in `out` move to the end of the window; the tile
    prefers the rate between two of its own samples once it has one."""
    left = window - (clock() - counted)
    if left > 0:
        sleep(left)
    rx = read_int(os.path.join(sys_net, device, "statistics", "rx_bytes"))
    tx = read_int(os.path.join(sys_net, device, "statistics", "tx_bytes"))
    span = clock() - counted
    if rx is None or tx is None or span <= 0 or rx < out["rx"] or tx < out["tx"]:
        return None
    rate = {"down": round((rx - out["rx"]) / span), "up": round((tx - out["tx"]) / span)}
    out["rx"], out["tx"] = rx, tx
    out["at"] = int(wall() * 1000)
    return rate


def run_json_with(runner, argv):
    try:
        return json.loads(runner(argv) or "null")
    except ValueError:
        return None


def parse_ping(text):
    """Milliseconds from one `ping -n -c 1` reply, or None."""
    match = re.search(r"time[=<]\s*([\d.]+)\s*ms", text or "")
    return round(float(match.group(1)), 1) if match else None


def ping(runner=run):
    return {"ok": True, "latency": parse_ping(runner(["ping", "-n", "-c", "1", "-W", "2", PROBE], timeout=4))}


def main(argv):
    payload = ping() if "--ping" in argv[1:] else sample()
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
