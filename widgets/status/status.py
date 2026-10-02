#!/usr/bin/env python3
"""Service status for the launcher tile. Stdlib only.

    status.py --services JSON    the tile: one row per service
    status.py --probe URL        the settings panel: what kind of page a URL is
    status.py --catalog          the settings panel: every service it can add

A service is a catalog id ("github") or a custom entry
{"url": "https://...", "name": "...", "kind": "statuspage" | "http"}.

Most status pages answer Atlassian Statuspage's /api/v2/summary.json, and
incident.io pages answer the same path in the same shape on their own host
(checked live on 2026-10-02: Linear, Notion, Docker, Groq, OpenAI). A few big
ones use their own format: Slack, Heroku, GitLab (status.io), Google Cloud and
AWS. A custom "http" entry is a plain reachability check: any answer below 500
means the server is up, since a login page that says 401 is still up.

Every row comes back as one shape: state (none, minor, major, critical,
maintenance, down, unknown), a summary line, and the page to open. Results are
cached for two minutes so reopening the launcher does not refetch.
"""

import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

USER_AGENT = "Mozilla/5.0 (omarchy-launcher status tile)"
TIMEOUT = 8
MAX_SERVICES = 8
MAX_BODY = 4_000_000
CACHE_TTL = 120

# id: (name, kind, host). Statuspage-shaped unless kind says otherwise.
CATALOG = {
    "github": ("GitHub", "statuspage", "www.githubstatus.com"),
    "gitlab": ("GitLab", "statusio", "status.gitlab.com"),
    "bitbucket": ("Bitbucket", "statuspage", "bitbucket.status.atlassian.com"),
    "claude": ("Claude", "statuspage", "status.claude.com"),
    "openai": ("OpenAI", "statuspage", "status.openai.com"),
    "cursor": ("Cursor", "statuspage", "status.cursor.com"),
    "perplexity": ("Perplexity", "statuspage", "status.perplexity.com"),
    "groq": ("Groq", "statuspage", "groqstatus.com"),
    "cohere": ("Cohere", "statuspage", "status.cohere.com"),
    "cloudflare": ("Cloudflare", "statuspage", "www.cloudflarestatus.com"),
    "aws": ("AWS", "aws", "health.aws.amazon.com"),
    "gcp": ("Google Cloud", "gcp", "status.cloud.google.com"),
    "digitalocean": ("DigitalOcean", "statuspage", "status.digitalocean.com"),
    "linode": ("Linode", "statuspage", "status.linode.com"),
    "vercel": ("Vercel", "statuspage", "www.vercel-status.com"),
    "netlify": ("Netlify", "statuspage", "www.netlifystatus.com"),
    "flyio": ("Fly.io", "statuspage", "status.flyio.net"),
    "render": ("Render", "statuspage", "status.render.com"),
    "heroku": ("Heroku", "heroku", "status.heroku.com"),
    "supabase": ("Supabase", "statuspage", "status.supabase.com"),
    "mongodb": ("MongoDB Atlas", "statuspage", "status.mongodb.com"),
    "docker": ("Docker", "statuspage", "www.dockerstatus.com"),
    "npm": ("npm", "statuspage", "status.npmjs.org"),
    "crates": ("crates.io", "statuspage", "status.crates.io"),
    "rubygems": ("RubyGems", "statuspage", "status.rubygems.org"),
    "hex": ("Hex", "statuspage", "status.hex.pm"),
    "nodejs": ("Node.js", "statuspage", "status.nodejs.org"),
    "circleci": ("CircleCI", "statuspage", "status.circleci.com"),
    "hashicorp": ("HashiCorp", "statuspage", "status.hashicorp.com"),
    "sentry": ("Sentry", "statuspage", "status.sentry.io"),
    "datadog": ("Datadog", "statuspage", "status.datadoghq.com"),
    "newrelic": ("New Relic", "statuspage", "status.newrelic.com"),
    "postman": ("Postman", "statuspage", "status.postman.com"),
    "twilio": ("Twilio", "statuspage", "status.twilio.com"),
    "slack": ("Slack", "slack", "slack-status.com"),
    "discord": ("Discord", "statuspage", "discordstatus.com"),
    "zoom": ("Zoom", "statuspage", "www.zoomstatus.com"),
    "matrix": ("Matrix", "statuspage", "status.matrix.org"),
    "reddit": ("Reddit", "statuspage", "www.redditstatus.com"),
    "twitch": ("Twitch", "statuspage", "status.twitch.com"),
    "epicgames": ("Epic Games", "statuspage", "status.epicgames.com"),
    "proton": ("Proton", "statuspage", "status.proton.me"),
    "onepassword": ("1Password", "statuspage", "status.1password.com"),
    "tailscale": ("Tailscale", "statuspage", "status.tailscale.com"),
    "dropbox": ("Dropbox", "statuspage", "status.dropbox.com"),
    "notion": ("Notion", "statuspage", "www.notion-status.com"),
    "linear": ("Linear", "statuspage", "linearstatus.com"),
    "figma": ("Figma", "statuspage", "status.figma.com"),
    "asana": ("Asana", "statuspage", "status.asana.com"),
    "trello": ("Trello", "statuspage", "trello.status.atlassian.com"),
    "zapier": ("Zapier", "statuspage", "status.zapier.com"),
    "shopify": ("Shopify", "statuspage", "www.shopifystatus.com"),
}
DEFAULTS = ["github", "cloudflare", "claude", "openai"]

