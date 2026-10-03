#!/usr/bin/env python3
"""CPU, memory, GPU, and VRAM usage, and the hardware specs, as one JSON object.

Shared by the sysmon and sysdisk widgets. Stdlib only. Usage comes from /proc
and sysfs. The GPU comes from nvidia-smi when it exists, otherwise sysfs.

A plain run is the usage the tile polls. It carries the CPU's /proc/stat
counters (`cpuTicks`) and the tile works out CPU % between its own samples,
so the reading covers the whole interval and the run never waits.

  --warm    also measure CPU % over a short window, for the first sample
            of a session, before there are two samples to compare
  --specs   also read the hardware specs, which do not change while the tile
            is open, so the tile asks for them once
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

CPU_DELTA_SECONDS = 0.12
PCI_DEVICES = "/sys/bus/pci/devices"
NVIDIA_PROC = "/proc/driver/nvidia/gpus"
HWMON = "/sys/class/hwmon"
THERMAL = "/sys/class/thermal"
DRM = "/sys/class/drm"
NVIDIA_QUERY = "utilization.gpu,memory.used,memory.total,clocks.gr,temperature.gpu"
GPU_ERROR = re.compile(r"fail|error|unable|no dev|not found|mismatch", re.I)
# hwmon drivers that report the CPU package, each with the labels to prefer.
# k10temp's Tctl carries an offset on some early Ryzens, which also report Tdie.
CPU_SENSORS = (
    ("k10temp", ("Tdie", "Tctl")),
    ("zenpower", ("Tdie", "Tctl")),
    ("coretemp", ("Package id 0",)),
    ("cpu_thermal", ()),
    ("cpu-thermal", ()),
)
CPU_ZONES = ("x86_pkg_temp", "cpu-thermal", "cpu_thermal")


def read_text(path):
    try:
        with open(path) as fh:
            return fh.read()
    except OSError:
        return ""


def run_text(argv, timeout=5):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def first_line(text):
    lines = (text or "").splitlines()
    return lines[0] if lines else ""


def parse_cpu_times(stat_text):
    """(total, idle) jiffies from the aggregate `cpu ` line of /proc/stat.
    Total is user..softirq; idle does not count iowait."""
    for line in (stat_text or "").splitlines():
        if line.startswith("cpu "):
            fields = line.split()
            try:
                values = [int(v) for v in fields[1:8]]
            except ValueError:
                return None
            if len(values) < 7:
                return None
            return sum(values), values[3]
    return None


def cpu_percent_between(before, after):
    if not before or not after:
        return 0.0
    dt = max(1, after[0] - before[0])
    idle = max(0, after[1] - before[1])
    return round(100.0 * (dt - idle) / dt, 1)


def cpu_percent(delay=CPU_DELTA_SECONDS):
    before = parse_cpu_times(read_text("/proc/stat"))
    time.sleep(delay)
    after = parse_cpu_times(read_text("/proc/stat"))
    return cpu_percent_between(before, after)


def parse_cpu_mhz(cpuinfo_text):
    """Average `cpu MHz` across cores, rounded; "" when cpuinfo has none."""
    values = []
    for line in (cpuinfo_text or "").splitlines():
        if line.startswith("cpu MHz") and ":" in line:
            try:
                values.append(float(line.split(":", 1)[1]))
            except ValueError:
                pass
    if not values:
        return ""
    return "%.0f" % (sum(values) / len(values))


def cpu_mhz():
    mhz = parse_cpu_mhz(read_text("/proc/cpuinfo"))
    if not mhz:
        khz = read_text("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq").strip()
        try:
            mhz = "%.0f" % (float(khz) / 1000)
        except ValueError:
            mhz = ""
    return mhz


def parse_meminfo(meminfo_text):
    """(used bytes, total bytes, used %). Used is total minus MemAvailable."""
    fields = {}
    for line in (meminfo_text or "").splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("MemTotal:", "MemAvailable:"):
            try:
                fields[parts[0]] = int(parts[1])
            except ValueError:
                pass
    total = fields.get("MemTotal:", 0) * 1024
    used = total - fields.get("MemAvailable:", 0) * 1024
    pct = 100.0 * used / total if total > 0 else 0.0
    return float("%.0f" % used), float("%.0f" % total), float("%.1f" % pct)


def mib_bytes(text):
    try:
        return str(int(float(text or "0") * 1024 * 1024))
    except ValueError:
        return ""


def parse_nvidia_query(line):
    """`utilization.gpu, memory.used, memory.total, clocks.gr, temperature.gpu`
    (MiB, MHz, °C) from nvidia-smi csv. VRAM comes back in bytes. Values stay
    strings; num() reads them."""
    fields = ((line or "").split(",", 4) + [""] * 5)[:5]
    return {
        "load": fields[0].replace(" ", ""),
        "vramUsed": mib_bytes(fields[1]),
        "vramTotal": mib_bytes(fields[2]),
        "mhz": fields[3].replace(" ", ""),
        "temp": fields[4].replace(" ", ""),
    }


def nvidia_gpu(run=run_text):
    return parse_nvidia_query(first_line(run([
        "nvidia-smi", "--query-gpu=" + NVIDIA_QUERY, "--format=csv,noheader,nounits",
    ])))


def runtime_status(device):
    """A device's runtime power state: `active`, `suspended`, ... Reading it
    never wakes the device, unlike the driver's own files."""
    return read_text(os.path.join(device, "power", "runtime_status")).strip()


