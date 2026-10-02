#!/usr/bin/env python3
"""Upcoming events from iCalendar (.ics) feeds, for the launcher tile. Stdlib only.

    agenda.py                the tile: events from every saved calendar
    agenda.py --list         the settings panel: the saved calendars
    agenda.py --add          the settings panel: save the calendar in
                             $ANDE_CALENDAR_URL (named $ANDE_CALENDAR_NAME)
    agenda.py --remove ID    forget one calendar

The file is agenda.py, not calendar.py: a calendar.py next to it would stand in
for the standard library's calendar module, which email._parseaddr and
http.cookiejar import.

A calendar is an http(s) or webcal address (Google's "secret address in iCal
format", an iCloud public calendar, Outlook's published ICS link, Fastmail,
Proton, any .ics on the web) or a local .ics file or a folder of them (a
vdirsyncer collection). An address like Google's is a password, so the saved
list lives in $XDG_CONFIG_HOME/ande.launcher/calendars.json at mode 0600, never
in the launcher's config or on a command line; the panel hands a new one over
in the environment.

Recurring events are expanded here: RRULE with FREQ DAILY, WEEKLY, MONTHLY or
YEARLY, INTERVAL, COUNT, UNTIL, BYDAY (with ordinals like 2MO and -1FR),
BYMONTHDAY, BYMONTH and BYSETPOS, plus RDATE, EXDATE, and RECURRENCE-ID for an
instance moved or cancelled on its own. Times are expanded in the event's own
zone, so a weekly 9:00 stays 9:00 across a daylight-saving change. Outlook's
Windows zone names are mapped to IANA ones.
"""

import hashlib
import json
import os
import re
import secrets
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) omarchy-launcher-calendar"
TIMEOUT = 15
MAX_BODY = 25_000_000
MAX_CALENDARS = 8
MAX_EVENTS = 300
MAX_STEPS = 60_000
TTL = 15 * 60
STALE_MAX = 7 * 86400
WINDOW_BEFORE_DAYS = 42
WINDOW_AFTER_DAYS = 60
URL_ENV = "ANDE_CALENDAR_URL"
NAME_ENV = "ANDE_CALENDAR_NAME"

WEEKDAYS = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}

# Outlook and Exchange write Windows zone names. The common ones, by CLDR.
WINDOWS_ZONES = {
    "Dateline Standard Time": "Etc/GMT+12",
    "Hawaiian Standard Time": "Pacific/Honolulu",
    "Alaskan Standard Time": "America/Anchorage",
    "Pacific Standard Time": "America/Los_Angeles",
    "Pacific Standard Time (Mexico)": "America/Tijuana",
    "US Mountain Standard Time": "America/Phoenix",
    "Mountain Standard Time": "America/Denver",
    "Central America Standard Time": "America/Guatemala",
    "Central Standard Time": "America/Chicago",
    "Central Standard Time (Mexico)": "America/Mexico_City",
    "Canada Central Standard Time": "America/Regina",
    "SA Pacific Standard Time": "America/Bogota",
    "Eastern Standard Time": "America/New_York",
    "US Eastern Standard Time": "America/Indianapolis",
    "Atlantic Standard Time": "America/Halifax",
    "Newfoundland Standard Time": "America/St_Johns",
    "E. South America Standard Time": "America/Sao_Paulo",
    "Argentina Standard Time": "America/Buenos_Aires",
    "UTC": "UTC",
    "Coordinated Universal Time": "UTC",
    "GMT Standard Time": "Europe/London",
    "Greenwich Standard Time": "Atlantic/Reykjavik",
    "W. Europe Standard Time": "Europe/Berlin",
    "Central Europe Standard Time": "Europe/Budapest",
    "Romance Standard Time": "Europe/Paris",
    "Central European Standard Time": "Europe/Warsaw",
    "GTB Standard Time": "Europe/Bucharest",
    "FLE Standard Time": "Europe/Kiev",
    "E. Europe Standard Time": "Europe/Chisinau",
    "Israel Standard Time": "Asia/Jerusalem",
    "South Africa Standard Time": "Africa/Johannesburg",
    "Russian Standard Time": "Europe/Moscow",
    "Turkey Standard Time": "Europe/Istanbul",
    "Arabian Standard Time": "Asia/Dubai",
    "Iran Standard Time": "Asia/Tehran",
    "Pakistan Standard Time": "Asia/Karachi",
    "India Standard Time": "Asia/Calcutta",
    "Nepal Standard Time": "Asia/Katmandu",
    "Bangladesh Standard Time": "Asia/Dhaka",
    "SE Asia Standard Time": "Asia/Bangkok",
    "China Standard Time": "Asia/Shanghai",
    "Singapore Standard Time": "Asia/Singapore",
    "Taipei Standard Time": "Asia/Taipei",
    "Tokyo Standard Time": "Asia/Tokyo",
    "Korea Standard Time": "Asia/Seoul",
    "AUS Central Standard Time": "Australia/Darwin",
    "E. Australia Standard Time": "Australia/Brisbane",
    "AUS Eastern Standard Time": "Australia/Sydney",
    "Tasmania Standard Time": "Australia/Hobart",
    "New Zealand Standard Time": "Pacific/Auckland",
}

