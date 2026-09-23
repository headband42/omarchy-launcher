#!/usr/bin/env python3
"""Time zone catalog and clock snapshots for the time zones widget.

    zones.py                 JSON list of {id, label, region}
    zones.py --local         JSON object for the system zone
    zones.py --clocks [ids]  JSON {local, zones} with current offsets
"""

import json
import sys
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

MAX_ZONES = 3
# zone.tab is the city list: one row per place you can choose.
# zone1970.tab is smaller on purpose. It drops cities whose clocks have
# matched a neighbor since 1970, so Stockholm, Oslo, and Amsterdam are absent.
ZONE_TAB = Path("/usr/share/zoneinfo/zone.tab")
ZONE1970_TAB = Path("/usr/share/zoneinfo/zone1970.tab")


def city_region(zone_id: str) -> tuple[str, str]:
    parts = [part.replace("_", " ") for part in str(zone_id or "").split("/") if part]
    if len(parts) >= 2:
        return parts[-1], " · ".join(parts[:-1])
    if parts:
        return parts[0], ""
    return str(zone_id or ""), ""


def offset_minutes_at(zone_id: str, when: datetime) -> int:
    if when.tzinfo is None:
        when = when.replace(tzinfo=ZoneInfo("UTC"))
    local = when.astimezone(ZoneInfo(zone_id))
    offset = local.utcoffset() or timedelta(0)
    return int(offset.total_seconds() // 60)


def local_zone_id() -> str:
    link = Path("/etc/localtime")
    try:
        target = str(link.resolve())
    except OSError:
        return ""
    marker = "/zoneinfo/"
    index = target.find(marker)
    if index < 0:
        return ""
    return target[index + len(marker):]


def zone_snapshot(zone_id: str, when: datetime | None = None) -> dict | None:
    moment = when or datetime.now(ZoneInfo("UTC"))
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=ZoneInfo("UTC"))
    try:
        local = moment.astimezone(ZoneInfo(zone_id))
    except (ZoneInfoNotFoundError, ValueError, OSError):
        return None
    city, region = city_region(zone_id)
    offset = local.utcoffset() or timedelta(0)
    return {
        "id": zone_id,
        "label": city,
        "region": region,
        "abbr": local.tzname() or "",
        "offsetMinutes": int(offset.total_seconds() // 60),
    }


def local_snapshot(when: datetime | None = None) -> dict:
    zone_id = local_zone_id()
    snap = zone_snapshot(zone_id, when) if zone_id else None
    if snap:
        return snap
    moment = when or datetime.now().astimezone()
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=ZoneInfo("UTC"))
    moment = moment.astimezone()
    offset = moment.utcoffset() or timedelta(0)
    return {
        "id": zone_id,
        "label": "Local",
        "region": "",
        "abbr": moment.tzname() or "",
        "offsetMinutes": int(offset.total_seconds() // 60),
    }


def tab_zone_ids(path: Path) -> list[str]:
    if not path.is_file():
        return []
    ids = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) >= 3 and cols[2].strip():
            ids.append(cols[2].strip())
    return ids


def list_zones() -> list[dict]:
    zones: list[dict] = []
    seen: set[str] = set()

    def add(zone_id: str) -> None:
        zone_id = str(zone_id or "").strip()
        if not zone_id or zone_id in seen:
            return
        try:
            ZoneInfo(zone_id)
        except (ZoneInfoNotFoundError, ValueError, OSError):
            return
        seen.add(zone_id)
        city, region = city_region(zone_id)
        try:
            offset = offset_minutes_at(zone_id, datetime.now(ZoneInfo("UTC")))
        except (ZoneInfoNotFoundError, ValueError, OSError):
            return
        zones.append({
            "id": zone_id,
            "label": city,
            "region": region,
            "offsetMinutes": offset,
        })

    ids = tab_zone_ids(ZONE_TAB) or tab_zone_ids(ZONE1970_TAB)
    for zone_id in ids:
        add(zone_id)
    add("UTC")
    zones.sort(key=lambda zone: (zone["label"].casefold(), zone["id"]))
    return zones


def clocks(zone_ids: list[str], when: datetime | None = None) -> dict:
    zones = []
    seen: set[str] = set()
    for raw in zone_ids:
        zone_id = str(raw or "").strip()
        if not zone_id or zone_id in seen:
            continue
        seen.add(zone_id)
        if len(zones) >= MAX_ZONES:
            break
        snap = zone_snapshot(zone_id, when)
        if snap:
            zones.append(snap)
    return {"local": local_snapshot(when), "zones": zones}


def main(argv: list[str]) -> None:
    if len(argv) >= 2 and argv[1] == "--local":
        payload = local_snapshot()
    elif len(argv) >= 2 and argv[1] == "--clocks":
        payload = clocks(argv[2:])
    else:
        payload = list_zones()
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main(sys.argv)
