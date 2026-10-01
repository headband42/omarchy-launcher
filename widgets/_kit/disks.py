#!/usr/bin/env python3
"""List user-facing disks/volumes, mounted or not. Shared by the disks and
sysdisk widgets. Stdlib only.

One row per filesystem (not per btrfs subvolume). Skip boot/ESP/recovery
and tiny partitions. Unmounted NTFS/data volumes are included so they
can be opened (mounted on click).
"""

import json
import os
import re
import subprocess
import sys

SKIP_FS = {"", "swap", "crypto_LUKS", "LVM2_member", "iso9660"}
KEEP_FS = {"ntfs", "ext4", "ext3", "ext2", "btrfs", "xfs", "exfat", "f2fs", "vfat", "ntfs3", "fuseblk"}
SKIP_LABEL = re.compile(r"^(recovery|system reserved|efi|esp|microsoft.*reserved)$", re.I)
MIN_SIZE = 2 * 1024 * 1024 * 1024  # 2 GiB


def mounts_for_device(devpath):
    """All mountpoints for a block device, ignoring btrfs subvol suffix in SOURCE."""
    if not devpath:
        return []
    try:
        raw = subprocess.check_output(["findmnt", "-r", "-n", "-o", "TARGET,SOURCE"], text=True)
    except (OSError, subprocess.CalledProcessError):
        return []
    hits = []
    for line in raw.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        target, source = parts[0], parts[1]
        base = source.split("[", 1)[0]
        if base == devpath or source.startswith(devpath + "["):
            hits.append(target)
    rank = lambda p: (0 if p == "/home" else 1 if p == "/" else 2, len(p))
    hits.sort(key=rank)
    return hits


def lsblk() -> list:
    raw = subprocess.check_output(
        [
            "lsblk", "-J", "-b",
            "-o", "NAME,PATH,FSTYPE,LABEL,MOUNTPOINT,SIZE,FSUSED,FSSIZE,TYPE,PKNAME,UUID,HOTPLUG,RM,MODEL",
        ],
        text=True,
    )
    return json.loads(raw).get("blockdevices") or []


def walk(nodes, disk_model=""):
    rows = []
    for node in nodes:
        model = str(node.get("model") or disk_model or "")
        ntype = str(node.get("type") or "")
        children = node.get("children") or []
        if ntype == "loop":
            rows.extend(walk(children, model))
            continue
        if ntype == "disk" and children:
            # Partitioned disk: the partitions below carry the volumes.
            # A childless disk with its own fstype (superfloppy USB stick)
            # falls through and is treated as a volume.
            rows.extend(walk(children, model))
            continue
        fstype = str(node.get("fstype") or "").lower()
        size = int(node.get("size") or 0)
        label = str(node.get("label") or "").strip()
        if size < MIN_SIZE or SKIP_LABEL.match(label):
            rows.extend(walk(children, model))
            continue
        if fstype == "vfat" and not node.get("rm") and not node.get("hotplug"):
            rows.extend(walk(children, model))
            continue
        name = str(node.get("name") or "")
        device = str(node.get("path") or f"/dev/{name}")
        extras = mounts_for_device(device)
        mount = extras[0] if extras else (node.get("mountpoint") or "")
        if fstype == "swap":
            # Active swap (zram "[SWAP]") is never a user-facing volume.
            rows.extend(walk(children, model))
            continue
        if not mount and (fstype in SKIP_FS or (fstype and fstype not in KEEP_FS)):
            # Unmounted media must look like openable data to be listed.
            # Anything already mounted is user-facing, whatever its fstype
            # (live-USB iso9660, video DVD, ...).
            rows.extend(walk(children, model))
            continue
        used = int(node.get("fsused") or 0)
        fssize = int(node.get("fssize") or 0) or size
        source_key = str(node.get("uuid") or name)
        rows.append({
            "device": device,
            "source": source_key,
            "path": mount,
            "label": label or model or name,
            "fstype": fstype,
            "size": fssize if mount else size,
            "used": used if mount else 0,
            "pct": (100.0 * used / fssize) if mount and fssize else 0.0,
            "mounted": bool(mount),
            "removable": bool(node.get("rm") or node.get("hotplug")),
        })
        rows.extend(walk(children, model))
    return rows


def collapse(rows: list) -> list:
    """One row per uuid/device; prefer /home then / then any mount."""
    by_key = {}
    rank = lambda p: (0 if p == "/home" else 1 if p == "/" else 2 if p else 3, len(p or ""))
    for row in rows:
        key = row["source"] or row["device"]
        prev = by_key.get(key)
        if not prev or rank(row["path"]) < rank(prev["path"]):
            if prev and prev["used"] and not row["used"]:
                row["used"] = prev["used"]
                row["size"] = prev["size"] or row["size"]
                row["pct"] = prev["pct"]
            by_key[key] = row
        elif prev and row["used"] and not prev["used"]:
            prev["used"] = row["used"]
            prev["size"] = row["size"] or prev["size"]
            prev["pct"] = row["pct"]
    out = list(by_key.values())
    for row in out:
        if row["path"] in ("/", "/home"):
            row["label"] = "System"
        if not row["label"]:
            row["label"] = os.path.basename(row["path"].rstrip("/")) or row["device"].split("/")[-1]
    out.sort(key=lambda r: (0 if r["path"] in ("/", "/home") else 1, r["label"].lower()))
    return out[:8]


def main() -> None:
    try:
        rows = collapse(walk(lsblk()))
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError, ValueError):
        rows = []
    json.dump(rows, sys.stdout)


if __name__ == "__main__":
    main()
