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
vram_used=""
vram_total=""

if command -v nvidia-smi >/dev/null; then
  set +e
  IFS=',' read -r gpu_load vram_used_mib vram_total_mib gpu_mhz < <(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,clocks.gr --format=csv,noheader,nounits 2>/dev/null | head -1)
  gpu_load=${gpu_load// /}
  gpu_mhz=${gpu_mhz// /}
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
python3 - "$cpu_pct" "${cpu_mhz:-0}" $mem "${gpu_load:-}" "${gpu_mhz:-}" "${vram_used:-}" "${vram_total:-}" <<'PY'
import json, sys
cpu, mhz, mem_used, mem_total, mem_pct, gpu, gpu_mhz, vram_used, vram_total = sys.argv[1:]
def num(v):
    try: return float(v)
    except: return 0.0
mu, mt = num(mem_used), num(mem_total)
vu, vt = num(vram_used), num(vram_total)
print(json.dumps({
  "cpu": num(cpu),
  "cpuMHz": num(mhz),
  "memUsed": mu,
  "memTotal": mt,
  "mem": num(mem_pct),
  "gpu": num(gpu),
  "gpuMHz": num(gpu_mhz),
  "vramUsed": vu,
  "vramTotal": vt,
  "vram": (100.0 * vu / vt) if vt else 0.0
}))
PY