MEETING = re.compile(
    r"https://(?:[a-z0-9-]+\.)*(?:meet\.google\.com|zoom\.us|zoomgov\.com|teams\.microsoft\.com|teams\.live\.com|"
    r"whereby\.com|webex\.com|meet\.jit\.si|discord\.gg|discord\.com|gotomeeting\.com|meet\.goto\.com|"
    r"chime\.aws|around\.co|app\.slack\.com/huddle|bluejeans\.com|meet\.proton\.me)[^\s\"'<>\\`]*",
    re.I,
)
HOST = re.compile(r"[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*(:\d{1,5})?")


class CalendarError(Exception):
    pass


# —— Values ——


def local_zone():
    try:
        name = os.path.realpath("/etc/localtime").split("zoneinfo/", 1)[1]
        return ZoneInfo(name)
    except (IndexError, ZoneInfoNotFoundError, ValueError, OSError):
        return datetime.now().astimezone().tzinfo


def zone_for(tzid, fallback):
    """A tzinfo for a TZID: IANA, a Windows name, or a vendor prefix around an IANA name."""
    name = str(tzid or "").strip().strip('"')
    if not name:
        return fallback
    name = WINDOWS_ZONES.get(name, name)
    for candidate in (name, re.sub(r"^/?(?:[^/]+/)*?(?=[A-Z][a-z]+/)", "", name)):
        try:
            return ZoneInfo(candidate)
        except (ZoneInfoNotFoundError, ValueError):
            continue
    match = re.search(r"([A-Z][A-Za-z_]+/[A-Z][A-Za-z_]+(?:/[A-Z][A-Za-z_]+)?)", name)
    if match:
        try:
            return ZoneInfo(match.group(1))
        except (ZoneInfoNotFoundError, ValueError):
            pass
    return fallback


def unescape(value):
    return (str(value or "").replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",")
            .replace("\\;", ";").replace("\\\\", "\\"))


def one_line(value, limit=160):
    return re.sub(r"\s+", " ", unescape(value)).strip()[:limit]


def parse_dt(value, params, fallback_zone):
    """(datetime or date, is_all_day). Datetimes come back aware."""
    raw = str(value or "").strip()
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", raw):
        return date(int(raw[0:4]), int(raw[4:6]), int(raw[6:8])), True
    match = re.fullmatch(r"(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?", raw)
    if not match:
        raise ValueError("bad date-time: %r" % raw)
    year, month, day, hour, minute, second, utc = match.groups()
    naive = datetime(int(year), int(month), int(day), int(hour), int(minute), int(second or 0))
    if utc:
        return naive.replace(tzinfo=timezone.utc), False
    return naive.replace(tzinfo=zone_for(params.get("TZID"), fallback_zone)), False


def parse_duration(value):
    match = re.fullmatch(r"([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", str(value or "").strip())
    if not match:
        return None
    sign, weeks, days, hours, minutes, seconds = match.groups()
    delta = timedelta(weeks=int(weeks or 0), days=int(days or 0), hours=int(hours or 0),
                      minutes=int(minutes or 0), seconds=int(seconds or 0))
    return -delta if sign == "-" else delta


# —— Reading the file ——


def unfold(text):
    """Logical lines: a line that starts with a space or tab continues the one before."""
    lines = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        elif raw:
            lines.append(raw)
    return lines


