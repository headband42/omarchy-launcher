#!/usr/bin/env python3
"""Tests for the calendar sampler. Stdlib only; nothing here reaches the network
or touches the real calendar list.

Run from the repo root:  python3 widgets/agenda/test_agenda.py
"""

import json
import os
import stat
import sys
import tempfile
import unittest
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import agenda

DENVER = ZoneInfo("America/Denver")


def ics(*events, name="Work"):
    body = "\r\n".join(["BEGIN:VCALENDAR", "VERSION:2.0", "X-WR-CALNAME:" + name] + list(events) + ["END:VCALENDAR"])
    return body


def vevent(*lines):
    return "\r\n".join(["BEGIN:VEVENT"] + list(lines) + ["END:VEVENT"])


def window(start, days):
    begin = datetime(start.year, start.month, start.day, tzinfo=DENVER)
    return begin.astimezone(timezone.utc), (begin + timedelta(days=days)).astimezone(timezone.utc)


def instances(text, start=date(2026, 10, 1), days=30, zone=DENVER):
    _, events = agenda.parse_calendar(text)
    begin, end = window(start, days)
    return agenda.expand(events, begin, end, zone)


def local(sec, zone=DENVER):
    return datetime.fromtimestamp(sec, zone)


class ReadTests(unittest.TestCase):
    def test_unfold_and_unescape(self):
        text = ics(vevent(
            "UID:1",
            "DTSTART:20261005T150000Z",
            "SUMMARY:Planning\\, part one\\;",
            " and two",
            "LOCATION:Room 4\\nFloor 2",
        ))
        name, events = agenda.parse_calendar(text)
        self.assertEqual(name, "Work")
        self.assertEqual(agenda.one_line(agenda.first(events[0], "SUMMARY")[1]), "Planning, part one;and two")
        self.assertEqual(agenda.one_line(agenda.first(events[0], "LOCATION")[1]), "Room 4 Floor 2")

    def test_params_with_quoted_colons(self):
        key, params, value = agenda.split_property('ATTENDEE;CN="Doe: Jane";ROLE=CHAIR:mailto:jane@example.com')
        self.assertEqual((key, params["CN"], params["ROLE"], value), ("ATTENDEE", "Doe: Jane", "CHAIR", "mailto:jane@example.com"))

    def test_alarm_properties_stay_out_of_the_event(self):
        text = ics(vevent("UID:1", "DTSTART:20261005T150000Z", "SUMMARY:Real", "BEGIN:VALARM", "SUMMARY:Alarm", "END:VALARM"))
        _, events = agenda.parse_calendar(text)
        self.assertEqual([v for _, v in events[0]["SUMMARY"]], ["Real"])

    def test_not_a_calendar(self):
        with self.assertRaises(agenda.CalendarError):
            agenda.parse_calendar("<html><body>Sign in</body></html>")

    def test_dates(self):
        self.assertEqual(agenda.parse_dt("20261005", {}, DENVER), (date(2026, 10, 5), True))
        self.assertEqual(agenda.parse_dt("20261005T090000Z", {}, DENVER)[0], datetime(2026, 10, 5, 9, tzinfo=timezone.utc))
        when, _ = agenda.parse_dt("20261005T090000", {"TZID": "Pacific Standard Time"}, DENVER)
        self.assertEqual(when.utcoffset(), timedelta(hours=-7))
        floating, _ = agenda.parse_dt("20261005T090000", {}, DENVER)
        self.assertEqual(floating.tzinfo, DENVER)
        with self.assertRaises(ValueError):
            agenda.parse_dt("tomorrow", {}, DENVER)

    def test_zone_names(self):
        self.assertEqual(str(agenda.zone_for("Europe/Berlin", DENVER)), "Europe/Berlin")
        self.assertEqual(str(agenda.zone_for("W. Europe Standard Time", DENVER)), "Europe/Berlin")
        self.assertEqual(str(agenda.zone_for("/mozilla.org/20050126_1/America/New_York", DENVER)), "America/New_York")
        self.assertEqual(str(agenda.zone_for("(UTC-05:00) America/Chicago custom", DENVER)), "America/Chicago")
        self.assertIs(agenda.zone_for("Nowhere Standard Time", DENVER), DENVER)

    def test_durations(self):
        self.assertEqual(agenda.parse_duration("PT1H30M"), timedelta(hours=1, minutes=30))
        self.assertEqual(agenda.parse_duration("P1W"), timedelta(weeks=1))
        self.assertEqual(agenda.parse_duration("P1DT2H"), timedelta(days=1, hours=2))
        self.assertIsNone(agenda.parse_duration("an hour"))


