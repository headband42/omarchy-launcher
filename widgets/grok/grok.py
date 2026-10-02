#!/usr/bin/env python3
"""Grok plan usage for the launcher tile. Stdlib only.

The limits on a signed-in Grok account come from the same call Grok Build's
`/usage` view makes:

    GET https://cli-chat-proxy.grok.com/v1/billing?format=credits
    Authorization: Bearer <session token>
    X-XAI-Token-Auth: xai-grok-cli

The token is the one `grok login` saved: the `key` of an entry in
`$GROK_HOME/auth.json`, else `~/.grok/auth.json`. That file is only ever
read. The token is never refreshed here, because a refresh rotates Grok's
refresh token behind its back, and it is never logged, printed, or cached.
Once it expires the tile says so, and Grok renews it the next time it runs.

`creditUsagePercent` is already a percentage of the weekly or monthly
allowance. A fresh window omits it; the tile still draws that window at 0%,
which is what `/usage` does. Grok Build and Grok Chat are separate bars only
when both report a percentage and those percentages add up to the allowance.
A product with no percentage is left out.

Money on this endpoint is USD cents, and a cent can arrive negative
(billing's sign). `{"val": 500}` is $5.00, `{"val": 1250}` is $12.50, and
`{}` is $0 because proto3 omits a zero. One dollar is 100 cents. The older
monthly ledger (`monthlyLimit` / `used`) is the same cents, used only when
the credits percentage is absent and the reply has no weekly or monthly
window. The reset is that window's end. The monthly ledger end is a calendar
month, so it is not the weekly reset.

The plan name comes from a second call, `GET {base}/settings`
(`subscription_tier_display`, else `subscription_tier`). That call failing
leaves the bars up under the name Grok. Nothing in this file reaches the
network on its own: `fetch` is injected, and the tests replace it.
"""

import json
import math
import os
import re
import sys
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

DEFAULT_BASE = "https://cli-chat-proxy.grok.com/v1"
TOKEN_HEADER = "xai-grok-cli"
USER_AGENT = "omarchy-launcher-grok"
MAX_BYTES = 200000

# Limits move slowly, so a slow poll is right; faster near a ceiling.
POLL_MS = 300000
POLL_BUSY_MS = 60000
NEAR_LIMIT = 80.0

# A product breakdown is the same pool as the allowance when the parts add
# back up. A percent point of slack covers a rounded reply.
COMPOSE_SLACK = 1.0

PRODUCTS = {
    "grokbuild": ("GROK BUILD", "of Grok Build"),
    "grokchat": ("GROK CHAT", "of Grok Chat"),
    "api": ("API", "of the API"),
}


def number(value):
    if value is None or isinstance(value, bool):
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def text(value, limit=200):
    return str(value or "").strip()[:limit]


def cents(value):
    """A `{val: cents}` amount. `{}` is zero. Anything else is `None`."""
    if isinstance(value, dict):
        if "val" not in value or value.get("val") is None:
            return 0
        value = value.get("val")
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        if not math.isfinite(value) or not value.is_integer():
            return None
        return int(value)
    if isinstance(value, str) and re.fullmatch(r"-?\d+", value.strip()):
        return int(value.strip())
    return None


def dollars(value):
    """Cents to a positive dollar amount. Billing's sign is not money owed."""
    amount = cents(value)
    return None if amount is None else abs(amount) / 100.0


def auth_path():
    """Where Grok keeps its sign-in."""
    folder = text(os.environ.get("GROK_HOME"), 400)
    if folder:
        return os.path.join(os.path.expanduser(folder), "auth.json")
    home = os.path.expanduser("~")
    if not home or home == "~":
        return ""
    return os.path.join(home, ".grok", "auth.json")