def split_property(line):
    """(NAME, {PARAM: value}, value) from one content line."""
    # The value starts at the first colon that is not inside a quoted parameter.
    quoted = False
    for index, char in enumerate(line):
        if char == '"':
            quoted = not quoted
        elif char == ":" and not quoted:
            head, value = line[:index], line[index + 1:]
            break
    else:
        return None
    parts = re.findall(r'(?:[^;"]|"[^"]*")+', head)
    if not parts:
        return None
    params = {}
    for part in parts[1:]:
        key, _, val = part.partition("=")
        params[key.strip().upper()] = val.strip().strip('"')
    return parts[0].strip().upper(), params, value


def parse_calendar(text):
    """(calendar name, [VEVENT dicts]). Each event maps a property name to a list of (params, value)."""
    name = ""
    events = []
    current = None
    depth = []
    for line in unfold(text):
        prop = split_property(line)
        if not prop:
            continue
        key, params, value = prop
        if key == "BEGIN":
            depth.append(value.strip().upper())
            if depth[-1] == "VEVENT" and len(depth) >= 1:
                current = {}
            continue
        if key == "END":
            if depth and depth[-1] == "VEVENT" and current is not None:
                events.append(current)
                current = None
            if depth:
                depth.pop()
            continue
        if current is not None and depth and depth[-1] == "VEVENT":
            current.setdefault(key, []).append((params, value))
        elif key == "X-WR-CALNAME" and not name and depth == ["VCALENDAR"]:
            name = one_line(value, 60)
    if not depth and not events and "BEGIN:VCALENDAR" not in text.upper():
        raise CalendarError("is not a calendar")
    return name, events


def first(event, key):
    values = event.get(key) or []
    return values[0] if values else ({}, "")


# —— Recurrence ——


def parse_rrule(value):
    rule = {}
    for part in str(value or "").split(";"):
        key, _, val = part.partition("=")
        if key:
            rule[key.strip().upper()] = val.strip()
    return rule


def byday(value):
    """[(ordinal or None, weekday)] from BYDAY=MO,2TU,-1FR."""
    out = []
    for item in str(value or "").split(","):
        match = re.fullmatch(r"([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)", item.strip().upper())
        if match:
            out.append((int(match.group(1)) if match.group(1) else None, WEEKDAYS[match.group(2)]))
    return out


def ints(value):
    out = []
    for item in str(value or "").split(","):
        try:
            out.append(int(item))
        except ValueError:
            pass
    return out