class RecurrenceTests(unittest.TestCase):
    def test_weekly_keeps_wall_time_across_dst(self):
        text = ics(vevent("UID:w", "DTSTART;TZID=America/Denver:20261026T090000", "DTEND;TZID=America/Denver:20261026T093000",
                          "RRULE:FREQ=WEEKLY;BYDAY=MO", "SUMMARY:Standup"))
        out = instances(text, date(2026, 10, 25), 21)
        self.assertEqual([local(e["start"]).strftime("%m-%d %H:%M") for e in out], ["10-26 09:00", "11-02 09:00", "11-09 09:00"])
        self.assertEqual(out[1]["end"] - out[1]["start"], 1800)

    def test_monthly_last_friday_and_count(self):
        text = ics(vevent("UID:m", "DTSTART;TZID=America/Denver:20260130T160000", "DURATION:PT1H",
                          "RRULE:FREQ=MONTHLY;BYDAY=-1FR;COUNT=12", "SUMMARY:Demo"))
        out = instances(text, date(2026, 10, 1), 92)
        self.assertEqual([local(e["start"]).strftime("%m-%d") for e in out], ["10-30", "11-27", "12-25"])

    def test_until_ends_the_series(self):
        text = ics(vevent("UID:u", "DTSTART:20261001T150000Z", "RRULE:FREQ=DAILY;UNTIL=20261003T150000Z", "SUMMARY:Short"))
        self.assertEqual(len(instances(text)), 3)

    def test_exdate_rdate_and_moved_instance(self):
        text = ics(
            vevent("UID:s", "DTSTART;TZID=America/Denver:20261005T100000", "DTEND;TZID=America/Denver:20261005T110000",
                   "RRULE:FREQ=DAILY;COUNT=5", "EXDATE;TZID=America/Denver:20261006T100000",
                   "RDATE;TZID=America/Denver:20261020T100000", "SUMMARY:Series"),
            vevent("UID:s", "RECURRENCE-ID;TZID=America/Denver:20261007T100000",
                   "DTSTART;TZID=America/Denver:20261007T150000", "DTEND;TZID=America/Denver:20261007T160000", "SUMMARY:Moved"),
            vevent("UID:s", "RECURRENCE-ID;TZID=America/Denver:20261008T100000",
                   "DTSTART;TZID=America/Denver:20261008T100000", "STATUS:CANCELLED", "SUMMARY:Cancelled"),
        )
        out = instances(text)
        self.assertEqual([(local(e["start"]).strftime("%d %H"), e["title"]) for e in out],
                         [("05 10", "Series"), ("07 15", "Moved"), ("09 10", "Series"), ("20 10", "Series")])

    def test_date_only_exdate_removes_a_timed_instance(self):
        text = ics(vevent("UID:d", "DTSTART;TZID=America/Denver:20261005T100000", "RRULE:FREQ=DAILY;COUNT=3",
                          "EXDATE;VALUE=DATE:20261006", "SUMMARY:x"))
        self.assertEqual([local(e["start"]).day for e in instances(text)], [5, 7])

    def test_all_day_and_multi_day(self):
        text = ics(
            vevent("UID:a", "DTSTART;VALUE=DATE:20261010", "DTEND;VALUE=DATE:20261013", "SUMMARY:Trip"),
            vevent("UID:b", "DTSTART;VALUE=DATE:20261015", "SUMMARY:One day"),
            vevent("UID:c", "DTSTART;VALUE=DATE:19900312", "RRULE:FREQ=YEARLY", "SUMMARY:Birthday"),
        )
        out = instances(text, date(2026, 10, 1), 200)
        by = {e["title"]: e for e in out}
        self.assertTrue(by["Trip"]["allDay"])
        self.assertEqual(by["Trip"]["end"] - by["Trip"]["start"], 3 * 86400)
        self.assertEqual(by["One day"]["end"] - by["One day"]["start"], 86400)
        self.assertEqual(local(by["Birthday"]["start"]).strftime("%Y-%m-%d"), "2027-03-12")

    def test_ongoing_event_from_before_the_window_is_kept(self):
        text = ics(vevent("UID:o", "DTSTART;VALUE=DATE:20260920", "DTEND;VALUE=DATE:20261010", "SUMMARY:Sabbatical"))
        self.assertEqual(len(instances(text, date(2026, 10, 1), 3)), 1)

    def test_an_orphaned_moved_instance_still_shows(self):
        text = ics(vevent("UID:gone", "RECURRENCE-ID:20261005T150000Z", "DTSTART:20261005T170000Z", "SUMMARY:Lonely"))
        self.assertEqual([e["title"] for e in instances(text)], ["Lonely"])

    def test_events_with_the_same_uid_and_no_rule_are_both_kept(self):
        text = ics(vevent("UID:dup", "DTSTART:20261005T150000Z", "SUMMARY:A"), vevent("UID:dup", "DTSTART:20261006T150000Z", "SUMMARY:B"))
        self.assertEqual([e["title"] for e in instances(text)], ["A", "B"])

    def test_unbounded_daily_rule_stops_at_the_window(self):
        text = ics(vevent("UID:forever", "DTSTART:20000101T150000Z", "RRULE:FREQ=DAILY", "SUMMARY:Daily"))
        self.assertEqual(len(instances(text, date(2026, 10, 1), 10)), 10)

    def test_occurrences_by_rule(self):
        def run(start, rule, limit=date(2030, 1, 1), n=8):
            return list(agenda.occurrences(start, agenda.parse_rrule(rule), limit))[:n]
        self.assertEqual(run(date(2026, 1, 31), "FREQ=MONTHLY;COUNT=4"),
                         [date(2026, 1, 31), date(2026, 3, 31), date(2026, 5, 31), date(2026, 7, 31)])
        self.assertEqual(run(date(2026, 11, 1), "FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=3"),
                         [date(2026, 11, 26), date(2027, 11, 25), date(2028, 11, 23)])
        self.assertEqual(run(date(2026, 10, 1), "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3"),
                         [date(2026, 10, 30), date(2026, 11, 30), date(2026, 12, 31)])
        self.assertEqual(run(date(2024, 2, 29), "FREQ=YEARLY;COUNT=2"), [date(2024, 2, 29), date(2028, 2, 29)])
        self.assertEqual(run(date(2026, 10, 1), "FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;COUNT=4"),
                         [date(2026, 10, 1), date(2026, 10, 13), date(2026, 10, 15), date(2026, 10, 27)])
        self.assertEqual(run(date(2026, 10, 1), "FREQ=SECONDLY"), [date(2026, 10, 1)])


