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
        # `_kit` and any other `_` folder is shared code, not a widget.
        if path.name.startswith("_"):
            continue
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
        if not widget_id or widget_id.startswith("_"):
            continue
        data["id"] = widget_id
        data["qml"] = str(qml_path.resolve())
        data["dir"] = str(path.resolve())
        # Settings.qml is optional. Its presence is what puts a gear on the
        # settings page and gives that widget a panel of its own.
        settings_path = path / "Settings.qml"
        if settings_path.is_file():
            data["settingsQml"] = str(settings_path.resolve())
        else:
            data.pop("settingsQml", None)
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