def nvidia_devices(pci=PCI_DEVICES):
    """PCI folders of NVIDIA display controllers (class 0x03xxxx)."""
    try:
        names = sorted(os.listdir(pci))
    except OSError:
        return []
    out = []
    for name in names:
        device = os.path.join(pci, name)
        if read_text(os.path.join(device, "vendor")).strip().lower() != "0x10de":
            continue
        if not read_text(os.path.join(device, "class")).strip().lower().startswith("0x03"):
            continue
        out.append(device)
    return out


def nvidia_asleep(pci=PCI_DEVICES):
    """True when every NVIDIA GPU is runtime-suspended. nvidia-smi would wake
    it, and on a hybrid laptop keep it awake for as long as the tile is open."""
    devices = nvidia_devices(pci)
    return bool(devices) and all(runtime_status(d) == "suspended" for d in devices)


def milli_celsius(path):
    """°C from a sysfs file in millidegrees; None when unreadable or implausible."""
    try:
        value = int(read_text(path).strip())
    except ValueError:
        return None
    if value <= 0 or value >= 150000:
        return None
    return round(value / 1000.0, 1)


def hwmon_temp(folder, labels=()):
    """°C from a hwmon folder: the first of `labels` it reports, else temp1."""
    by_label = {}
    for path in sorted(glob.glob(os.path.join(folder, "temp*_input"))):
        label = read_text(path[: -len("_input")] + "_label").strip()
        if label:
            by_label.setdefault(label, path)
    for want in labels:
        if want in by_label:
            return milli_celsius(by_label[want])
    return milli_celsius(os.path.join(folder, "temp1_input"))


def cpu_temp(hwmon=HWMON, thermal=THERMAL):
    """The CPU package temperature from hwmon, else a CPU thermal zone."""
    folders = {}
    for folder in sorted(glob.glob(os.path.join(hwmon, "hwmon*"))):
        folders.setdefault(read_text(os.path.join(folder, "name")).strip(), folder)
    for name, labels in CPU_SENSORS:
        if name in folders:
            found = hwmon_temp(folders[name], labels)
            if found is not None:
                return found
    for zone in sorted(glob.glob(os.path.join(thermal, "thermal_zone*"))):
        if read_text(os.path.join(zone, "type")).strip() in CPU_ZONES:
            found = milli_celsius(os.path.join(zone, "temp"))
            if found is not None:
                return found
    return None


def parse_sclk(text):
    """Current shader clock from amdgpu `pp_dpm_sclk`: the line marked `*`."""
    for line in (text or "").splitlines():
        if "*" in line:
            parts = re.split(r"[: *]+", line)
            return parts[1].replace("Mhz", "") if len(parts) > 1 else ""
    return ""


def sysfs_gpu(cards=None):
    """Load, clock, VRAM, and temperature from the first DRM card that reports
    gpu_busy_percent. A card the kernel has put to sleep is reported asleep and
    left alone: amdgpu wakes the card to answer any of its own files."""
    for card in cards if cards is not None else sorted(glob.glob(DRM + "/card*/device")):
        busy = os.path.join(card, "gpu_busy_percent")
        if not os.access(busy, os.R_OK):
            continue
        if runtime_status(card) == "suspended":
            return {"asleep": True}
        found = {"load": read_text(busy).strip()}
        sclk = os.path.join(card, "pp_dpm_sclk")
        if os.access(sclk, os.R_OK):
            found["mhz"] = parse_sclk(read_text(sclk))
        used = os.path.join(card, "mem_info_vram_used")
        total = os.path.join(card, "mem_info_vram_total")
        if os.access(used, os.R_OK) and os.access(total, os.R_OK):
            found["vramUsed"] = read_text(used).strip()
            found["vramTotal"] = read_text(total).strip()
        for folder in sorted(glob.glob(os.path.join(card, "hwmon", "hwmon*"))):
            temp = hwmon_temp(folder, ("edge",))
            if temp is not None:
                found["temp"] = str(temp)
                break
        return found
    return None