class MeetingTests(unittest.TestCase):
    def test_meeting_links(self):
        event = {"DESCRIPTION": [({}, "Join: https://us02web.zoom.us/j/123?pwd=abc.\\nThanks")]}
        self.assertEqual(agenda.meeting_link(event), "https://us02web.zoom.us/j/123?pwd=abc")
        event = {"LOCATION": [({}, "https://meet.google.com/abc-defg-hij")]}
        self.assertEqual(agenda.meeting_link(event), "https://meet.google.com/abc-defg-hij")
        event = {"X-MICROSOFT-SKYPETEAMSMEETINGURL": [({}, "https://teams.microsoft.com/l/meetup-join/19%3a")]}
        self.assertTrue(agenda.meeting_link(event).startswith("https://teams.microsoft.com/"))
        self.assertEqual(agenda.meeting_link({"URL": [({}, "https://example.com/event/1")]}), "https://example.com/event/1")
        self.assertEqual(agenda.meeting_link({"URL": [({}, "javascript:alert(1)")]}), "")
        self.assertEqual(agenda.meeting_link({}), "")


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "conf", "calendars.json")
        self.cache = os.path.join(self.dir.name, "cache")

    def tearDown(self):
        self.dir.cleanup()

    def test_clean_source(self):
        self.assertEqual(agenda.clean_source("webcal://p01-caldav.icloud.com/published/2/abc"), ("url", "https://p01-caldav.icloud.com/published/2/abc"))
        self.assertEqual(agenda.clean_source("calendar.google.com/calendar/ical/x/basic.ics")[0], "url")
        self.assertEqual(agenda.clean_source(self.dir.name), ("path", self.dir.name))
        for bad in ("", "/does/not/exist.ics", "ftp://x.org/a.ics", "https://u@x.org/a.ics", "https://x.org/a b.ics"):
            self.assertEqual(agenda.clean_source(bad), ("", ""), bad)

    def test_where_hides_the_secret(self):
        self.assertEqual(agenda.where("https://calendar.google.com/calendar/ical/me%40gmail.com/private-abc123/basic.ics"), "calendar.google.com/…")

    def test_add_list_remove_with_a_private_file(self):
        body = ics(vevent("UID:1", "DTSTART:20261005T150000Z", "SUMMARY:x"), name="Team")
        out = agenda.add("https://cal.example/team.ics", "", self.path, fetcher=lambda url: body)
        self.assertTrue(out["ok"])
        self.assertEqual(out["calendar"]["name"], "Team")
        self.assertEqual(out["events"], 1)
        self.assertEqual(stat.S_IMODE(os.stat(self.path).st_mode), 0o600)
        saved = agenda.read_saved(self.path)
        self.assertEqual(saved[0]["source"], "https://cal.example/team.ics")
        self.assertEqual(agenda.listing(saved)["calendars"], [{"id": saved[0]["id"], "name": "Team", "where": "cal.example/…"}])
        again = agenda.add("https://cal.example/team.ics", "", self.path, fetcher=lambda url: body)
        self.assertEqual(again["error"], "That calendar is already on the tile")
        self.assertEqual(agenda.remove(saved[0]["id"], self.path, self.cache), {"ok": True})
        self.assertEqual(agenda.read_saved(self.path), [])
        self.assertEqual(agenda.remove("nope", self.path, self.cache), {"ok": False})

    def test_add_refuses_a_page_that_is_not_a_calendar(self):
        out = agenda.add("https://example.com", "", self.path, fetcher=lambda url: "<html></html>")
        self.assertEqual(out, {"ok": False, "error": "example.com is not a calendar"})
        self.assertFalse(os.path.exists(self.path))

    def test_add_names_a_folder_after_itself(self):
        folder = os.path.join(self.dir.name, "personal")
        os.makedirs(folder)
        with open(os.path.join(folder, "a.ics"), "w") as handle:
            handle.write(ics(vevent("UID:1", "DTSTART:20261005T150000Z", "SUMMARY:x"), name=""))
        out = agenda.add(folder, "", self.path)
        self.assertEqual(out["calendar"]["name"], "personal")

    def test_web_calendars_are_cached_and_fall_back_when_down(self):
        calendar = {"id": "c1", "source": "https://cal.example/a.ics"}
        calls = []

        def fetch(url):
            calls.append(url)
            return "BEGIN:VCALENDAR\r\nEND:VCALENDAR"

        agenda.load_text(calendar, 1000, fetch, self.cache)
        agenda.load_text(calendar, 1000 + agenda.TTL - 1, fetch, self.cache)
        self.assertEqual(len(calls), 1)
        cached = agenda.cache_file("c1", self.cache)
        self.assertEqual(stat.S_IMODE(os.stat(cached).st_mode), 0o600)

        def down(url):
            raise agenda.CalendarError("did not answer")

        text, error = agenda.load_text(calendar, 1000 + agenda.TTL + 1, down, self.cache)
        self.assertEqual((text.startswith("BEGIN:VCALENDAR"), error), (True, "did not answer"))
        text, error = agenda.load_text(calendar, 1000 + agenda.STALE_MAX + 1, down, self.cache)
        self.assertEqual((text, error), ("", "did not answer"))


