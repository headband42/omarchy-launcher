#!/usr/bin/env bash
# Print one JSON sample of CPU, memory, GPU, and VRAM. CPU% uses a short
# /proc/stat delta so a 1s poller does not need to keep state.

set -euo pipefail

read_cpu() {
  local a b
  a=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat)
  sleep 0.12
  b=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat)
  python3 - "$a" "$b" <<'PY'
import sys
t0, i0 = map(int, sys.argv[1].split())
t1, i1 = map(int, sys.argv[2].split())
dt = max(1, t1 - t0)
idle = max(0, i1 - i0)
print(round(100.0 * (dt - idle) / dt, 1))
PY
}

cpu_mhz=$(awk '/^cpu MHz/ {s+=$4; n++;} END { if(n) printf "%.0f", s/n }' /proc/cpuinfo)
if [[ -z ${cpu_mhz:-} && -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
  cpu_mhz=$(awk '{printf "%.0f", $1/1000}' /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
fi

mem=$(awk '
  /^MemTotal:/ {t=$2}
  /^MemAvailable:/ {a=$2}
  END {
    t=t*1024; used=(t-a*1024);
    printf "%.0f %.0f %.1f", used, t, (t>0?100*used/t:0)
  }
' /proc/meminfo)

gpu_load=""
gpu_mhz=""
gpu_name=""
vram_used=""
vram_total=""

if command -v nvidia-smi >/dev/null; then
  set +e
  IFS=',' read -r gpu_load vram_used_mib vram_total_mib gpu_mhz < <(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,clocks.gr --format=csv,noheader,nounits 2>/dev/null | head -1)
  gpu_load=${gpu_load// /}
  gpu_mhz=${gpu_mhz// /}
  gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
  vram_used=$(python3 -c "print(int(float('${vram_used_mib:-0}')*1024*1024))" 2>/dev/null)
  vram_total=$(python3 -c "print(int(float('${vram_total_mib:-0}')*1024*1024))" 2>/dev/null)
  set -e
fi

if [[ -z ${gpu_load:-} ]]; then
  for card in /sys/class/drm/card*/device; do
    [[ -r $card/gpu_busy_percent ]] || continue
    gpu_load=$(cat "$card/gpu_busy_percent")
    if [[ -r $card/pp_dpm_sclk ]]; then
      gpu_mhz=$(awk -F'[: *]+' '/\*/ {gsub(/Mhz/,"",$2); print $2; exit}' "$card/pp_dpm_sclk")
    fi
    if [[ -r $card/mem_info_vram_used && -r $card/mem_info_vram_total ]]; then
      vram_used=$(cat "$card/mem_info_vram_used")
      vram_total=$(cat "$card/mem_info_vram_total")
    fi
    break
  done
fi

cpu_pct=$(read_cpu)
python3 - "$cpu_pct" "${cpu_mhz:-0}" $mem "${gpu_load:-}" "${gpu_mhz:-}" "${vram_used:-}" "${vram_total:-}" "${gpu_name:-}" <<'PY'
import json, re, subprocess, sys
cpu, mhz, mem_used, mem_total, mem_pct, gpu, gpu_mhz, vram_used, vram_total, gpu_name = sys.argv[1:]
def num(v):
    try: return float(v)
    except: return 0.0

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

cpu_model, cpu_threads, cpu_cores = cpu_info()
if re.search(r"fail|error|unable|no dev|not found|mismatch", gpu_name, re.I):
    gpu_name = ""
if not gpu_name.strip():
    gpu_name = gpu_fallback()
mu, mt = num(mem_used), num(mem_total)
vu, vt = num(vram_used), num(vram_total)
print(json.dumps({
  "cpu": num(cpu),
  "cpuMHz": num(mhz),
  "cpuModel": cpu_model,
  "cpuCores": cpu_cores,
  "cpuThreads": cpu_threads,
  "memUsed": mu,
  "memTotal": mt,
  "mem": num(mem_pct),
  "memConfig": memory_config(),
  "gpu": num(gpu),
  "gpuMHz": num(gpu_mhz),
  "gpuModel": gpu_name.strip(),
  "vramUsed": vu,
  "vramTotal": vt,
  "vram": (100.0 * vu / vt) if vt else 0.0
}))
PY
