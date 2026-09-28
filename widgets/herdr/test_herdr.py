import io
import json
import os
import subprocess
import sys
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

import herdr
import sample

KC = "w1"


def agent(agent_name, status, pane="w1:p1", tab="w1:t1", workspace=KC,
          title="", focused=False, cwd="", seq=1, revision=1):
    row = {
        "agent": agent_name,
        "agent_status": status,
        "cwd": cwd or "/home/ande/Projects/" + (agent_name or "pane"),
        "focused": focused,
        "foreground_cwd": cwd or "/home/ande/Projects/" + (agent_name or "pane"),
        "pane_id": pane,
        "revision": revision,
        "state_change_seq": seq,
        "tab_id": tab,
        "terminal_id": "term_" + (agent_name or "x"),
        "terminal_title": title or ((agent_name or "pane") + " is running"),
        "terminal_title_stripped": title or ((agent_name or "pane") + " is running"),
        "workspace_id": workspace,
    }
    return row


def snapshot(agents=None, workspaces=None, tabs=None, version="0.8.2"):
    return {
        "version": version,
        "protocol": 20,
        "agents": agents if agents is not None else [],
        "workspaces": workspaces if workspaces is not None else [
            {"workspace_id": "w1", "number": 1, "label": "omarchy-launcher",
             "focused": True, "pane_count": 4, "tab_count": 2,
             "active_tab_id": "w1:t1", "agent_status": "working"}],
        "tabs": tabs if tabs is not None else [
            {"tab_id": "w1:t1", "workspace_id": "w1", "number": 1, "label": "1",
             "focused": True, "pane_count": 2, "agent_status": "working"},
            {"tab_id": "w1:t2", "workspace_id": "w1", "number": 2, "label": "2",
             "focused": False, "pane_count": 2, "agent_status": "idle"}],
        "panes": [],
        "layouts": [],
        "focused_pane_id": "w1:p1",
        "focused_tab_id": "w1:t1",
        "focused_workspace_id": "w1",
    }


def envelope(snap):
    return {"id": "cli:api:snapshot", "type": "session_snapshot",
            "result": {"snapshot": snap}}


THREE = snapshot(agents=[
    agent("grok", "idle", pane="w1:p1", tab="w1:t1", title="MLB launcher widget"),
    agent("muse", "working", pane="w1:p2", tab="w1:t1", title="Push repo to GitHub"),
    agent("opencode", "idle", pane="w1:p4", tab="w1:t2", title="Refactor the parser",
          focused=True),
])


def fake_run(payload=None, error=None, raises=None):
    def run():
        if raises:
            raise raises
        if error:
            return {"id": "cli:api:snapshot",
                    "error": {"code": error[0], "message": error[1]}}
        return envelope(payload if payload is not None else THREE)
    return run


class Completed:
    """A subprocess result stand-in, so the runner can be tested directly."""

    def __init__(self, stdout="", stderr="", returncode=0):
        self.stdout = stdout
        self.stderr = stderr
        self.returncode = returncode


