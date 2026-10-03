#!/usr/bin/env python3
"""Muse subscription quota for the launcher tile. Stdlib only.

The numbers on a Muse subscription come from one call:

    POST https://api.meta.ai/muse-code/key
    Authorization: Bearer <Meta account token>

The token is the one `muse login` saved: `providers.meta.access_token` in
`$XDG_CONFIG_HOME/muse/auth.json`, else `~/.config/muse/auth.json`. That
file is only ever read. The token is never printed, logged, or cached.

The call mints a Model API key as a side effect; the tile drops it and
keeps only `subs_usage`. Minting does not invalidate the stored key (the
old one still answers afterwards), so polling it is safe. The minted key
is never printed, logged, or cached either.

The reply's quota shape is two blocks with integer percentages:

    window  the current window: used_percent, window_duration_mins (300 is
            the 5-hour block), and resets_at in epoch SECONDS
    weekly  the rolling week: used_percent and resets_at, same seconds

Percentages may exceed 100 past the quota. The plan name is
`subs_tier_name` without its "Muse Code " prefix. Nothing in this file
reaches the network on its own: `fetch` is injected, and the tests
replace it.
"""

import json
import os
import sys
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.request import Request, urlopen

MINT_URL = "https://api.meta.ai/muse-code/key"
USER_AGENT = "omarchy-launcher-muse"
MAX_BYTES = 100000

# Quota moves slowly, so a slow poll is right; faster near a ceiling.
POLL_MS = 300000
POLL_BUSY_MS = 60000
NEAR_LIMIT = 80.0


def number(value):
    if value is None or isinstance(value, bool):
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    if result != result or result in (float("inf"), float("-inf")):
        return None
    return result


def text(value, limit=200):
    return str(value or "").strip()[:limit]


def auth_paths():
    """Where Muse keeps its sign-in, in the order it looks."""
    paths = []
    folder = text(os.environ.get("XDG_CONFIG_HOME"), 400)
    if folder:
        paths.append(os.path.join(os.path.expanduser(folder), "muse", "auth.json"))
    home = os.path.expanduser("~")
    if home and home != "~":
        paths.append(os.path.join(home, ".config", "muse", "auth.json"))
    unique = []
    for path in paths:
        if path not in unique:
            unique.append(path)
    return unique


def credentials(path=None):
    """The Meta account token from Muse's saved sign-in, or None.

    None is a normal state: Muse also runs on a bare API key, which has
    no subscription quota to show. The token is only returned, never shown.
    """
    for candidate in ([path] if path else auth_paths()):
        try:
            with open(candidate, encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            continue
        providers = data.get("providers") if isinstance(data, dict) else None
        meta = providers.get("meta") if isinstance(providers, dict) else None
        if not isinstance(meta, dict):
            continue
        token = str(meta.get("access_token") or "").strip()
        if not token or len(token) > 8192:
            continue
        return {"token": token}
    return None


def fetch_json(url, token, timeout=15, opener=urlopen):
    if url != MINT_URL:
        raise ValueError("Refusing an unexpected request")
    request = Request(url, data=b"{}", headers={
        "Accept": "application/json",
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT,
    })
    with opener(request, timeout=timeout) as response:
        raw = response.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise OSError("Meta sent more than expected")
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("Unexpected payload")
    return payload


def window_label(minutes):
    """300 -> "5-HOUR WINDOW". Anything else reads as itself."""
    if minutes is None:
        return "WINDOW"
    whole = int(minutes)
    if whole > 0 and whole % 60 == 0:
        hours = whole // 60
        return "1-HOUR WINDOW" if hours == 1 else "%d-HOUR WINDOW" % hours
    if whole > 0:
        return "%d-MIN WINDOW" % whole
    return "WINDOW"


def parse_block(key, raw):
    """One quota block, ready for the tile, or None when unusable."""
    if not isinstance(raw, dict):
        return None
    percent = number(raw.get("used_percent"))
    if percent is None:
        return None
    resets = number(raw.get("resets_at"))
    resets_ms = int(resets * 1000) if resets else None
    if key == "window":
        minutes = number(raw.get("window_duration_mins"))
        label = window_label(int(minutes) if minutes else None)
        caption = "of this window"
    else:
        label = "WEEK"
        caption = "of this week"
    return {
        "id": key,
        "label": label,
        "caption": caption,
        "percent": percent,
        "resetsAtMs": resets_ms,
        # No window yet: it opens with the next message.
        "idle": resets_ms is None,
        "over": percent >= 100.0,
        "near": percent >= NEAR_LIMIT,
    }


def plan_name(raw):
    """subs_tier_name without its "Muse Code " prefix."""
    name = text(raw, 80)
    prefix = "Muse Code "
    if name.startswith(prefix):
        name = name[len(prefix):]
    return name or "Muse"


def parse_usage(payload):
    if not isinstance(payload, dict):
        return error_view("Meta sent an unexpected payload")
    plan = plan_name(payload.get("subs_tier_name"))
    if not payload.get("is_subs_active"):
        if payload.get("require_payment"):
            return error_view("Muse needs a payment method", "plan", plan)
        return error_view("No active Muse subscription", "plan", plan)
    usage = payload.get("subs_usage")
    if not isinstance(usage, dict):
        return error_view("Meta sent no subscription usage", "error", plan)
    meters = []
    for key in ("window", "weekly"):
        block = parse_block(key, usage.get(key))
        if block:
            meters.append(block)
    if not meters:
        return error_view("Meta sent no usable quota", "error", plan)
    return {
        "ok": True,
        "reason": "",
        "plan": plan,
        "meters": meters,
        "error": None,
        "pollMs": POLL_BUSY_MS if any(block["near"] for block in meters) else POLL_MS,
    }


def error_view(message="Muse usage is unavailable", reason="error", plan=""):
    """What the tile draws instead of bars. `reason` picks the advice:
    signin (no Muse sign-in), expired, plan (no subscription), or error."""
    return {
        "ok": False,
        "reason": reason,
        "plan": plan,
        "meters": [],
        "error": text(message, 160) or "Muse usage is unavailable",
        "pollMs": POLL_MS,
    }


def collect(fetch=fetch_json, path=None):
    account = credentials(path)
    if not account:
        return error_view("No Muse sign-in found", "signin")
    try:
        payload = fetch(MINT_URL, account["token"])
    except HTTPError as error:
        if error.code in (401, 403):
            return error_view("Muse's sign-in has expired", "expired")
        if error.code == 429:
            return error_view("Meta asked the tile to slow down")
        return error_view("Meta answered %d" % error.code)
    except Exception as error:
        return error_view(text(error, 160) or "Muse usage is unavailable")
    return parse_usage(payload)


def cache_path():
    root = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(root, "ande.launcher", "muse.json")


def write_cache(payload, path=None):
    """Keep the last good reply for the next launcher session. Best effort.
    The payload is quota only: neither token reaches it."""
    target = path or cache_path()
    try:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        temporary = "%s.%d.tmp" % (target, os.getpid())
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"))
        os.replace(temporary, target)
    except OSError:
        pass


def main(argv, collector=None, cache=None):
    try:
        payload = (collector or collect)()
    except Exception as error:
        payload = error_view(text(error, 160) or "Muse usage is unavailable")
    payload["savedAt"] = int(datetime.now(timezone.utc).timestamp() * 1000)
    if payload.get("ok"):
        write_cache(payload, cache)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
