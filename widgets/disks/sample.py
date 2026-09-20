#!/usr/bin/env python3
"""List mounted disks as JSON. Skip virtual filesystems."""

import json
import os
import subprocess
import sys

SKIP_FS = {
    "tmpfs", "devtmpfs", "squashfs", "overlay", "proc", "sysfs", "cgroup",
    "cgroup2", "devpts", "securityfs", "pstore", "bpf", "tracefs", "debugfs",
    "hugetlbfs", "mqueue", "fusectl", "configfs", "ramfs", "autofs",
    "fuse.portal", "fuse.gvfsd-fuse", "nsfs", "binfmt_misc",
}


def main() -> None:
    try:
        raw = subprocess.check_output(["findmnt", "-J", "-b", "-o", "TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL,LABEL"], text=True)
        filesystems = json.loads(raw).get("filesystems") or []
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        filesystems = []

    rows = []

    def walk(nodes):
        for node in nodes:
            fstype = str(node.get("fstype") or "")
            target = str(node.get("target") or "")
            if not target or fstype in SKIP_FS or target.startswith("/boot") or target.startswith("/efi"):
                walk(node.get("children") or [])
                continue
            if target in ("/",) or target.startswith("/home") or target.startswith("/run/media") or target.startswith("/media") or target.startswith("/mnt"):
                size = int(node.get("size") or 0)
                used = int(node.get("used") or 0)
                label = str(node.get("label") or "") or os.path.basename(target.rstrip("/")) or target
                if target == "/":
                    label = "System"
                rows.append({
                    "path": target,
                    "label": label,
                    "fstype": fstype,
                    "size": size,
                    "used": used,
                    "pct": (100.0 * used / size) if size else 0.0,
                    "removable": target.startswith("/run/media") or target.startswith("/media"),
                })
            walk(node.get("children") or [])

    walk(filesystems)
    # Prefer unique paths, system first then others.
    uniq = {}
    for row in rows:
        uniq[row["path"]] = row
    ordered = sorted(uniq.values(), key=lambda r: (0 if r["path"] == "/" else 1 if r["path"].startswith("/home") else 2, r["path"]))
    json.dump(ordered[:8], sys.stdout)


if __name__ == "__main__":
    main()