class AgentParsingTest(unittest.TestCase):
    def test_a_live_agent_becomes_a_row(self):
        parsed = herdr.parse_agent(agent(
            "opencode", "working", title="OC | Pushing current branch",
            focused=True, cwd="/home/ande/Projects/omarchy-launcher-weather", seq=251))
        self.assertEqual(parsed["name"], "opencode")
        self.assertEqual(parsed["status"], "working")
        self.assertEqual(parsed["title"], "OC | Pushing current branch")
        self.assertTrue(parsed["focused"])
        self.assertEqual(parsed["paneId"], "w1:p1")
        self.assertEqual(parsed["tabId"], "w1:t1")
        self.assertEqual(parsed["workspaceId"], "w1")
        self.assertEqual(parsed["seq"], 251)
        # A long path is shortened to the two segments that identify it.
        self.assertEqual(parsed["cwd"], "Projects/omarchy-launcher-weather")

    def test_every_documented_status_is_kept(self):
        for status in ("idle", "working", "blocked", "done", "unknown"):
            self.assertEqual(herdr.parse_agent(agent("x", status))["status"], status)

    def test_an_undocumented_status_becomes_unknown(self):
        self.assertEqual(herdr.normalize_status("thinking"), "unknown")
        self.assertEqual(herdr.normalize_status("WORKING"), "working")
        self.assertEqual(herdr.normalize_status(None), "unknown")
        self.assertEqual(herdr.normalize_status(7), "unknown")

    def test_a_path_shows_only_its_last_two_segments(self):
        home = os.path.expanduser("~")
        # The rule is uniform: the last two segments, whoever owns the path.
        self.assertEqual(herdr.home_name(home), "~")
        self.assertEqual(herdr.home_name(home + "/Projects/thing"), "Projects/thing")
        self.assertEqual(herdr.home_name("~/Projects/thing"), "Projects/thing")
        self.assertEqual(herdr.home_name("/home/other/Projects/thing"), "Projects/thing")
        self.assertEqual(herdr.home_name("/var/log"), "var/log")
        self.assertEqual(herdr.home_name("/"), "")
        self.assertEqual(herdr.home_name(""), "")
        self.assertEqual(herdr.home_name(None), "")

    def test_an_agent_with_no_title_falls_back_to_its_directory(self):
        raw = agent("grok", "idle", cwd="/home/ande/Projects/herdr")
        raw.pop("terminal_title")
        raw.pop("terminal_title_stripped")
        self.assertEqual(herdr.parse_agent(raw)["title"], "Projects/herdr")

    def test_a_display_name_beats_the_raw_id(self):
        raw = agent("grok", "idle")
        raw["display_agent"] = "Grok CLI"
        self.assertEqual(herdr.parse_agent(raw)["name"], "Grok CLI")
        # An agent herdr has not identified still gets a row.
        raw = {"agent_status": "unknown", "pane_id": "w1:p9",
               "terminal_title": "ande@host:~/code"}
        parsed = herdr.parse_agent(raw)
        self.assertEqual(parsed["name"], "")
        self.assertEqual(parsed["title"], "ande@host:~/code")

    def test_junk_agents_are_dropped(self):
        for raw in (None, 7, "x", [], {}, {"agent_status": "idle"}):
            self.assertIsNone(herdr.parse_agent(raw))

    def test_a_snapshot_with_no_agents_reads_as_empty(self):
        self.assertEqual(herdr.parse_agents({}), [])
        self.assertEqual(herdr.parse_agents({"agents": None}), [])
        self.assertEqual(herdr.parse_agents(None), [])
        self.assertEqual(len(herdr.parse_agents(THREE)), 3)


class SortAndCountTest(unittest.TestCase):
    def test_blocked_comes_first_then_working(self):
        rows = herdr.parse_agents(snapshot(agents=[
            agent("a", "done", pane="w1:p1"),
            agent("b", "idle", pane="w1:p2"),
            agent("c", "working", pane="w1:p3"),
            agent("d", "blocked", pane="w1:p4"),
        ]))
        ordered = [a["name"] for a in herdr.sort_agents(rows)]
        self.assertEqual(ordered, ["d", "c", "b", "a"])

    def test_the_focused_pane_leads_within_a_status(self):
        rows = herdr.parse_agents(snapshot(agents=[
            agent("a", "idle", pane="w1:p1", seq=9),
            agent("b", "idle", pane="w1:p2", seq=5, focused=True),
        ]))
        ordered = [a["name"] for a in herdr.sort_agents(rows)]
        self.assertEqual(ordered, ["b", "a"])

    def test_counts_include_every_status(self):
        rows = herdr.parse_agents(snapshot(agents=[
            agent("a", "working", pane="w1:p1"),
            agent("b", "working", pane="w1:p2"),
            agent("c", "idle", pane="w1:p3"),
        ]))
        counts = herdr.count_statuses(rows)
        self.assertEqual(counts["working"], 2)
        self.assertEqual(counts["idle"], 1)
        self.assertEqual(counts["blocked"], 0)
        self.assertEqual(counts["done"], 0)
        self.assertEqual(set(counts), set(herdr.STATUSES))
        self.assertEqual(len(herdr.busy(rows)), 2)

    def test_sorting_is_stable_between_polls(self):
        rows = herdr.parse_agents(THREE)
        first = [a["paneId"] for a in herdr.sort_agents(rows)]
        again = [a["paneId"] for a in herdr.sort_agents(list(reversed(rows)))]
        self.assertEqual(first, again)


