#!/usr/bin/env python3
"""CPU, memory, GPU, and VRAM usage plus hardware specs, as one JSON object.

Shared by the sysmon and sysdisk widgets. Stdlib only. Usage comes from /proc
and sysfs. The GPU comes from nvidia-smi when it exists, otherwise sysfs. CPU%
is a short /proc/stat delta, so a 1s poller does not need to keep state.
"""

import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

CPU_DELTA_SECONDS = 0.12


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
    """`utilization.gpu, memory.used, memory.total, clocks.gr` (MiB, MHz) from
    nvidia-smi csv. VRAM comes back in bytes. Values stay strings; num() reads them."""
    fields = ((line or "").split(",", 3) + ["", "", "", ""])[:4]
    return {
        "load": fields[0].replace(" ", ""),
        "vramUsed": mib_bytes(fields[1]),
        "vramTotal": mib_bytes(fields[2]),
        "mhz": fields[3].replace(" ", ""),
    }


def nvidia_gpu(run=run_text):
    query = parse_nvidia_query(first_line(run([
        "nvidia-smi",
        "--query-gpu=utilization.gpu,memory.used,memory.total,clocks.gr",
        "--format=csv,noheader,nounits",
    ])))
    query["name"] = first_line(run(["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"]))
    return query


def parse_sclk(text):
    """Current shader clock from amdgpu `pp_dpm_sclk`: the line marked `*`."""
    for line in (text or "").splitlines():
        if "*" in line:
            parts = re.split(r"[: *]+", line)
            return parts[1].replace("Mhz", "") if len(parts) > 1 else ""
    return ""


def sysfs_gpu(cards=None):
    """Load, clock, and VRAM from the first DRM card that reports gpu_busy_percent."""
    for card in cards if cards is not None else sorted(glob.glob("/sys/class/drm/card*/device")):
        busy = os.path.join(card, "gpu_busy_percent")
        if not os.access(busy, os.R_OK):
            continue
        found = {"load": read_text(busy).strip()}
        sclk = os.path.join(card, "pp_dpm_sclk")
        if os.access(sclk, os.R_OK):
            found["mhz"] = parse_sclk(read_text(sclk))
        used = os.path.join(card, "mem_info_vram_used")
        total = os.path.join(card, "mem_info_vram_total")
        if os.access(used, os.R_OK) and os.access(total, os.R_OK):
            found["vramUsed"] = read_text(used).strip()
            found["vramTotal"] = read_text(total).strip()
        return found
    return None


def gpu_usage():
    gpu = {"load": "", "mhz": "", "name": "", "vramUsed": "", "vramTotal": ""}
    if shutil.which("nvidia-smi"):
        gpu.update(nvidia_gpu())
    if not gpu["load"]:
        gpu.update(sysfs_gpu() or {})
    return gpu


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0

def cpu_info():
    """Model name, thread and physical-core counts from /proc/cpuinfo."""
    model, threads, cores, per_pkg = "", 0, 0, 0
    core_ids, pkg_ids = set(), set()
    try:
        text = open("/proc/cpuinfo").read()
    except OSError:
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
    return m, threads, cores

def gpu_fallback():
    """Model name for non-NVIDIA GPUs via lspci; "" when unavailable."""
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
    DMI properties; falls back to dmidecode (root). "" when neither works,
    and the widget hides the spec."""
    mods = udevadm_sticks()
    if not mods:
        try:
            out = subprocess.run(["dmidecode", "-t", "memory"], capture_output=True, text=True, timeout=10).stdout
        except (OSError, subprocess.SubprocessError):
            return ""
        if not out.strip():
            try:
                out = subprocess.run(["sudo", "-n", "dmidecode", "-t", "memory"], capture_output=True, text=True, timeout=10).stdout
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


def collect():
    mhz = cpu_mhz()
    mem_used, mem_total, mem_pct = parse_meminfo(read_text("/proc/meminfo"))
    gpu = gpu_usage()
    cpu = cpu_percent()
    cpu_model, cpu_threads, cpu_cores = cpu_info()
    gpu_name = gpu["name"]
    if re.search(r"fail|error|unable|no dev|not found|mismatch", gpu_name, re.I):
        gpu_name = ""
    if not gpu_name.strip():
        gpu_name = gpu_fallback()
    vu, vt = num(gpu["vramUsed"]), num(gpu["vramTotal"])
    return {
        "cpu": num(cpu),
        "cpuMHz": num(mhz),
        "cpuModel": cpu_model,
        "cpuCores": cpu_cores,
        "cpuThreads": cpu_threads,
        "memUsed": mem_used,
        "memTotal": mem_total,
        "mem": mem_pct,
        "memConfig": memory_config(),
        "gpu": num(gpu["load"]),
        "gpuMHz": num(gpu["mhz"]),
        "gpuModel": gpu_name.strip(),
        "sysDrive": system_drive(),
        "vramUsed": vu,
        "vramTotal": vt,
        "vram": (100.0 * vu / vt) if vt else 0.0,
    }


def main():
    json.dump(collect(), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