def days_in_month(year, month):
    return (date(year + month // 12, month % 12 + 1, 1) - timedelta(days=1)).day


def nth_weekdays(year, month, rules):
    """Days of a month that match BYDAY entries, each with an optional ordinal."""
    last = days_in_month(year, month)
    days = []
    for ordinal, weekday in rules:
        matches = [d for d in range(1, last + 1) if date(year, month, d).weekday() == weekday]
        if ordinal is None:
            days.extend(matches)
        elif 0 < ordinal <= len(matches):
            days.append(matches[ordinal - 1])
        elif 0 < -ordinal <= len(matches):
            days.append(matches[ordinal])
    return days


def month_days(year, month, rule, start_day):
    """The days of one month a MONTHLY or YEARLY rule lands on, before BYSETPOS."""
    last = days_in_month(year, month)
    if "BYMONTHDAY" in rule:
        days = []
        for value in ints(rule["BYMONTHDAY"]):
            day = value if value > 0 else last + value + 1
            if 1 <= day <= last:
                days.append(day)
        if "BYDAY" in rule:
            weekdays = {w for _, w in byday(rule["BYDAY"])}
            days = [d for d in days if date(year, month, d).weekday() in weekdays]
    elif "BYDAY" in rule:
        days = nth_weekdays(year, month, byday(rule["BYDAY"]))
    else:
        days = [start_day] if start_day <= last else []
    days = sorted(set(days))
    if "BYSETPOS" in rule and days:
        picked = []
        for pos in ints(rule["BYSETPOS"]):
            if 0 < pos <= len(days):
                picked.append(days[pos - 1])
            elif 0 < -pos <= len(days):
                picked.append(days[pos])
        days = sorted(set(picked))
    return days


def occurrences(start, rule, until_limit):
    """Start values of a recurring event, in order, from its first.

    `start` is a date or an aware datetime; times are stepped in the start's
    own zone. Stops at COUNT, UNTIL, `until_limit`, or MAX_STEPS candidates."""
    freq = rule.get("FREQ", "").upper()
    if freq not in ("DAILY", "WEEKLY", "MONTHLY", "YEARLY"):
        yield start
        return
    interval = max(1, ints(rule.get("INTERVAL", "1"))[0] if ints(rule.get("INTERVAL", "1")) else 1)
    count = ints(rule.get("COUNT", ""))
    count = count[0] if count else None
    until = None
    if rule.get("UNTIL"):
        try:
            until, _ = parse_dt(rule["UNTIL"], {}, start.tzinfo if isinstance(start, datetime) else timezone.utc)
        except ValueError:
            until = None
    all_day = not isinstance(start, datetime)
    months = ints(rule.get("BYMONTH", ""))
    emitted = 0
    steps = 0

    def wall(day):
        if all_day:
            return day
        return datetime(day.year, day.month, day.day, start.hour, start.minute, start.second, tzinfo=start.tzinfo)

    def past_until(value):
        if until is None:
            return False
        if isinstance(until, datetime) and not all_day:
            return value > until
        if isinstance(until, datetime):
            return value > until.date()
        return (value.date() if isinstance(value, datetime) else value) > until

    def after_limit(value):
        return (value.date() if isinstance(value, datetime) else value) > until_limit

    base = start.date() if isinstance(start, datetime) else start
    period = 0
    while steps < MAX_STEPS:
        if freq == "DAILY":
            day = base + timedelta(days=period * interval)
            candidates = [day]
            if months and day.month not in months:
                candidates = []
            if "BYDAY" in rule and day.weekday() not in {w for _, w in byday(rule["BYDAY"])}:
                candidates = []
            if "BYMONTHDAY" in rule:
                last = days_in_month(day.year, day.month)
                wanted = {(v if v > 0 else last + v + 1) for v in ints(rule["BYMONTHDAY"])}
                if day.day not in wanted:
                    candidates = []
        elif freq == "WEEKLY":
            week_start = base - timedelta(days=base.weekday()) + timedelta(weeks=period * interval)
            weekdays = sorted({w for _, w in byday(rule.get("BYDAY", ""))}) or [base.weekday()]
            candidates = [week_start + timedelta(days=w) for w in weekdays]
            if months:
                candidates = [d for d in candidates if d.month in months]
            day = week_start
        elif freq == "MONTHLY":
            total = base.year * 12 + base.month - 1 + period * interval
            year, month = divmod(total, 12)
            month += 1
            candidates = [] if months and month not in months else [date(year, month, d) for d in month_days(year, month, rule, base.day)]
            day = date(year, month, 1)
        else:
            year = base.year + period * interval
            in_months = months or [base.month]
            candidates = []
            for month in sorted(in_months):
                if 1 <= month <= 12:
                    candidates.extend(date(year, month, d) for d in month_days(year, month, rule, base.day))
            day = date(year, 1, 1)
        period += 1
        if day > until_limit + timedelta(days=366) and freq != "DAILY" or (freq == "DAILY" and day > until_limit):
            return
        for candidate in candidates:
            steps += 1
            if candidate < base:
                continue
            value = wall(candidate)
            if past_until(value):
                return
            if count is not None and emitted >= count:
                return
            emitted += 1
            if after_limit(value):
                return
            yield value


# —— Instances ——


def as_utc(value, zone):
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc)
    return datetime(value.year, value.month, value.day, tzinfo=zone).astimezone(timezone.utc)


def instance_key(value):
    """A start value as a comparable key: dates by day, times by UTC instant."""
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return value.strftime("%Y%m%d")


def meeting_link(event):
    for key in ("LOCATION", "DESCRIPTION", "URL", "X-GOOGLE-CONFERENCE", "X-MICROSOFT-SKYPETEAMSMEETINGURL"):
        for _, value in event.get(key) or []:
            match = MEETING.search(unescape(value))
            if match:
                return match.group(0).rstrip(".,;)>")
    _, url = first(event, "URL")
    url = unescape(url).strip()
    return url if re.fullmatch(r"https://[^\s\"'<>\\`]{1,1000}", url) else ""


def expand(events, window_start, window_end, zone):
    """Every instance that overlaps [window_start, window_end), as plain dicts."""
    masters = {}
    overrides = {}
    loose = []
    for event in events:
        uid = one_line(first(event, "UID")[1], 300)
        if event.get("RECURRENCE-ID"):
            params, value = first(event, "RECURRENCE-ID")
            try:
                original, _ = parse_dt(value, params, zone)
            except ValueError:
                continue
            overrides.setdefault(uid, {})[instance_key(original)] = event
        elif uid and uid in masters:
            loose.append(event)
        elif uid:
            masters[uid] = event
        else:
            loose.append(event)

    limit = window_end.astimezone(zone).date()
    out = []

    def add(event, start_value, all_day, length):
        start_utc = as_utc(start_value, zone)
        end_utc = as_utc(start_value + length, zone) if length else start_utc
        if end_utc <= window_start and not (end_utc == start_utc and start_utc >= window_start):
            return
        if start_utc >= window_end:
            return
        out.append({
            "title": one_line(first(event, "SUMMARY")[1]) or "(no title)",
            "start": int(start_utc.timestamp()),
            "end": int(end_utc.timestamp()),
            "allDay": all_day,
            "location": one_line(first(event, "LOCATION")[1], 120),
            "link": meeting_link(event),
        })

    def length_of(event, start_value, all_day):
        if one_line(first(event, "STATUS")[1]).upper() == "CANCELLED":
            return None
        params, value = first(event, "DTEND")
        if value:
            try:
                end_value, _ = parse_dt(value, params, zone)
                if type(end_value) is type(start_value):
                    span = end_value - start_value
                    return span if span.total_seconds() >= 0 else timedelta(0)
            except ValueError:
                pass
        duration = parse_duration(first(event, "DURATION")[1])
        if duration is not None:
            return duration
        return timedelta(days=1) if all_day else timedelta(0)

    for uid, event in list(masters.items()) + [("", e) for e in loose]:
        params, value = first(event, "DTSTART")
        try:
            start, all_day = parse_dt(value, params, zone)
        except ValueError:
            continue
        length = length_of(event, start, all_day)
        rule = parse_rrule(first(event, "RRULE")[1]) if event.get("RRULE") else None
        moved = overrides.get(uid, {}) if uid else {}
        excluded = set()
        for ex_params, ex_value in event.get("EXDATE") or []:
            for item in ex_value.split(","):
                try:
                    excluded.add(instance_key(parse_dt(item, ex_params, zone)[0]))
                except ValueError:
                    pass
        starts = []
        if rule:
            starts.extend(occurrences(start, rule, limit))
        else:
            starts.append(start)
        for rd_params, rd_value in event.get("RDATE") or []:
            for item in rd_value.split(","):
                try:
                    starts.append(parse_dt(item.split("/")[0], rd_params, zone)[0])
                except ValueError:
                    pass
        seen = set()
        for value in starts:
            key = instance_key(value)
            # Some calendars exclude a timed instance with a date-only EXDATE.
            day_key = value.astimezone(zone).strftime("%Y%m%d") if isinstance(value, datetime) else key
            if key in seen or key in excluded or day_key in excluded:
                continue
            seen.add(key)
            if key in moved:
                continue
            if length is not None:
                add(event, value, all_day, length)
        for key, override in moved.items():
            o_params, o_value = first(override, "DTSTART")
            try:
                o_start, o_all_day = parse_dt(o_value, o_params, zone)
            except ValueError:
                continue
            o_length = length_of(override, o_start, o_all_day)
            if o_length is not None:
                add(override, o_start, o_all_day, o_length)
    # An override whose series is missing still happened.
    for uid, moved in overrides.items():
        if uid in masters:
            continue
        for override in moved.values():
            o_params, o_value = first(override, "DTSTART")
            try:
                o_start, o_all_day = parse_dt(o_value, o_params, zone)
            except ValueError:
                continue
            o_length = length_of(override, o_start, o_all_day)
            if o_length is not None:
                add(override, o_start, o_all_day, o_length)
    out.sort(key=lambda e: (e["start"], not e["allDay"], e["title"]))
    return out


# —— Where calendars live ——


def config_path():
    root = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(root, "ande.launcher", "calendars.json")


def cache_dir():
    root = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(root, "ande.launcher", "calendar")


def read_saved(path=None):
    try:
        with open(path or config_path(), encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return []
    rows = data.get("calendars") if isinstance(data, dict) else None
    return [r for r in rows if isinstance(r, dict) and r.get("id") and r.get("source")] if isinstance(rows, list) else []


def write_private(path, payload):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def write_saved(rows, path=None):
    write_private(path or config_path(), {"calendars": rows})


def clean_source(raw):
    """("url", https URL) or ("path", absolute path), or ("", "")."""
    value = str(raw or "").strip()
    if not value:
        return "", ""
    if value.startswith("~") or value.startswith("/"):
        path = os.path.abspath(os.path.expanduser(value))
        return ("path", path) if os.path.exists(path) else ("", "")
    if value.lower().startswith("webcal://"):
        value = "https://" + value[9:]
    if "://" not in value:
        value = "https://" + value
    try:
        parts = urlsplit(value)
    except ValueError:
        return "", ""
    host = (parts.netloc or "").lower()
    if parts.scheme not in ("http", "https") or "@" in host or not HOST.fullmatch(host):
        return "", ""
    if any(ch in value for ch in " \t\n\"'<>\\`"):
        return "", ""
    return "url", value[:2000]


def where(source):
    """How the panel shows a calendar's address: the host only, since the rest is a secret."""
    kind, value = clean_source(source)
    if kind == "url":
        return urlsplit(value).netloc + "/…"
    if kind == "path":
        home = os.path.expanduser("~")
        return "~" + value[len(home):] if value.startswith(home) else value
    return ""


# —— Fetching ——


def fetch(url, timeout=TIMEOUT):
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/calendar, */*;q=0.5"})
    try:
        with urlopen(request, timeout=timeout) as reply:
            body = reply.read(MAX_BODY)
    except HTTPError as error:
        raise CalendarError("answered %d" % error.code)
    except (URLError, OSError, ValueError):
        raise CalendarError("did not answer")
    return body.decode("utf-8", "replace")


def read_local(path):
    """The text of an .ics file, or of every .ics in a folder (a vdirsyncer collection)."""
    files = []
    if os.path.isdir(path):
        for root, _, names in os.walk(path):
            files.extend(os.path.join(root, n) for n in sorted(names) if n.lower().endswith(".ics"))
            if len(files) > 20_000:
                break
    elif os.path.isfile(path):
        files = [path]
    else:
        raise CalendarError("is missing")
    chunks = []
    for name in files:
        try:
            with open(name, encoding="utf-8", errors="replace") as handle:
                chunks.append(handle.read())
        except OSError:
            continue
    return "\n".join(chunks)


def cache_file(calendar_id, folder=None):
    safe = hashlib.sha1(str(calendar_id).encode()).hexdigest()[:20]
    return os.path.join(folder or cache_dir(), safe + ".json")


def load_text(calendar, now, fetcher=fetch, folder=None):
    """(text, error) for one calendar: local files read fresh, web ones cached."""
    kind, value = clean_source(calendar.get("source"))
    if kind == "path":
        try:
            return read_local(value), ""
        except CalendarError as error:
            return "", str(error)
    if kind != "url":
        return "", "has a bad address"
    path = cache_file(calendar["id"], folder)
    cached = None
    try:
        with open(path, encoding="utf-8") as handle:
            cached = json.load(handle)
    except (OSError, ValueError):
        cached = None
    if isinstance(cached, dict) and 0 <= now - float(cached.get("at") or 0) < TTL:
        return str(cached.get("text") or ""), ""
    try:
        text = fetcher(value)
    except CalendarError as error:
        if isinstance(cached, dict) and now - float(cached.get("at") or 0) < STALE_MAX:
            return str(cached.get("text") or ""), str(error)
        return "", str(error)
    try:
        write_private(path, {"at": now, "text": text})
    except OSError:
        pass
    return text, ""


# —— Commands ——


def window(now, zone):
    today = datetime.fromtimestamp(now, zone).date()
    start = datetime(today.year, today.month, 1, tzinfo=zone) - timedelta(days=7)
    start = min(start, datetime(today.year, today.month, today.day, tzinfo=zone) - timedelta(days=WINDOW_BEFORE_DAYS))
    end = datetime(today.year, today.month, today.day, tzinfo=zone) + timedelta(days=WINDOW_AFTER_DAYS)
    return start.astimezone(timezone.utc), end.astimezone(timezone.utc)


def collect(now=None, saved=None, fetcher=fetch, folder=None, zone=None):
    now = time.time() if now is None else now
    zone = zone or local_zone()
    saved = read_saved() if saved is None else saved
    start, end = window(now, zone)
    calendars = saved[:MAX_CALENDARS]

    def one(indexed):
        index, calendar = indexed
        text, error = load_text(calendar, now, fetcher, folder)
        events = []
        if text:
            try:
                _, parsed = parse_calendar(text)
                events = expand(parsed, start, end, zone)
            except CalendarError as problem:
                error = str(problem)
        for event in events:
            event["calendar"] = index
        return {"id": calendar["id"], "name": calendar.get("name") or "Calendar", "ok": not error, "error": error}, events

    results = []
    if calendars:
        with ThreadPoolExecutor(max_workers=len(calendars)) as pool:
            results = list(pool.map(one, enumerate(calendars)))
    events = [e for _, evs in results for e in evs]
    events.sort(key=lambda e: (e["start"], not e["allDay"], e["title"]))
    return {
        "ok": True,
        "calendars": [info for info, _ in results],
        "events": cap(events, now),
        "window": {"start": int(start.timestamp()), "end": int(end.timestamp())},
    }


def cap(events, now, limit=MAX_EVENTS):
    """At most `limit` events: everything not over yet first, then the latest past ones."""
    if len(events) <= limit:
        return events
    upcoming = [e for e in events if e["end"] >= now][:limit]
    past = [e for e in events if e["end"] < now]
    room = limit - len(upcoming)
    kept = (past[-room:] if room > 0 else []) + upcoming
    kept.sort(key=lambda e: (e["start"], not e["allDay"], e["title"]))
    return kept


def listing(saved=None):
    saved = read_saved() if saved is None else saved
    return {"ok": True, "calendars": [{"id": c["id"], "name": c.get("name") or "Calendar", "where": where(c["source"])} for c in saved]}


def add(source, name="", path=None, fetcher=fetch, now=None):
    now = time.time() if now is None else now
    kind, value = clean_source(source)
    if not kind:
        return {"ok": False, "error": "That isn't a web address or a file on this computer"}
    saved = read_saved(path)
    if len(saved) >= MAX_CALENDARS:
        return {"ok": False, "error": "Up to %d calendars" % MAX_CALENDARS}
    if any(clean_source(c["source"])[1] == value for c in saved):
        return {"ok": False, "error": "That calendar is already on the tile"}
    try:
        text = read_local(value) if kind == "path" else fetcher(value)
        title, events = parse_calendar(text)
    except CalendarError as error:
        place = urlsplit(value).netloc if kind == "url" else value
        return {"ok": False, "error": "%s %s" % (place, error)}
    calendar = {
        "id": secrets.token_hex(6),
        "name": one_line(name, 40) or title or (urlsplit(value).netloc if kind == "url" else os.path.basename(value.rstrip("/"))),
        "source": value,
    }
    write_saved(saved + [calendar], path)
    return {"ok": True, "calendar": {"id": calendar["id"], "name": calendar["name"], "where": where(value)}, "events": len(events)}


def remove(calendar_id, path=None, folder=None):
    saved = read_saved(path)
    keep = [c for c in saved if c["id"] != calendar_id]
    if len(keep) == len(saved):
        return {"ok": False}
    write_saved(keep, path)
    try:
        os.remove(cache_file(calendar_id, folder))
    except OSError:
        pass
    return {"ok": True}


def main(argv):
    args = argv[1:]
    if "--list" in args:
        payload = listing()
    elif "--add" in args:
        payload = add(os.environ.get(URL_ENV, ""), os.environ.get(NAME_ENV, ""))
    elif "--remove" in args:
        index = args.index("--remove")
        payload = remove(args[index + 1] if index + 1 < len(args) else "")
    else:
        payload = collect()
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