class SectionTest(unittest.TestCase):
    def test_a_section_id_splits_into_whole_ids(self):
        # A tab is matched by its own full id, not by the tail after the colon.
        tab = herdr.section_of("w1:t2")
        self.assertEqual(tab["workspace"], "w1")
        self.assertEqual(tab["tab"], "w1:t2")
        self.assertEqual(herdr.section_of("w1")["workspace"], "w1")
        self.assertEqual(herdr.section_of("")["id"], "")
        self.assertEqual(herdr.section_of(None)["id"], "")

    def test_agents_are_matched_against_their_own_section(self):
        rows = herdr.parse_agents(THREE)
        self.assertEqual(len([a for a in rows if herdr.in_section(a, herdr.section_of(""))]), 3)
        self.assertEqual(len([a for a in rows if herdr.in_section(a, herdr.section_of("w1"))]), 3)
        in_t1 = [a["name"] for a in rows if herdr.in_section(a, herdr.section_of("w1:t1"))]
        self.assertEqual(sorted(in_t1), ["grok", "muse"])
        in_t2 = [a["name"] for a in rows if herdr.in_section(a, herdr.section_of("w1:t2"))]
        self.assertEqual(in_t2, ["opencode"])
        # An unknown section matches nothing rather than everything.
        self.assertEqual([a for a in rows if herdr.in_section(a, herdr.section_of("w9"))], [])

    def test_the_scoped_list_hides_what_is_outside_it(self):
        view = herdr.build(THREE, "w1:t2")
        self.assertEqual(view["total"], 1)
        self.assertEqual(view["agents"][0]["name"], "opencode")
        self.assertEqual(view["hidden"], 2)
        self.assertEqual(view["scopedCounts"]["idle"], 1)
        # The header still knows the whole session, not just the section.
        self.assertEqual(view["counts"]["working"], 1)
        self.assertEqual(view["counts"]["idle"], 2)

    def test_busy_only_keeps_what_needs_a_person(self):
        view = herdr.build(THREE, herdr.ALL, busy_only=True)
        self.assertEqual([a["name"] for a in view["agents"]], ["muse"])
        self.assertTrue(view["busyOnly"])

    def test_sections_list_every_workspace_and_tab(self):
        rows = herdr.sections(THREE)
        self.assertEqual(rows[0]["id"], "")
        self.assertEqual(rows[0]["kind"], "all")
        self.assertEqual(rows[0]["count"], 3)
        self.assertEqual(rows[1]["id"], "w1")
        self.assertEqual(rows[1]["kind"], "workspace")
        self.assertEqual(rows[1]["label"], "1 omarchy-launcher")
        self.assertEqual(rows[1]["count"], 3)
        self.assertEqual([r["id"] for r in rows[2:]], ["w1:t1", "w1:t2"])
        self.assertEqual(rows[2]["kind"], "tab")
        self.assertEqual(rows[2]["label"], "tab 1")
        self.assertEqual(rows[2]["detail"], "omarchy-launcher")
        self.assertEqual(rows[2]["count"], 2)
        self.assertEqual(rows[3]["count"], 1)
        for row in rows:
            self.assertIsInstance(row["count"], int)

    def test_sections_survive_a_session_with_no_workspaces(self):
        rows = herdr.sections(snapshot(agents=[], workspaces=[], tabs=[]))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], "")
        self.assertEqual(herdr.sections({})[0]["id"], "")
        self.assertEqual(herdr.sections(None)[0]["id"], "")

    def test_sections_span_several_workspaces(self):
        snap = snapshot(
            agents=[agent("a", "idle", pane="w2:p1", tab="w2:t1", workspace="w2")],
            workspaces=[
                {"workspace_id": "w1", "number": 1, "label": "alpha", "focused": True,
                 "pane_count": 1, "tab_count": 1, "active_tab_id": "w1:t1",
                 "agent_status": "idle"},
                {"workspace_id": "w2", "number": 2, "label": "beta", "focused": False,
                 "pane_count": 1, "tab_count": 1, "active_tab_id": "w2:t1",
                 "agent_status": "idle"}],
            tabs=[{"tab_id": "w1:t1", "workspace_id": "w1", "number": 1, "label": "1",
                   "focused": True, "pane_count": 1, "agent_status": "idle"}])
        rows = herdr.sections(snap)
        self.assertEqual([r["id"] for r in rows], ["", "w1", "w1:t1", "w2"])
        self.assertEqual(rows[3]["count"], 1)
        view = herdr.build(snap, "w2")
        self.assertEqual([a["name"] for a in view["agents"]], ["a"])

    def test_a_label_is_found_or_the_raw_id_is_shown(self):
        self.assertEqual(herdr.section_label(THREE, ""), "All sections")
        self.assertEqual(herdr.section_label(THREE, "w1"), "1 omarchy-launcher")
        self.assertEqual(herdr.section_label(THREE, "w1:t2"), "tab 2")
        # A section that no longer exists shows its id rather than nothing.
        self.assertEqual(herdr.section_label(THREE, "w9"), "w9")

    def test_a_workspace_with_no_label_still_gets_a_name(self):
        snap = snapshot(workspaces=[
            {"workspace_id": "w3", "number": 3, "label": "", "focused": False,
             "pane_count": 0, "tab_count": 0, "active_tab_id": "", "agent_status": "idle"}],
            tabs=[])
        self.assertEqual(herdr.sections(snap)[1]["label"], "3 workspace 3")


