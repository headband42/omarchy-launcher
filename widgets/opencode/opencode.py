"""OpenCode Go subscription model.

OpenCode Go is a subscription with three usage blocks per account:

    fiveHour   20% of the monthly limit
    week       50%
    month      100%

The console serves all of them from one call, and that is the only call this
widget makes:

    GET https://opencode.ai/console/api/go/status

with the console's own access token and the active organization id. Both come
out of OpenCode's local database, which the CLI writes:

    $XDG_DATA_HOME/opencode/opencode.db   (default ~/.local/share/opencode)
    tables: account (access_token), account_state (active_org_id,
    active_account_id)

The database is opened read-only and the token is never logged, printed, or
written anywhere. Money arrives as micro-cents, so $12 is "1200000000", and
is converted to plain dollars here.

Nothing in this file reaches the network on its own: `fetch` is injected, so
the tests replace it and never touch the console.

Times go out as epoch milliseconds. The tile formats them against a clock it
keeps ticking, so a countdown stays right between polls. A good reply is
also saved to the cache (usage only, never the token), and the tile draws
that while the first poll of a launcher session is out.
"""

import json
import math
import os
import sqlite3
import sys
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen

CONSOLE = "https://opencode.ai/console"
STATUS_URL = CONSOLE + "/api/go/status"
ALLOWED_HOSTS = ("opencode.ai", "www.opencode.ai")
USER_AGENT = "omarchy-launcher-opencode"
MAX_BYTES = 400000

# A micro-cent is a hundred-millionth of a dollar, so a dollar is this many
# of them. The console's own numbers pin it: a $12 block arrives as
# "1200000000", and $60 as "6000000000".
MICRO = 100000000.0

# The three blocks, in the order a person reads them: soonest reset first.
METER_ORDER = ("fiveHour", "week", "month")
METER_LABELS = {
    "fiveHour": "5-HOUR",
    "week": "WEEK",
    "month": "MONTH",
}

# A block changes slowly, so a slow poll is right. One minute when something
# is close to its ceiling, so the last of the way is watchable.
POLL_MS = 300000
POLL_BUSY_MS = 60000
NEAR_LIMIT = 0.8


def number(value, default=None):
    if isinstance(value, bool):
        return default
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    return result if math.isfinite(result) else default


def text(value, limit=200):
    result = str(value or "").strip()
    return result[:limit]


def db_candidates():
    """Where OpenCode's database might be, in the order OpenCode resolves it.

    `OPENCODE_DB` and `XDG_DATA_HOME` are the two the CLI itself honors, so
    they come first. The default is the XDG data directory.
    """
    paths = []
    direct = text(os.environ.get("OPENCODE_DB"), 400)
    if direct:
        paths.append(direct)
    data_home = text(os.environ.get("XDG_DATA_HOME"), 400)
    if data_home:
        paths.append(os.path.join(data_home, "opencode", "opencode.db"))
    home = os.path.expanduser("~")
    if home and home != "~":
        paths.append(os.path.join(home, ".local", "share", "opencode", "opencode.db"))
    unique = []
    for path in paths:
        if path and path not in unique:
            unique.append(path)
    return unique


