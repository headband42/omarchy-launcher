#!/usr/bin/env python3
"""Claude plan usage for the launcher tile. Stdlib only.

The limits on a Claude subscription come from one call:

    GET https://api.anthropic.com/api/oauth/usage
    Authorization: Bearer <access token>
    anthropic-beta: oauth-2025-04-20

The token is the one Claude Code saved when you signed in with your Claude
account: `claudeAiOauth.accessToken` in `$CLAUDE_CONFIG_DIR/.credentials.json`,
else `~/.claude/.credentials.json`. That file is only ever read. The token is
never refreshed here, because a refresh rotates Claude Code's refresh token
behind its back, and it is never logged, printed, or cached. Once it expires
the tile says so, and Claude Code renews it the next time it runs.

The reply names each limit with its utilization, a percentage, and when it
resets:

    five_hour         the current session window
    seven_day         the week, every model
    seven_day_opus    the week, Opus only
    seven_day_sonnet  the week, Sonnet only
    extra_usage       pay-as-you-go use past the plan, when it is turned on

Any other limit is shown as well once some of it is used, so a new one appears
without a change here. At 0% it is left out: the reply carries internal
codenames (`iguana_necktie`) that mean nothing on a tile until they are used. Nothing in this file reaches the network on its
own: `fetch` is injected, and the tests replace it.
"""

import json
import math
import os
import sys
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.request import Request, urlopen

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
BETA = "oauth-2025-04-20"
USER_AGENT = "omarchy-launcher-claude"
MAX_BYTES = 200000

# Known limits, in the order a person reads them, with the tile's label and
# the words under the big number when that limit is the fullest.
LIMITS = (
    ("five_hour", "5-HOUR SESSION", "of this session"),
    ("seven_day", "WEEK · ALL MODELS", "of this week"),
    ("seven_day_opus", "WEEK · OPUS", "of this week’s Opus"),
    ("seven_day_sonnet", "WEEK · SONNET", "of this week’s Sonnet"),
    ("extra_usage", "EXTRA USAGE", "of extra usage"),
)
KNOWN = {key: (label, caption) for key, label, caption in LIMITS}

# Limits move slowly, so a slow poll is right; faster near a ceiling.
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
    return result if math.isfinite(result) else None


def text(value, limit=200):
    return str(value or "").strip()[:limit]


def credential_paths():
    """Where Claude Code keeps its sign-in, in the order it looks."""
    paths = []
    folder = text(os.environ.get("CLAUDE_CONFIG_DIR"), 400)
    if folder:
        paths.append(os.path.join(os.path.expanduser(folder), ".credentials.json"))
    home = os.path.expanduser("~")
    if home and home != "~":
        paths.append(os.path.join(home, ".claude", ".credentials.json"))
    unique = []
    for path in paths:
        if path not in unique:
            unique.append(path)
    return unique