class ViewTest(unittest.TestCase):
    def test_a_live_session_polls_fast(self):
        view = herdr.build(THREE)
        self.assertTrue(view["ok"])
        self.assertEqual(view["total"], 3)
        self.assertEqual(view["pollMs"], herdr.POLL_BUSY_MS)
        self.assertEqual(view["banner"], "HERDR")
        self.assertEqual(view["version"], "0.8.2")
        # The agents sort to the front by urgency.
        self.assertEqual(view["agents"][0]["name"], "muse")
        self.assertEqual(view["focus"]["name"], "opencode")

    def test_a_quiet_session_polls_slowly(self):
        quiet = snapshot(agents=[agent("a", "idle", pane="w1:p1")])
        self.assertEqual(herdr.build(quiet)["pollMs"], herdr.POLL_IDLE_MS)

    def test_an_empty_session_polls_slowest(self):
        view = herdr.build(snapshot(agents=[]))
        self.assertEqual(view["total"], 0)
        self.assertEqual(view["agents"], [])
        self.assertIsNone(view["focus"])
        self.assertEqual(view["pollMs"], herdr.POLL_OFF_MS)

    def test_a_blocked_agent_polls_fast_even_alone(self):
        blocked = snapshot(agents=[agent("a", "blocked", pane="w1:p1")])
        self.assertEqual(herdr.build(blocked)["pollMs"], herdr.POLL_BUSY_MS)

    def test_the_focus_falls_back_to_the_first_row(self):
        unfocused = snapshot(agents=[agent("a", "idle", pane="w1:p1")])
        self.assertEqual(herdr.build(unfocused)["focus"]["name"], "a")

    def test_junk_snapshots_do_not_raise(self):
        for snap in ({}, {"agents": []}, {"agents": None}, {"agents": [None, 7, {}]},
                      {"workspaces": 7, "tabs": "x"}):
            view = herdr.build(snap)
            self.assertTrue(view["ok"])
            self.assertEqual(view["agents"], [])
        # Something that is not a snapshot at all is an error, and says so.
        for snap in ([], "x", 7, None):
            self.assertFalse(herdr.build(snap)["ok"])

    def test_every_view_carries_the_full_status_key_set(self):
        view = herdr.build(THREE)
        for key in ("counts", "scopedCounts"):
            self.assertEqual(set(view[key]), set(herdr.STATUSES))
            self.assertEqual(sum(view[key].values()), 3)
        for key in ("ok", "banner", "error", "pollMs", "agents", "total", "hidden",
                    "counts", "scopedCounts", "focus", "moving", "section",
                    "sectionLabel", "busyOnly", "version", "workspaces"):
            self.assertIn(key, view)


