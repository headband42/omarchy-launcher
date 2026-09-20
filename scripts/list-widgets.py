#!/usr/bin/env python3
"""Emit bundled + user launcher widgets as one JSON array. User dir wins on id."""

import json
import sys
from pathlib import Path


def load_dir(root: Path) -> list:
    if not root.is_dir():
        return []
    rows = []
    for path in sorted(root.iterdir()):
        meta_path = path / "widget.json"
        qml_path = path / "Widget.qml"
        if not meta_path.is_file() or not qml_path.is_file():
            continue
        try:
            data = json.loads(meta_path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(data, dict):
            continue
        widget_id = str(data.get("id") or path.name).strip()
        if not widget_id:
            continue
        data["id"] = widget_id
        data["qml"] = str(qml_path.resolve())
        data["dir"] = str(path.resolve())
        rows.append(data)
    return rows


def main() -> None:
    bundled = Path(sys.argv[1]) if len(sys.argv) > 1 else Path()
    user = Path(sys.argv[2]) if len(sys.argv) > 2 else Path()
    seen = set()
    out = []
    for row in load_dir(user) + load_dir(bundled):
        if row["id"] in seen:
            continue
        seen.add(row["id"])
        out.append(row)
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