def epoch_ms(value):
    """An RFC 3339 stamp as epoch milliseconds. Extra fraction digits are cut
    to microseconds, which is as far as the clock parser reads."""
    stamp = text(value, 48)
    if not stamp:
        return None
    if stamp.endswith("Z"):
        stamp = stamp[:-1] + "+00:00"
    stamp = re.sub(r"(\.\d{6})\d+", r"\1", stamp, count=1)
    try:
        parsed = datetime.fromisoformat(stamp)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp() * 1000)


def _entry(data):
    """One saved sign-in, or None. The token is only returned, never shown."""
    if not isinstance(data, dict):
        return None
    token = str(data.get("key") or data.get("access_token") or "").strip()
    if not token or len(token) > 8192:
        return None
    user_id = text(data.get("user_id") or data.get("userId"), 64)
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", user_id or ""):
        user_id = ""
    return {"token": token, "expiresAt": epoch_ms(data.get("expires_at") or data.get("expiresAt")),
            "userId": user_id}


def credentials(path=None, now_ms=None):
    """The session token from Grok's saved sign-in, or None.

    None is a normal state: an API key has no plan limits to show. When more
    than one sign-in is saved, one that has not expired wins, and among those
    the one that lasts longest. The token is only returned, never shown.
    """
    candidate = path if path is not None else auth_path()
    if not candidate:
        return None
    try:
        with open(candidate, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    entries = []
    direct = _entry(data)
    if direct:
        entries.append(direct)
    if isinstance(data, dict):
        for value in data.values():
            entry = _entry(value)
            if entry and entry not in entries:
                entries.append(entry)
    if not entries:
        return None

    def still_good(entry):
        expires = entry["expiresAt"]
        if expires is None or now_ms is None:
            return True
        return expires > now_ms

    living = [entry for entry in entries if still_good(entry)]
    pool = living or entries
    pool.sort(key=lambda entry: entry["expiresAt"] if entry["expiresAt"] is not None else -1,
              reverse=True)
    return pool[0]


def base_url():
    """The CLI chat proxy, or a https override the user set for Grok itself."""
    raw = text(os.environ.get("GROK_CLI_CHAT_PROXY_BASE_URL"), 200) or DEFAULT_BASE
    parsed = urlparse(raw)
    if parsed.scheme != "https" or not parsed.hostname:
        return ""
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        return ""
    host = parsed.hostname
    if parsed.port:
        host = "%s:%d" % (host, parsed.port)
    path = (parsed.path or "").rstrip("/")
    return "https://" + host + path


def billing_url():
    base = base_url()
    return base + "/billing?format=credits" if base else ""


def settings_url():
    base = base_url()
    return base + "/settings" if base else ""


def allowed_url(url):
    """The credits call and the settings call, and nothing else."""
    target = text(url, 500)
    return target if target and target in (billing_url(), settings_url()) else ""


def fetch_json(url, token, user_id="", timeout=15, opener=urlopen):
    target = allowed_url(url)
    if not target:
        raise ValueError("Refusing an unexpected request")
    headers = {
        "Accept": "application/json",
        "Authorization": "Bearer " + token,
        "X-XAI-Token-Auth": TOKEN_HEADER,
        "User-Agent": USER_AGENT,
    }
    if user_id:
        headers["x-userid"] = user_id
    request = Request(target, headers=headers)
    with opener(request, timeout=timeout) as response:
        raw = response.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise OSError("Grok sent more than expected")
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("Unexpected payload")
    return payload


def period_kind(period_type):
    """week, month, or usage, from the proto enum name."""
    name = text(period_type, 80).upper()
    if "WEEKLY" in name:
        return "week"
    if "MONTHLY" in name:
        return "month"
    return "usage"


def period_words(kind):
    if kind == "week":
        return ("WEEK", "of this week")
    if kind == "month":
        return ("MONTH", "of this month")
    return ("USAGE", "of the allowance")


def canonical_product(name):
    """GrokBuild and PRODUCT_GROK_BUILD are the same bar."""
    raw = re.sub(r"[^a-z0-9]+", "", text(name, 80).lower())
    if raw.startswith("product"):
        raw = raw[len("product"):]
    if raw in ("grokbuild", "build"):
        return "grokbuild"
    if raw in ("grokchat", "chat"):
        return "grokchat"
    if raw in ("grokapi", "api"):
        return "api"
    return raw


def meter(meter_id, label, caption, percent, resets, used=None, limit=None):
    return {
        "id": meter_id,
        "label": label,
        "caption": caption,
        "percent": percent,
        "used": used,
        "limit": limit,
        "resetsAtMs": resets,
        "over": percent >= 100.0,
        "near": percent >= NEAR_LIMIT,
    }


def product_meters(raw, resets):
    """Products that reported a percentage, in the order the reply gave them."""
    if not isinstance(raw, list):
        return []
    meters = []
    seen = set()
    for item in raw:
        if not isinstance(item, dict):
            continue
        percent = number(item.get("usagePercent"))
        if percent is None:
            continue
        canon = canonical_product(item.get("product"))
        if not canon or canon in seen:
            continue
        seen.add(canon)
        label, caption = PRODUCTS.get(canon, (canon.upper(), "of " + canon))
        meters.append(meter(canon, label, caption, percent, resets))
    return meters


def composing(products, percent):
    """True when the product bars are the allowance split apart, not a second copy of it."""
    if len(products) < 2 or percent is None:
        return False
    if not any(item["percent"] > 0 for item in products):
        return False
    total = sum(item["percent"] for item in products)
    return abs(total - percent) <= COMPOSE_SLACK


def ondemand_meter(config, resets):
    """Pay-as-you-go, once a spending cap is set. The cap is cents."""
    cap = cents(config.get("onDemandCap"))
    used = cents(config.get("onDemandUsed"))
    if cap is None or abs(cap) <= 0:
        return None
    spent = 0 if used is None else abs(used)
    percent = spent / abs(cap) * 100.0
    return meter("ondemand", "PAY AS YOU GO", "of the spending cap", percent, resets,
                 dollars(used if used is not None else 0), dollars(cap))


def legacy_meter(config, resets):
    """The older monthly ledger, in cents, when the credits percentage is absent."""
    limit = cents(config.get("monthlyLimit"))
    used = cents(config.get("used"))
    if limit is None or abs(limit) <= 0 or used is None:
        return None
    percent = abs(used) / abs(limit) * 100.0
    return meter("period", "MONTH", "of this month", percent, resets, dollars(used), dollars(limit))


# The display name is the one /usage shows. The other field is a fallback,
# and on some accounts it is a tier number rather than a name.
PLAN_KEYS = ("subscription_tier_display", "subscriptionTierDisplay",
             "subscription_tier", "subscriptionTier")


def _plan_text(value):
    name = text(value, 80)
    if name and any(ch.isalpha() for ch in name):
        return name
    return ""


def _plan_blobs(source):
    """The object itself, plus a nested settings or credits config."""
    if not isinstance(source, dict):
        return []
    blobs = [source]
    for key in ("settings", "config"):
        nested = source.get(key)
        if isinstance(nested, dict) and nested not in blobs:
            blobs.append(nested)
    return blobs


def plan_name(settings, billing):
    """X Premium+, SuperGrok, and so on. The allowance still draws without it.

    The settings reply wins over the billing reply. Inside either, the
    display name wins over the raw tier.
    """
    for source in (settings, billing):
        for blob in _plan_blobs(source):
            for key in PLAN_KEYS:
                name = _plan_text(blob.get(key))
                if name:
                    return name
    return "Grok"


def credits_left(config):
    """Prepaid balance in dollars, or None when there is nothing bought."""
    amount = cents(config.get("prepaidBalance"))
    if amount is None or abs(amount) <= 0:
        return None
    return abs(amount) / 100.0


def parse_billing(payload, plan="Grok"):
    """The credits reply as a tile payload."""
    if not isinstance(payload, dict):
        return error_view("Grok sent an unexpected payload")
    config = payload.get("config") if isinstance(payload.get("config"), dict) else None
    if config is None and ("creditUsagePercent" in payload or "currentPeriod" in payload
                           or "monthlyLimit" in payload):
        config = payload
    if not isinstance(config, dict):
        return error_view("Grok sent an unexpected payload", "error", plan)

    period = config.get("currentPeriod") if isinstance(config.get("currentPeriod"), dict) else {}
    kind = period_kind(period.get("type"))
    resets = epoch_ms(period.get("end")) or epoch_ms(config.get("billingPeriodEnd"))
    label, caption = period_words(kind if period else "usage")
    percent = number(config.get("creditUsagePercent"))

    meters = []
    if percent is None and period and kind in ("week", "month"):
        # A fresh window names itself and omits the percentage. It is 0%, not
        # an account with no limit.
        percent = 0.0
        label, caption = period_words(kind)
    if percent is not None:
        if not period:
            label, caption = period_words("usage")
        meters.append(meter("period", label, caption, percent, resets))
        products = product_meters(config.get("productUsage"), resets)
        if composing(products, percent):
            meters.extend(products)
    else:
        legacy = legacy_meter(config, resets)
        if legacy:
            meters.append(legacy)

    extra = ondemand_meter(config, resets)
    if extra:
        meters.append(extra)
    if not meters:
        return error_view("This sign-in has no usage limits", "plan", plan)

    return {
        "ok": True,
        "reason": "",
        "plan": plan or "Grok",
        "credits": credits_left(config),
        "meters": meters,
        "error": None,
        "pollMs": POLL_BUSY_MS if any(item["near"] for item in meters) else POLL_MS,
    }


def error_view(message="Grok usage is unavailable", reason="error", plan=""):
    """What the tile draws instead of bars. `reason` picks the advice:
    signin (no Grok sign-in), expired, plan (no limits), or error."""
    return {
        "ok": False,
        "reason": reason,
        "plan": plan,
        "credits": None,
        "meters": [],
        "error": text(message, 160) or "Grok usage is unavailable",
        "pollMs": POLL_MS,
    }


def collect(fetch=fetch_json, path=None, now_ms=None):
    # The clock has to be known before the sign-in is chosen, or an expired
    # stamp outranks a session that is still good.
    now_ms = now_ms if now_ms is not None else int(datetime.now(timezone.utc).timestamp() * 1000)
    account = credentials(path, now_ms)
    if not account:
        return error_view("No Grok sign-in found", "signin")
    if account["expiresAt"] and account["expiresAt"] <= now_ms:
        return error_view("Grok's sign-in has expired", "expired")
    target = billing_url()
    if not target:
        return error_view("Grok's billing address is not one this tile can call")
    try:
        billing = fetch(target, account["token"], account["userId"])
    except HTTPError as error:
        if error.code in (401, 403):
            return error_view("Grok's sign-in has expired", "expired")
        if error.code == 429:
            return error_view("Grok asked the tile to slow down")
        return error_view("Grok answered %d" % error.code)
    except Exception as error:
        return error_view(text(error, 160) or "Grok usage is unavailable")

    # The plan name rides on the settings call. A failure here keeps the bars.
    settings = None
    try:
        settings = fetch(settings_url(), account["token"], account["userId"])
    except Exception:
        settings = None
    view = parse_billing(billing, plan_name(settings, billing))
    return view


def cache_path():
    root = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(root, "ande.launcher", "grok.json")


def write_cache(payload, path=None):
    """Keep the last good reply for the next launcher session. Best effort.
    The payload is usage only: the token never reaches it."""
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
        payload = error_view(text(error, 160) or "Grok usage is unavailable")
    payload["savedAt"] = int(datetime.now(timezone.utc).timestamp() * 1000)
    if payload.get("ok"):
        write_cache(payload, cache)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