class EnvelopeTest(unittest.TestCase):
    def test_the_snapshot_comes_out_of_the_envelope(self):
        self.assertIs(herdr.snapshot_of(envelope(THREE)), THREE)
        # `herdr agent list` answers with the agents array directly.
        listed = {"result": {"agents": THREE["agents"]}}
        self.assertEqual(herdr.snapshot_of(listed)["agents"], THREE["agents"])
        self.assertIsNone(herdr.snapshot_of({}))
        self.assertIsNone(herdr.snapshot_of(None))
        self.assertIsNone(herdr.snapshot_of({"result": 7}))

    def test_an_error_envelope_is_read_not_guessed_at(self):
        reply = {"id": "cli:api:snapshot",
                 "error": {"code": "server_not_running",
                           "message": "no herdr server is running"}}
        self.assertEqual(herdr.envelope_error(reply), "server_not_running: no herdr server is running")
        self.assertEqual(herdr.envelope_error({}), "")
        self.assertEqual(herdr.envelope_error({"error": 7}), "")
        self.assertEqual(herdr.envelope_error({"error": {}}), "")

    def test_a_code_already_inside_the_message_is_not_repeated(self):
        reply = {"error": {"code": "server_not_running", "message": "server_not_running here"}}
        self.assertEqual(herdr.envelope_error(reply), "server_not_running here")