def credentials(path=None):
    """The OAuth token and plan from Claude Code's saved sign-in, or None.

    None is a normal state: Claude Code also runs on an API key, which has
    no plan limits to show. The token is only returned, never shown.
    """
    for candidate in ([path] if path else credential_paths()):
        try:
            with open(candidate, encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            continue
        oauth = data.get("claudeAiOauth") if isinstance(data, dict) else None
        if not isinstance(oauth, dict):
            continue
        token = str(oauth.get("accessToken") or "").strip()
        if not token or len(token) > 8192:
            continue
        expires = number(oauth.get("expiresAt"))
        return {
            "token": token,
            "expiresAt": int(expires) if expires else None,
            "subscription": text(oauth.get("subscriptionType"), 40).lower(),
            "tier": text(oauth.get("rateLimitTier"), 80).lower(),
        }
    return None


def plan_name(subscription, tier):
    """Claude Max 20x, Claude Pro, and so on, from what the sign-in says."""
    for size in ("20x", "5x"):
        if "max_" + size in tier or "max-" + size in tier:
            return "Claude Max " + size
    names = {"max": "Claude Max", "pro": "Claude Pro", "team": "Claude Team",
             "enterprise": "Claude Enterprise"}
    return names.get(subscription, "Claude")


def fetch_json(url, token, timeout=15, opener=urlopen):
    if url != USAGE_URL:
        raise ValueError("Refusing an unexpected request")
    request = Request(url, headers={
        "Accept": "application/json",
        "Authorization": "Bearer " + token,
        "anthropic-beta": BETA,
        "User-Agent": USER_AGENT,
    })
    with opener(request, timeout=timeout) as response:
        raw = response.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise OSError("Anthropic sent more than expected")
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("Unexpected payload")
    return payload


def epoch_ms(value):
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
    return int(parsed.timestamp() * 1000)


def words(key):
    """A label for a limit this file has not heard of: seven_day_haiku -> WEEK · HAIKU."""
    for prefix, name in (("seven_day", "WEEK"), ("five_hour", "5-HOUR")):
        if key == prefix:
            return name
        if key.startswith(prefix + "_"):
            return name + " · " + key[len(prefix) + 1:].replace("_", " ").upper()
    return key.replace("_", " ").upper()


def parse_limit(key, raw):
    """One limit, ready for the tile, or None when there is nothing to draw."""
    if not isinstance(raw, dict):
        return None
    if key == "extra_usage" and not raw.get("is_enabled"):
        return None
    percent = number(raw.get("utilization"))
    if percent is None:
        return None
    label, caption = KNOWN.get(key, (words(key), "of " + words(key).lower()))
    resets = epoch_ms(raw.get("resets_at"))
    return {
        "id": key,
        "label": label,
        "caption": caption,
        "percent": percent,
        "resetsAtMs": resets,
        # No window yet: it opens with the next message.
        "idle": resets is None and key != "extra_usage",
        "over": percent >= 100.0,
        "near": percent >= NEAR_LIMIT,
    }


def parse_usage(payload, account=None):
    if not isinstance(payload, dict):
        return error_view("Anthropic sent an unexpected payload")
    account = account or {}
    limits = []
    for key, _label, _caption in LIMITS:
        limit = parse_limit(key, payload.get(key))
        if limit:
            limits.append(limit)
    for key in sorted(payload):
        if key in KNOWN:
            continue
        limit = parse_limit(key, payload.get(key))
        if limit and limit["percent"] > 0:
            limits.append(limit)
    if not limits:
        return error_view("This sign-in has no plan limits", "plan")
    return {
        "ok": True,
        "reason": "",
        "plan": plan_name(account.get("subscription", ""), account.get("tier", "")),
        "meters": limits,
        "error": None,
        "pollMs": POLL_BUSY_MS if any(limit["near"] for limit in limits) else POLL_MS,
    }


def error_view(message="Claude usage is unavailable", reason="error", plan=""):
    """What the tile draws instead of bars. `reason` picks the advice:
    signin (no Claude sign-in), expired, plan (no limits), or error."""
    return {
        "ok": False,
        "reason": reason,
        "plan": plan,
        "meters": [],
        "error": text(message, 160) or "Claude usage is unavailable",
        "pollMs": POLL_MS,
    }


def collect(fetch=fetch_json, path=None, now_ms=None):
    account = credentials(path)
    if not account:
        return error_view("No Claude sign-in found", "signin")
    plan = plan_name(account["subscription"], account["tier"])
    now_ms = now_ms if now_ms is not None else int(datetime.now(timezone.utc).timestamp() * 1000)
    if account["expiresAt"] and account["expiresAt"] <= now_ms:
        return error_view("Claude Code’s sign-in has expired", "expired", plan)
    try:
        payload = fetch(USAGE_URL, account["token"])
    except HTTPError as error:
        if error.code in (401, 403):
            return error_view("Claude Code’s sign-in has expired", "expired", plan)
        if error.code == 429:
            return error_view("Anthropic asked the tile to slow down", "error", plan)
        return error_view("Anthropic answered %d" % error.code, "error", plan)
    except Exception as error:
        return error_view(text(error, 160) or "Claude usage is unavailable", "error", plan)
    return parse_usage(payload, account)


def cache_path():
    root = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(root, "ande.launcher", "claude.json")


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
        payload = error_view(text(error, 160) or "Claude usage is unavailable")
    payload["savedAt"] = int(datetime.now(timezone.utc).timestamp() * 1000)
    if payload.get("ok"):
        write_cache(payload, cache)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