class CollectTests(unittest.TestCase):
    def test_collect_merges_calendars_and_tags_them(self):
        now = datetime(2026, 10, 2, 8, tzinfo=DENVER).timestamp()
        bodies = {
            "https://a.example/a.ics": ics(vevent("UID:1", "DTSTART;TZID=America/Denver:20261002T090000", "SUMMARY:Standup")),
            "https://b.example/b.ics": ics(vevent("UID:2", "DTSTART;VALUE=DATE:20261003", "SUMMARY:Holiday")),
        }
        saved = [{"id": "a", "name": "Work", "source": "https://a.example/a.ics"},
                 {"id": "b", "name": "Home", "source": "https://b.example/b.ics"},
                 {"id": "c", "name": "Dead", "source": "https://c.example/c.ics"}]

        def fetch(url):
            if url not in bodies:
                raise agenda.CalendarError("answered 404")
            return bodies[url]

        with tempfile.TemporaryDirectory() as folder:
            out = agenda.collect(now, saved, fetch, folder, DENVER)
        self.assertEqual([(e["title"], e["calendar"]) for e in out["events"]], [("Standup", 0), ("Holiday", 1)])
        self.assertEqual(out["calendars"][2], {"id": "c", "name": "Dead", "ok": False, "error": "answered 404"})

    def test_cap_keeps_what_is_coming(self):
        events = [{"start": i, "end": i + 1, "allDay": False, "title": str(i)} for i in range(10)]
        kept = agenda.cap(events, 6, limit=4)
        self.assertEqual([e["start"] for e in kept], [5, 6, 7, 8])
        self.assertEqual(agenda.cap(events, 0, limit=20), events)


if __name__ == "__main__":
    unittest.main()