def credentials(path=None):
    """The console token and active organization, read from OpenCode's db.

    Returns None when there is no usable account, which is a normal state:
    OpenCode works signed out. The token is only ever returned, never shown.
    """
    candidates = [path] if path else db_candidates()
    for candidate in candidates:
        if not candidate or not os.path.isfile(candidate):
            continue
        try:
            # Read-only, so a running OpenCode is never disturbed and the
            # database can never be written by a widget. The path is quoted
            # because it travels inside a URI, where a "?" or "#" of its own
            # would otherwise start a query or a fragment.
            connection = sqlite3.connect("file:" + quote(candidate) + "?mode=ro", uri=True)
        except sqlite3.Error:
            continue
        try:
            # The two tables are read separately rather than joined, so more
            # than one saved account cannot multiply the rows. The token is
            # the active account's, so it belongs to the same account as the
            # org; the latest update is only the fallback.
            state = connection.execute(
                "select active_org_id from account_state limit 1").fetchone()
            try:
                active = connection.execute(
                    "select active_account_id from account_state limit 1").fetchone()
            except sqlite3.Error:
                active = None
            row = None
            if active and active[0]:
                row = connection.execute(
                    "select access_token from account where id = ? and access_token is not null "
                    "and access_token != '' limit 1", (text(active[0], 128),)).fetchone()
            if not row:
                row = connection.execute(
                    "select access_token from account where access_token is not null "
                    "and access_token != '' order by time_updated desc limit 1").fetchone()
        except sqlite3.Error:
            row = state = None
        finally:
            connection.close()
        if not row:
            continue
        # Secrets are never displayed, so they are not trimmed to a display
        # width: only stripped, with a sanity cap far above any real token.
        token = str(row[0] or "").strip()
        org = text(state[0], 256) if state else ""
        if token and len(token) <= 8192 and org:
            return {"token": token, "org": org, "db": candidate}
    return None


def allowed_url(url):
    """Only the one console endpoint, over https, rebuilt without extras."""
    parsed = urlparse(text(url, 500))
    if parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS:
        return ""
    if text(parsed.path, 200) != "/console/api/go/status":
        return ""
    return "https://" + parsed.hostname + "/console/api/go/status"


def fetch_json(url, token, org, timeout=15, opener=urlopen):
    """Read the Go status. urllib is fine here; opencode.ai does not block it."""
    target = allowed_url(url)
    if not target:
        raise ValueError("Refusing an unexpected request")
    request = Request(target, headers={
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
        "Authorization": "Bearer " + token,
        "x-org-id": org,
    })
    with opener(request, timeout=timeout) as response:
        raw = response.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise OSError("OpenCode sent more than expected")
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("Unexpected payload")
    return payload