def intel_gpu(drm=DRM):
    """The clock of an Intel GPU (i915 or xe). Neither has a load counter a
    user can read, so the load stays unknown."""
    for card in sorted(glob.glob(os.path.join(drm, "card*"))):
        if "-" in os.path.basename(card):
            continue
        driver = os.path.basename(os.path.realpath(os.path.join(card, "device", "driver")))
        if driver == "i915":
            paths = [os.path.join(card, "gt_act_freq_mhz"), os.path.join(card, "gt", "gt0", "rps_act_freq_mhz")]
        elif driver == "xe":
            paths = sorted(glob.glob(os.path.join(card, "device", "tile*", "gt0", "freq0", "act_freq")))
        else:
            continue
        for path in paths:
            mhz = read_text(path).strip()
            if mhz.isdigit() and int(mhz) > 0:
                return {"mhz": mhz}
    return None


def gpu_usage(run=run_text, which=shutil.which, pci=PCI_DEVICES, cards=None, drm=DRM):
    gpu = {"load": "", "mhz": "", "vramUsed": "", "vramTotal": "", "temp": "", "asleep": False}
    if which("nvidia-smi"):
        if nvidia_asleep(pci):
            gpu["asleep"] = True
            return gpu
        gpu.update(nvidia_gpu(run))
    if not gpu["load"]:
        gpu.update(sysfs_gpu(cards) or {})
        if gpu["asleep"]:
            return gpu
    if not gpu["load"] and not num(gpu["mhz"]):
        gpu.update(intel_gpu(drm) or {})
    return gpu


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def num_or_none(v):
    """A reading the GPU gave, or None for one it did not ([N/A], empty)."""
    try:
        return float(v)
    except (TypeError, ValueError):
        return None

def cpu_info(text=None):
    """Model name, thread and physical-core counts from /proc/cpuinfo."""
    model, threads, cores, per_pkg = "", 0, 0, 0
    core_ids, pkg_ids = set(), set()
    if text is None:
        text = read_text("/proc/cpuinfo")
    if not text:
        return model, threads, cores
    for line in text.splitlines():
        if line.startswith("model name"):
            if not model:
                model = line.split(":", 1)[1].strip()
        elif line.startswith("processor"):
            threads += 1
        elif line.startswith("core id"):
            core_ids.add(line.split(":", 1)[1].strip())
        elif line.startswith("physical id"):
            pkg_ids.add(line.split(":", 1)[1].strip())
        elif line.startswith("cpu cores"):
            try: per_pkg = int(line.split(":", 1)[1].strip())
            except ValueError: pass
    if len(core_ids) > 1:
        cores = len(core_ids)
    elif per_pkg:
        cores = per_pkg * (len(pkg_ids) or 1)
    else:
        cores = threads
    m = re.sub(r"\(R\)|\(TM\)|[®™]", "", model)
    m = re.sub(r"\s+", " ", m).strip()
    m = re.sub(r"\s*@.*$", "", m)
    m = re.sub(r"\s+(Processor|CPU)\s*$", "", m, flags=re.I)
    # "16-Core" / "Eight-Core": the core count is its own spec.
    m = re.sub(r"\s+(\d+|[A-Za-z]+)-Core$", "", m)
    return m, threads, cores