class RunnerTest(unittest.TestCase):
    def test_only_the_snapshot_command_is_allowed(self):
        self.assertEqual(herdr.allowed_command(["/usr/bin/herdr", "api", "snapshot"]),
                         ["/usr/bin/herdr", "api", "snapshot"])
        for args in (["/usr/bin/herdr"], ["herdr", "api", "snapshot"],
                     ["/usr/bin/herdr", "agent", "list"],
                     ["/usr/bin/herdr", "api", "schema"],
                     ["/bin/sh", "api", "snapshot"],
                     ["/usr/bin/herdr", "api", "snapshot", "--evil"],
                     [], None, "herdr api snapshot"):
            self.assertIsNone(herdr.allowed_command(args))

    def test_the_runner_passes_the_real_command(self):
        seen = {}

        def runner(command, **kwargs):
            seen["command"] = command
            seen["kwargs"] = kwargs
            return Completed(stdout=json.dumps(envelope(THREE)))

        payload = herdr.run_herdr(runner=runner)
        self.assertEqual(seen["command"], ["/usr/bin/herdr", "api", "snapshot"])
        self.assertTrue(seen["kwargs"]["capture_output"])
        self.assertIn("timeout", seen["kwargs"])
        self.assertEqual(herdr.snapshot_of(payload), THREE)

    def test_silence_becomes_a_readable_error(self):
        with self.assertRaises(OSError) as caught:
            herdr.run_herdr(runner=lambda *a, **k: Completed(stdout="", stderr=""))
        self.assertIn("No herdr server", str(caught.exception))

    def test_stderr_is_preferred_when_there_is_no_output(self):
        with self.assertRaises(OSError) as caught:
            herdr.run_herdr(runner=lambda *a, **k: Completed(stdout=" ", stderr="not found"))
        self.assertIn("not found", str(caught.exception))

    def test_non_json_becomes_an_error(self):
        with self.assertRaises(OSError):
            herdr.run_herdr(runner=lambda *a, **k: Completed(stdout="usage: herdr"))
        with self.assertRaises(OSError):
            herdr.run_herdr(runner=lambda *a, **k: Completed(stdout="[1, 2, 3]"))

    def test_an_oversized_reply_is_refused(self):
        blob = json.dumps({"result": {"snapshot": snapshot()}}) + " " * herdr.MAX_BYTES
        with self.assertRaises(OSError):
            herdr.run_herdr(runner=lambda *a, **k: Completed(stdout=blob))

    def test_a_missing_binary_and_a_hang_are_both_errors(self):
        def missing(*a, **k):
            raise FileNotFoundError("/usr/bin/herdr")
        with self.assertRaises(OSError) as caught:
            herdr.run_herdr(runner=missing)
        self.assertIn("not installed", str(caught.exception))

        def slow(*a, **k):
            raise subprocess.TimeoutExpired("herdr", 8)
        with self.assertRaises(OSError) as caught:
            herdr.run_herdr(runner=slow)
        self.assertIn("in time", str(caught.exception))

        def denied(*a, **k):
            raise PermissionError("nope")
        with self.assertRaises(OSError):
            herdr.run_herdr(runner=denied)

    def test_a_working_session_is_read_for_real(self):
        # The one test that touches the running server, and only reads.
        payload = herdr.run_herdr()
        snap = herdr.snapshot_of(payload)
        self.assertIsNotNone(snap)
        self.assertIn("agents", snap)
        self.assertEqual(herdr.envelope_error(payload), "")


class CollectTest(unittest.TestCase):
    def test_a_live_session_becomes_a_payload(self):
        view = herdr.collect(run=fake_run())
        self.assertTrue(view["ok"])
        self.assertEqual(view["total"], 3)
        self.assertEqual(view["section"], "")

    def test_the_section_and_the_busy_flag_reach_the_payload(self):
        # Tab 1 holds the working agent, so narrowing to it and keeping only
        # what is moving leaves exactly that one row.
        view = herdr.collect("w1:t1", True, run=fake_run())
        self.assertEqual(view["section"], "w1:t1")
        self.assertEqual(view["total"], 1)
        self.assertEqual(view["agents"][0]["name"], "muse")
        self.assertTrue(view["busyOnly"])
        # The same tab without the filter keeps its idle agent too.
        self.assertEqual(herdr.collect("w1:t1", run=fake_run())["total"], 2)
        # A tab whose only agent is idle drops out entirely under the filter.
        self.assertEqual(herdr.collect("w1:t2", True, run=fake_run())["total"], 0)

    def test_a_stopped_server_is_drawn_not_raised(self):
        view = herdr.collect(run=fake_run(error=("server_not_running", "no herdr server is running")))
        self.assertFalse(view["ok"])
        self.assertIn("no herdr server", view["error"])
        self.assertEqual(view["agents"], [])
        self.assertEqual(view["pollMs"], herdr.POLL_OFF_MS)
        self.assertEqual(set(view["counts"]), set(herdr.STATUSES))
        # Everything the tile reads still exists, so nothing has to guard.
        self.assertEqual(view["sectionLabel"], "All sections")
        self.assertEqual(view["banner"], "HERDR")

    def test_a_dead_binary_is_drawn_not_raised(self):
        for raised in (OSError("offline"), RuntimeError("boom"), ValueError("bad")):
            view = herdr.collect(run=fake_run(raises=raised))
            self.assertFalse(view["ok"])
            self.assertTrue(view["error"])
            self.assertEqual(view["total"], 0)

    def test_an_unexpected_envelope_is_drawn_not_raised(self):
        for reply in ({}, {"result": 7}, [1, 2], {"result": {"snapshot": 7}}):
            view = herdr.collect(run=lambda r=reply: r)
            self.assertFalse(view["ok"])
            self.assertTrue(view["error"])

    def test_the_section_catalog_falls_back_when_herdr_is_away(self):
        rows = herdr.catalog(run=fake_run())
        self.assertEqual(rows[0]["id"], "")
        self.assertTrue(rows[0]["count"])
        for run in (fake_run(raises=OSError("offline")), fake_run(raises=RuntimeError()),
                    fake_run(error=("server_not_running", "gone")),
                    fake_run(payload=snapshot(agents=[], workspaces=[], tabs=[]))):
            rows = herdr.catalog(run=run)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["id"], "")
            self.assertEqual(rows[0]["count"], 0)

    def test_the_shipped_section_catalog_is_readable_right_now(self):
        # The one test that talks to the live session through the shipped path.
        rows = herdr.catalog()
        self.assertTrue(rows)
        self.assertEqual(rows[0]["id"], "")
        for row in rows[1:]:
            self.assertTrue(row["id"])
            self.assertIn(row["kind"], ("workspace", "tab"))