STATES = ("none", "maintenance", "minor", "major", "critical", "down", "unknown")
SEVERITY = {"none": 0, "maintenance": 1, "unknown": 2, "minor": 3, "major": 4, "critical": 5, "down": 5}

HOST = re.compile(r"[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*(:\d{1,5})?")


class FetchError(Exception):
    def __init__(self, status, message=""):
        super().__init__(message or "HTTP %s" % status)
        self.status = status


def fetch(url, timeout=TIMEOUT, raw=False):
    """(status, body, seconds) for a GET. Raises FetchError on 5xx and URLError."""
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json, */*"})
    started = time.monotonic()
    try:
        with urlopen(request, timeout=timeout) as reply:
            body = reply.read(MAX_BODY)
            status = reply.status
    except HTTPError as error:
        status, body = error.code, b""
    return status, body, time.monotonic() - started


def fetch_json(url, encoding=None, fetcher=fetch):
    status, body, _ = fetcher(url)
    if status >= 400:
        raise FetchError(status)
    try:
        return json.loads(body.decode(encoding) if encoding else body)
    except (ValueError, UnicodeDecodeError):
        raise FetchError(0, "unreadable")


def text(value, limit=120):
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


def clean_url(raw):
    """An http(s) URL with a sane host, or ""."""
    value = str(raw or "").strip()
    if not value:
        return ""
    if "://" not in value:
        value = "https://" + value
    try:
        parts = urlsplit(value)
    except ValueError:
        return ""
    host = (parts.netloc or "").lower()
    if parts.scheme not in ("http", "https") or "@" in host or not HOST.fullmatch(host):
        return ""
    if any(ch in value for ch in " \t\n\"'<>\\`"):
        return ""
    return value[:300]


def clean_services(raw):
    """Catalog ids and custom entries, deduplicated, at most MAX_SERVICES."""
    try:
        rows = json.loads(raw) if isinstance(raw, str) else raw
    except ValueError:
        rows = None
    if not isinstance(rows, list):
        rows = list(DEFAULTS)
    out, seen = [], set()
    for row in rows:
        if isinstance(row, str) and row in CATALOG:
            key = row
            entry = {"id": row}
        elif isinstance(row, dict):
            url = clean_url(row.get("url"))
            kind = row.get("kind") if row.get("kind") in ("statuspage", "http") else "http"
            if not url:
                continue
            key = "%s:%s" % (kind, url)
            entry = {"url": url, "kind": kind, "name": text(row.get("name"), 40) or urlsplit(url).netloc}
        else:
            continue
        if key in seen:
            continue
        seen.add(key)
        out.append(entry)
        if len(out) >= MAX_SERVICES:
            break
    return out


# —— Adapters: each returns (state, summary, link) ——


def worst(states):
    best = "none"
    for state in states:
        if SEVERITY.get(state, 0) > SEVERITY.get(best, 0):
            best = state
    return best


def from_statuspage(data, page):
    if not isinstance(data, dict) or not isinstance(data.get("status"), dict):
        raise FetchError(0, "not a status page")
    indicator = str(data["status"].get("indicator") or "none")
    state = indicator if indicator in STATES else "unknown"
    summary = text(data["status"].get("description")) or "All Systems Operational"
    link = page
    incidents = [i for i in data.get("incidents") or [] if isinstance(i, dict) and i.get("status") not in ("resolved", "postmortem")]
    if incidents:
        first = incidents[0]
        impact = str(first.get("impact") or "")
        if impact in ("minor", "major", "critical"):
            state = worst([state, impact])
        elif state == "none":
            state = "minor"
        summary = text(first.get("name")) or summary
        if len(incidents) > 1:
            summary += " (+%d more)" % (len(incidents) - 1)
        link = str(first.get("shortlink") or "") or page
    else:
        live = [m for m in data.get("scheduled_maintenances") or [] if isinstance(m, dict) and m.get("status") == "in_progress"]
        if live:
            state = worst([state, "maintenance"])
            summary = "Maintenance: " + (text(live[0].get("name")) or "in progress")
            link = str(live[0].get("shortlink") or "") or page
    return state, summary, link


def from_slack(data, page):
    status = str((data or {}).get("status") or "")
    active = [i for i in (data or {}).get("active_incidents") or [] if isinstance(i, dict)]
    if status == "ok" and not active:
        return "none", "All Systems Operational", page
    if not active:
        return ("unknown" if status not in ("active", "broken") else "minor"), "Slack reports a problem", page
    kinds = [str(i.get("type") or "") for i in active]
    state = "major" if "outage" in kinds else ("minor" if "incident" in kinds else "maintenance")
    return state, text(active[0].get("title")) or "Incident", str(active[0].get("url") or "") or page


def from_heroku(data, page):
    systems = [s for s in (data or {}).get("status") or [] if isinstance(s, dict)]
    colors = {"green": "none", "yellow": "minor", "red": "major"}
    state = worst(colors.get(str(s.get("status")), "unknown") for s in systems) if systems else "unknown"
    incidents = [i for i in (data or {}).get("incidents") or [] if isinstance(i, dict)]
    if incidents:
        return worst([state, "minor"]), text(incidents[0].get("title")) or "Incident", page
    if state == "none":
        return state, "All Systems Operational", page
    bad = [str(s.get("system")) for s in systems if s.get("status") != "green"]
    return state, "Trouble with " + ", ".join(bad), page


# status.io: 100 operational, 200 planned maintenance, 300 degraded
# performance, 400 partial disruption, 500 disruption, 600 security event.
STATUSIO = {100: "none", 200: "maintenance", 300: "minor", 400: "major", 500: "critical", 600: "major"}


def from_statusio(data, page):
    result = (data or {}).get("result") or {}
    overall = result.get("status_overall") or {}
    try:
        code = int(overall.get("status_code"))
    except (TypeError, ValueError):
        code = 0
    state = STATUSIO.get(code, "unknown")
    incidents = [i for i in result.get("incidents") or [] if isinstance(i, dict)]
    if incidents:
        return worst([state, "minor"]), text(incidents[0].get("name")) or "Incident", page
    return state, text(overall.get("status")) or ("All Systems Operational" if state == "none" else "Status unknown"), page


GCP_SEVERITY = {"low": "minor", "medium": "major", "high": "critical"}


def from_gcp(data, page):
    open_ = [i for i in data if isinstance(i, dict) and not i.get("end")] if isinstance(data, list) else None
    if open_ is None:
        raise FetchError(0, "unreadable")
    if not open_:
        return "none", "All Systems Operational", page
    state = worst(GCP_SEVERITY.get(str(i.get("severity")), "minor") for i in open_)
    first = open_[0]
    summary = text(first.get("external_desc")) or "Incident"
    if len(open_) > 1:
        summary += " (+%d more)" % (len(open_) - 1)
    uri = str(first.get("uri") or "")
    link = page + uri if uri.startswith("incidents/") else page
    return state, summary, link


# AWS Health event status: 0 resolved, 1 informational, 2 degraded, 3 disrupted.
AWS_STATUS = {"1": "minor", "2": "minor", "3": "major"}


def from_aws(data, page):
    if not isinstance(data, list):
        raise FetchError(0, "unreadable")
    events = []
    for event in data:
        if not isinstance(event, dict):
            continue
        log = event.get("event_log") or []
        latest = str((log[-1] if log and isinstance(log[-1], dict) else event).get("status") or event.get("status") or "0")
        if latest in AWS_STATUS:
            events.append((AWS_STATUS[latest], event))
    if not events:
        return "none", "All Systems Operational", page
    state = worst(state for state, _ in events)
    regions = []
    for _, event in events:
        region = text(event.get("region_name"), 30)
        if region and region not in regions:
            regions.append(region)
    services = {text(event.get("service_name"), 40) for _, event in events}
    what = services.pop() if len(services) == 1 else "%d events" % len(events)
    summary = what + (" in " + ", ".join(regions[:3]) if regions else "")
    return state, summary, page


def check_http(url, fetcher=fetch):
    """Up while the server answers below 500, with the round trip in ms."""
    try:
        status, _, seconds = fetcher(url)
    except (URLError, OSError, ValueError):
        return "down", "No answer", None
    ms = int(round(seconds * 1000))
    if status >= 500:
        return "down", "HTTP %d" % status, ms
    return "none", "Up · %d ms" % ms, ms


def collect_one(entry, fetcher=fetch):
    if "id" in entry:
        name, kind, host = CATALOG[entry["id"]]
        page = "https://%s/" % host
        row = {"key": entry["id"], "name": name, "page": page, "kind": kind}
    else:
        kind = entry["kind"]
        url = entry["url"]
        parts = urlsplit(url)
        page = "%s://%s/" % (parts.scheme, parts.netloc) if kind == "statuspage" else url
        row = {"key": "%s:%s" % (kind, url), "name": entry["name"], "page": page, "kind": kind}
    latency = None
    try:
        if kind == "statuspage":
            state, summary, link = from_statuspage(fetch_json(page + "api/v2/summary.json", fetcher=fetcher), page)
        elif kind == "slack":
            state, summary, link = from_slack(fetch_json("https://slack-status.com/api/v2.0.0/current", fetcher=fetcher), "https://slack-status.com/")
        elif kind == "heroku":
            state, summary, link = from_heroku(fetch_json(page + "api/v4/current-status", fetcher=fetcher), page)
        elif kind == "statusio":
            state, summary, link = from_statusio(fetch_json(page + "1.0/status/5b36dc6502d06804c08349f7", fetcher=fetcher), page)
        elif kind == "gcp":
            state, summary, link = from_gcp(fetch_json(page + "incidents.json", fetcher=fetcher), page)
        elif kind == "aws":
            state, summary, link = from_aws(fetch_json(page + "public/currentevents", encoding="utf-16", fetcher=fetcher), page)
        else:
            state, summary, latency = check_http(page, fetcher)
            link = page
    except FetchError as error:
        state, summary, link = "unknown", ("Status page answered %s" % error.status) if error.status else "Status page sent something unreadable", page
    except (URLError, OSError, ValueError):
        state, summary, link = "unknown", "Status page did not answer", page
    row.update({"state": state, "summary": summary, "link": link, "latency": latency})
    return row


def collect(raw, fetcher=fetch):
    entries = clean_services(raw)
    if not entries:
        return {"ok": True, "services": [], "worst": "none"}
    with ThreadPoolExecutor(max_workers=len(entries)) as pool:
        rows = list(pool.map(lambda entry: collect_one(entry, fetcher), entries))
    return {"ok": True, "services": rows, "worst": worst(row["state"] for row in rows if row["state"] != "unknown")}


def probe(raw, fetcher=fetch):
    """Whether a URL is a status page (and its name) or a plain site to check."""
    url = clean_url(raw)
    if not url:
        return {"ok": False, "error": "That isn't a web address"}
    parts = urlsplit(url)
    base = "%s://%s/" % (parts.scheme, parts.netloc)
    try:
        data = fetch_json(base + "api/v2/summary.json", fetcher=fetcher)
        if isinstance(data, dict) and isinstance(data.get("status"), dict):
            name = text(((data.get("page") or {}).get("name")), 40) or parts.netloc
            return {"ok": True, "kind": "statuspage", "url": base, "name": name}
    except (FetchError, URLError, OSError, ValueError):
        pass
    state, _, _ = check_http(url, fetcher)
    if state == "down":
        return {"ok": False, "error": "%s did not answer" % parts.netloc}
    return {"ok": True, "kind": "http", "url": url, "name": parts.netloc}


# —— Cache ——


def cache_path():
    root = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(root, "ande.launcher", "status.json")


def read_cache(key, now, path=None):
    try:
        with open(path or cache_path(), encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or data.get("key") != key:
        return None
    if not 0 <= now - float(data.get("at") or 0) <= CACHE_TTL:
        return None
    return data.get("payload")


def write_cache(key, payload, now, path=None):
    path = path or cache_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump({"key": key, "at": now, "payload": payload}, handle)
        os.replace(tmp, path)
    except OSError:
        pass


def option(args, name):
    if name not in args:
        return None
    index = args.index(name)
    return args[index + 1] if index + 1 < len(args) else ""


def catalog():
    return [{"id": key, "name": name, "host": host} for key, (name, _, host) in CATALOG.items()]


def main(argv):
    args = argv[1:]
    url = option(args, "--probe")
    if "--catalog" in args:
        payload = {"ok": True, "services": catalog(), "defaults": DEFAULTS}
    elif url is not None:
        payload = probe(url)
    else:
        raw = option(args, "--services") or "null"
        key = json.dumps(clean_services(raw), sort_keys=True)
        now = time.time()
        payload = None if "--fresh" in args else read_cache(key, now)
        if payload is None:
            payload = collect(raw)
            payload["at"] = now
            write_cache(key, payload, now)
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