def parse_stamp(value):
    stamp = text(value, 40)
    if not stamp:
        return None
    if stamp.endswith("Z"):
        stamp = stamp[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(stamp)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def epoch_ms(value):
    """An ISO stamp as epoch milliseconds, or None."""
    parsed = parse_stamp(value)
    return int(parsed.timestamp() * 1000) if parsed else None


def dollars(micro_cents):
    """Micro-cents to plain dollars. `None` stays `None`."""
    value = number(micro_cents)
    return None if value is None else value / MICRO


def percent_of(meter):
    """How much of the block is used, as a percentage.

    A block can go over its limit, so this is not clamped: 100% is the
    ceiling on the bar, not on the number.
    """
    used = number(meter.get("usedMicroCents"))
    limit = number(meter.get("limitMicroCents"))
    if used is None or not limit or limit <= 0:
        return None
    return used / limit * 100.0


def parse_meter(meter_id, raw):
    """One usage block, ready for the tile."""
    if not isinstance(raw, dict):
        return None
    used = dollars(raw.get("usedMicroCents"))
    limit = dollars(raw.get("limitMicroCents"))
    if used is None and limit is None:
        # Nothing to draw. A block that is absent and a block that is empty
        # would otherwise look the same on the tile.
        return None
    percent = percent_of(raw)
    resets = epoch_ms(raw.get("resetsAt"))
    return {
        "id": meter_id,
        "label": METER_LABELS.get(meter_id, meter_id),
        "used": used,
        "limit": limit,
        "percent": percent,
        "resetsAtMs": resets,
        "startsAtMs": epoch_ms(raw.get("startsAt")),
        # A rolling block with no window yet starts with the next request.
        "idle": resets is None,
        "over": bool(percent is not None and limit and used is not None and used > limit),
        "near": bool(percent is not None and percent >= NEAR_LIMIT * 100),
    }


def plan_name(product, renewal):
    """Go or Go Plus, in the words the console uses."""
    for value in (product, renewal):
        if not value:
            continue
        if "plus" in str(value).lower():
            return "OpenCode Go Plus"
    return "OpenCode Go"


def parse_status(payload):
    """The console's reply as a tile payload."""
    if not isinstance(payload, dict):
        return error_view("OpenCode sent an unexpected payload")
    access = payload.get("access")
    if not isinstance(access, dict):
        return error_view("No Go subscription on this account", "plan")

    meters_raw = access.get("meters")
    meters_raw = meters_raw if isinstance(meters_raw, dict) else {}
    meters = []
    for meter_id in METER_ORDER:
        meter = parse_meter(meter_id, meters_raw.get(meter_id))
        if meter:
            meters.append(meter)
    # A block the console did not send is dropped rather than shown as zero,
    # because zero used and no block at all are different things.
    for meter_id in sorted(meters_raw):
        if meter_id in METER_ORDER:
            continue
        meter = parse_meter(meter_id, meters_raw[meter_id])
        if meter:
            meters.append(meter)

    if not meters:
        return error_view("No Go usage blocks on this account", "plan")

    upgrade = payload.get("upgradePrice") if isinstance(payload.get("upgradePrice"), dict) else {}
    product = text(payload.get("product"), 20)
    canceling = bool(access.get("cancelAtPeriodEnd") or payload.get("cancelAtPeriodEnd"))

    return {
        "ok": True,
        "reason": "",
        "product": product,
        "plan": plan_name(product, text(payload.get("renewalProduct"), 20)),
        "active": not canceling,
        "canceling": canceling,
        "renewalPending": bool(payload.get("renewalPending")),
        "useBalance": bool(payload.get("useBalance")),
        "endsAtMs": epoch_ms(access.get("endsAt")),
        "startsAtMs": epoch_ms(access.get("startsAt")),
        "currency": text(payload.get("renewalCurrency"), 8).upper() or "USD",
        "upgrade": dollars(upgrade.get("amountMicroCents")),
        "meters": meters,
        "error": None,
        # A block changes slowly, so a slow poll is right. One minute when
        # something is close to its ceiling, so the last of the way is watchable.
        "pollMs": POLL_BUSY_MS if any(m["near"] for m in meters) else POLL_MS,
    }


def error_view(message="OpenCode Go usage is unavailable", reason="error"):
    """A reply the tile draws instead of bars. `reason` picks the advice:
    signin (no account), expired, plan (no Go blocks), or error."""
    return {
        "ok": False,
        "reason": reason,
        "product": "",
        "plan": "",
        "active": False,
        "canceling": False,
        "renewalPending": False,
        "useBalance": False,
        "endsAtMs": None,
        "startsAtMs": None,
        "currency": "USD",
        "upgrade": None,
        "meters": [],
        "error": text(message, 160) or "OpenCode Go usage is unavailable",
        "pollMs": POLL_MS,
    }


def signed_out(error):
    code = getattr(error, "code", None)
    if code in (401, 403):
        return True
    lowered = text(error, 160).lower()
    return any(word in lowered for word in ("401", "403", "unauthorized", "forbidden"))


def collect(fetch=fetch_json, path=None):
    """Read the console and turn the reply into a tile payload.

    Not being signed in is a state the tile draws, not a crash: OpenCode works
    signed out, and the tile says what is missing.
    """
    account = credentials(path)
    if not account:
        return error_view("No OpenCode console account found", "signin")
    try:
        payload = fetch(STATUS_URL, account["token"], account["org"])
    except Exception as error:
        if signed_out(error):
            return error_view("Console sign-in has expired", "expired")
        if isinstance(error, HTTPError):
            return error_view("OpenCode answered %d" % error.code)
        return error_view(text(error, 160) or "OpenCode Go usage is unavailable")
    return parse_status(payload)


def cache_path():
    root = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(root, "ande.launcher", "opencode.json")


def write_cache(payload, path=None):
    """Keep the last good reply for the next launcher session. Best effort."""
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
        payload = error_view(text(error, 160) or "OpenCode Go usage is unavailable")
    payload["savedAt"] = int(datetime.now(timezone.utc).timestamp() * 1000)
    if payload.get("ok"):
        write_cache(payload, cache)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