class SampleTest(unittest.TestCase):
    def test_sample_passes_the_section_through(self):
        output = io.StringIO()
        with patch("sample.herdr.collect", return_value={"ok": True}) as collect:
            with redirect_stdout(output):
                result = sample.main(["sample.py", "--section", "w1:t2"])
        self.assertEqual(result, 0)
        collect.assert_called_once_with("w1:t2", False)
        self.assertTrue(json.loads(output.getvalue())["ok"])

    def test_sample_reports_the_busy_flag(self):
        with patch("sample.herdr.collect", return_value={"ok": True}) as collect:
            with redirect_stdout(io.StringIO()):
                sample.main(["sample.py", "--busy"])
        self.assertEqual(collect.call_args[0][1], True)

    def test_sample_serves_the_section_catalog(self):
        output = io.StringIO()
        with patch("sample.herdr.catalog", return_value=[{"id": "", "count": 0}]) as catalog:
            with redirect_stdout(output):
                result = sample.main(["sample.py", "--sections"])
        self.assertEqual(result, 0)
        catalog.assert_called_once()
        self.assertEqual(len(json.loads(output.getvalue())["rows"]), 1)

    def test_sample_survives_a_raising_collector(self):
        output = io.StringIO()
        with patch("sample.herdr.collect", side_effect=RuntimeError("no route")):
            with redirect_stdout(output):
                result = sample.main(["sample.py"])
        self.assertEqual(result, 0)
        payload = json.loads(output.getvalue())
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error"], "no route")


class CatalogWiringTest(unittest.TestCase):
    def test_the_launcher_finds_this_widget(self):
        here = os.path.dirname(os.path.abspath(__file__))
        widgets = os.path.dirname(here)
        script = os.path.join(os.path.dirname(widgets), "scripts", "list-widgets.py")
        rows = subprocess.run([sys.executable, script, widgets],
                              capture_output=True, text=True, timeout=30, check=True).stdout
        found = {row["id"]: row for row in json.loads(rows)}
        self.assertIn("herdr", found)
        row = found["herdr"]
        self.assertTrue(row["qml"].endswith("/widgets/herdr/Widget.qml"))
        self.assertTrue(row["settingsQml"].endswith("/widgets/herdr/Settings.qml"))
        self.assertTrue(os.path.isfile(row["qml"]))
        self.assertTrue(os.path.isfile(row["settingsQml"]))
        self.assertEqual(row["name"], "Herdr")
        self.assertEqual(row["defaultCommand"], "herdr")
        self.assertTrue(row["defaultLabel"])
        self.assertTrue(row["icon"])
        self.assertTrue(row["description"])


if __name__ == "__main__":
    unittest.main()