def gpu_fallback():
    """Model name from lspci, preferring a GPU that is not Intel's; "" when
    unavailable."""
    try:
        out = subprocess.run(["lspci", "-mm"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    cands = []
    for line in out.splitlines():
        if not re.search(r'"(VGA compatible controller|3D controller|Display controller)"', line):
            continue
        parts = re.findall(r'"([^"]*)"', line)
        if len(parts) < 3:
            continue
        vendor, dev = parts[1], parts[2]
        dev = re.sub(r"\[[^\]]*(?:Corp|Inc|Ltd|ATI|Technolog)[^\]]*\]", "", dev)
        dev = dev.replace("[", "").replace("]", "")
        dev = re.sub(r"\s+", " ", dev).strip(" -")
        if dev.lower().startswith(vendor.lower()):
            dev = dev[len(vendor):].strip(" -")
        if dev:
            cands.append(dev)
    if not cands:
        return ""
    for c in cands:
        if not re.search(r"intel", c, re.I):
            return c
    return cands[0]

def fmt_gb(mb):
    return "%dG" % (mb // 1024) if mb % 1024 == 0 else "%.1fG" % (mb / 1024)

def udevadm_sticks():
    """Populated memory modules from udev's world-readable DMI properties
    (udevadm info -p /devices/virtual/dmi/id). No root, no extra packages."""
    try:
        out = subprocess.run(["udevadm", "info", "-p", "/devices/virtual/dmi/id"], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    devs = {}
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("E: MEMORY_DEVICE_"):
            continue
        mm = re.match(r"E: MEMORY_DEVICE_(\d+)_([A-Z_]+)=(.*)$", line)
        if not mm:
            continue
        idx, key, val = mm.groups()
        devs.setdefault(idx, {})[key] = val.strip()
    def mts(raw):
        v = (raw or "").strip()
        return v + " MT/s" if v.isdigit() else ""
    sticks = []
    for idx in sorted(devs, key=int):
        d = devs[idx]
        if d.get("PRESENT", "1") == "0":
            continue
        try:
            size_b = int(d.get("SIZE", "0") or "0")
        except ValueError:
            continue
        if size_b <= 0:
            continue
        sticks.append({
            "Size": "%d MB" % (size_b // 1048576),
            "Type": d.get("TYPE", ""),
            "Speed": mts(d.get("SPEED_MTS", "")),
            "Configured Memory Speed": mts(d.get("CONFIGURED_SPEED_MTS", "")),
            "Bank Locator": d.get("BANK_LOCATOR", ""),
            "Locator": d.get("LOCATOR", ""),
        })
    return sticks

def dmidecode_sticks(text):
    sticks, cur, in_mem = [], {}, False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("Handle "):
            if cur and in_mem:
                sticks.append(cur)
            cur, in_mem = {}, False
            continue
        if s == "Memory Device":
            in_mem = True
            continue
        if in_mem and ":" in s:
            k, v = s.split(":", 1)
            cur[k.strip()] = v.strip()
    if cur and in_mem:
        sticks.append(cur)
    return [m for m in sticks if m.get("Size", "").lower() not in ("", "no module installed")]

def memory_config():
    """E.g. '2×32G DDR5-5600 dual-channel'. Prefers udev's world-readable
    DMI properties; falls back to dmidecode, which only works as root. "" when
    neither works, and the widget hides the spec. Never `sudo -n`: every
    refusal is a line in the system journal."""
    mods = udevadm_sticks()
    if not mods:
        try:
            out = subprocess.run(["dmidecode", "-t", "memory"], capture_output=True, text=True, timeout=10).stdout
        except (OSError, subprocess.SubprocessError):
            return ""
        if not out.strip():
            return ""
        mods = dmidecode_sticks(out)
    return build_config(mods)

def build_config(mods):
    if not mods:
        return ""
    def to_mb(sz):
        mt = re.match(r"(\d+)\s*(MB|GB)", sz, re.I)
        if not mt:
            return 0
        return int(mt.group(1)) * (1024 if mt.group(2).upper() == "GB" else 1)
    sizes = [to_mb(m.get("Size", "")) for m in mods]
    if any(s <= 0 for s in sizes):
        return ""
    if len(set(sizes)) == 1:
        cfg = "%d×%s" % (len(mods), fmt_gb(sizes[0]))
    else:
        cfg = "%s mixed" % fmt_gb(sum(sizes))
    types = {m.get("Type", "").strip() for m in mods} - {"", "Unknown"}
    if len(types) == 1:
        cfg += " " + types.pop()
    speeds = set()
    for m in mods:
        for k in ("Configured Memory Speed", "Speed"):
            sp = re.match(r"(\d+)", m.get(k, ""))
            if sp:
                speeds.add(int(sp.group(1)))
                break
    if len(speeds) == 1:
        cfg += "-%d" % speeds.pop()
    chans = set()
    for m in mods:
        for k in ("Bank Locator", "Locator"):
            mt = re.search(r"channel\s*([A-Z0-9]+)", m.get(k, ""), re.I)
            if mt:
                chans.add(mt.group(1).upper())
    if len(chans) > 1:
        cfg += " " + {2: "dual-channel", 4: "quad-channel", 8: "octa-channel"}.get(len(chans), "%d-channel" % len(chans))
    return cfg

def mount_source(mp):
    try:
        out = subprocess.run(["findmnt", "-n", "-o", "SOURCE", mp], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.splitlines()[0].strip() if out.strip() else ""

def strip_mount_suffix(src):
    return re.sub(r"\[.*\]$", "", src or "")

def parent_name(kname):
    return re.sub(r"p?\d+$", "", kname or "")

def resolve_disk_kname(src):
    """Kernel name (e.g. nvme2n1) of the physical disk behind a mount source.
    Walks device-mapper slaves via sysfs, then strips a partition suffix."""
    src = strip_mount_suffix(src)
    if not src.startswith("/dev/"):
        return ""
    kname = src[len("/dev/"):]
    if kname.startswith("mapper/") or kname.startswith("dm-"):
        want = kname.split("/", 1)[1] if "/" in kname else kname
        for _ in range(6):
            found = ""
            try:
                candidates = os.listdir("/sys/block")
            except OSError:
                return ""
            for cand in candidates:
                if not cand.startswith("dm-"):
                    continue
                try:
                    with open("/sys/block/%s/dm/name" % cand) as fh:
                        name = fh.read().strip()
                except OSError:
                    continue
                if name == want or cand == want:
                    found = cand
                    break
            if not found:
                return ""
            try:
                slaves = sorted(os.listdir("/sys/block/%s/slaves" % found))
            except OSError:
                return ""
            if not slaves:
                return ""
            kname = slaves[0]
            if not kname.startswith("dm-"):
                break
            want = kname
        else:
            return ""
    base = "/sys/class/block/"
    if not os.path.exists(base + kname + "/partition"):
        return kname if os.path.exists(base + kname) else ""
    parent = parent_name(kname)
    return parent if os.path.exists(base + parent) else ""

def lsblk_tree():
    try:
        out = subprocess.run(["lsblk", "-J", "-b", "-o", "NAME,PATH,TYPE,MODEL,SIZE,TRAN"], capture_output=True, text=True, timeout=10).stdout
        return json.loads(out).get("blockdevices") or []
    except (OSError, subprocess.SubprocessError, ValueError):
        return []

def find_disk_node(nodes, disk):
    for n in nodes or []:
        if n.get("path") == "/dev/" + disk or n.get("name") == disk:
            return n
        hit = find_disk_node(n.get("children"), disk)
        if hit:
            return hit
    return None

def fmt_size(b):
    try:
        b = int(b)
    except (TypeError, ValueError):
        return ""
    if b <= 0:
        return ""
    if b >= 1099511627776:
        return "%.1fT" % (b / 1099511627776)
    if b >= 1073741824:
        return "%.1fG" % (b / 1073741824)
    if b >= 1048576:
        return "%dM" % (b // 1048576)
    return "%dK" % (b // 1024)

def sysfs_text(path):
    try:
        with open(path) as fh:
            return fh.read().strip()
    except OSError:
        return ""

def pcie_label(speed_text, width_text):
    """'32.0 GT/s PCIe' + '4' -> 'PCIe 5.0 x4'. Pure; file reads happen in pcie_link."""
    m = re.search(r"([\d.]+)\s*GT/s", speed_text or "")
    if not m:
        return ""
    try:
        speed = float(m.group(1))
    except ValueError:
        return ""
    gen = ""
    for floor, name in ((64.0, "6.0"), (32.0, "5.0"), (16.0, "4.0"), (8.0, "3.0"), (5.0, "2.0"), (2.5, "1.0")):
        if speed >= floor - 0.01:
            gen = name
            break
    if not gen:
        return ""
    wm = re.search(r"(\d+)", width_text or "")
    return "PCIe %s x%s" % (gen, wm.group(1)) if wm else "PCIe %s" % gen

def pcie_link(disk):
    """Negotiated PCIe link of an NVMe disk via PCI sysfs (world-readable)."""
    try:
        real = os.path.realpath("/sys/class/block/" + disk)
    except OSError:
        return ""
    addr = ""
    for part in real.split(os.sep):
        if re.fullmatch(r"[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.\d", part):
            addr = part
    if not addr:
        return ""
    base = "/sys/bus/pci/devices/" + addr + "/"
    speed = sysfs_text(base + "current_link_speed") or sysfs_text(base + "max_link_speed")
    width = sysfs_text(base + "current_link_width") or sysfs_text(base + "max_link_width")
    return pcie_label(speed, width)

def sata_label(spd_text):
    """"6.0 Gbps" -> "SATA 6Gb/s". Pure; the file read happens in sata_link."""
    m = re.search(r"([\d.]+)\s*Gbps", spd_text or "")
    if not m:
        return ""
    try:
        return "SATA %gGb/s" % float(m.group(1))
    except ValueError:
        return ""

def sata_link(disk):
    """Negotiated SATA speed via ata_link sysfs (world-readable)."""
    try:
        real = os.path.realpath("/sys/class/block/" + disk)
    except OSError:
        return ""
    m = re.search(r"/ata(\d+)/", real)
    if not m:
        return ""
    return sata_label(sysfs_text("/sys/class/ata_link/link%s/sata_spd" % m.group(1)))

def system_drive():
    """E.g. '3.6T · NVMe · PCIe 5.0 x4' for the disk backing /."""
    src = mount_source("/") or mount_source("/home") or mount_source("/boot")
    disk = resolve_disk_kname(src)
    if not disk:
        return ""
    node = find_disk_node(lsblk_tree(), disk)
    if not node:
        return ""
    tran = str(node.get("tran") or "").lower()
    link = ""
    if disk.startswith("nvme"):
        link = pcie_link(disk)
    if not link:
        link = sata_link(disk)
    parts = []
    cap = fmt_size(node.get("size"))
    if cap:
        parts.append(cap)
    if tran == "nvme":
        parts.append("NVMe")
        if link:
            parts.append(link)
    elif tran == "sata":
        parts.append(link or "SATA")
    elif tran == "usb":
        parts.append("USB")
    elif link:
        parts.append(link)
    return " · ".join(parts)


def gpu_model(run=run_text, which=shutil.which, pci=PCI_DEVICES, proc=NVIDIA_PROC):
    """The GPU's name without waking it. NVIDIA's driver keeps it under /proc;
    nvidia-smi is asked only while the GPU is awake, and lspci is the rest."""
    for info in sorted(glob.glob(os.path.join(proc, "*", "information"))):
        for line in read_text(info).splitlines():
            if line.startswith("Model:"):
                name = line.split(":", 1)[1].strip()
                if name:
                    return name
    if which("nvidia-smi") and not nvidia_asleep(pci):
        name = first_line(run(["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"])).strip()
        if name and not GPU_ERROR.search(name):
            return name
    return gpu_fallback()


def usage(warm=False):
    """The polled sample. `cpu` is present only with `warm`."""
    before = parse_cpu_times(read_text("/proc/stat")) if warm else None
    if warm:
        time.sleep(CPU_DELTA_SECONDS)
    ticks = parse_cpu_times(read_text("/proc/stat"))
    mem_used, mem_total, mem_pct = parse_meminfo(read_text("/proc/meminfo"))
    gpu = gpu_usage()
    vu, vt = num(gpu["vramUsed"]), num(gpu["vramTotal"])
    temp = num_or_none(gpu["temp"])
    out = {
        "cpuTicks": list(ticks) if ticks else None,
        "cpuMHz": num(cpu_mhz()),
        "cpuTemp": cpu_temp(),
        "memUsed": mem_used,
        "memTotal": mem_total,
        "mem": mem_pct,
        "gpu": num_or_none(gpu["load"]),
        "gpuMHz": num(gpu["mhz"]),
        "gpuTemp": temp if temp and temp > 0 else None,
        "gpuAsleep": bool(gpu["asleep"]),
        "vramUsed": vu,
        "vramTotal": vt,
        "vram": (100.0 * vu / vt) if vt else 0.0,
    }
    if warm:
        out["cpu"] = cpu_percent_between(before, ticks)
    return out


def specs():
    cpu_model, cpu_threads, cpu_cores = cpu_info()
    return {
        "cpuModel": cpu_model,
        "cpuCores": cpu_cores,
        "cpuThreads": cpu_threads,
        "memConfig": memory_config(),
        "gpuModel": gpu_model(),
        "sysDrive": system_drive(),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description="CPU, memory, and GPU usage as JSON.")
    parser.add_argument("--warm", action="store_true",
                        help="also measure CPU %% over a short window, for a session's first sample")
    parser.add_argument("--specs", action="store_true",
                        help="also read the hardware specs, which the tile asks for once")
    args = parser.parse_args(argv)
    out = usage(warm=args.warm)
    if args.specs:
        out.update(specs())
    json.dump(out, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
