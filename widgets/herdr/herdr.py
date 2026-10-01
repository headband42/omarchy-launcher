"""Herdr tile model.

Herdr is a terminal workspace manager that watches panes and reports what the
coding agent in each one is doing. It runs a server on a socket and exposes
the live session over its CLI:

    herdr api snapshot     # the whole session as JSON
    herdr agent list       # just the agents array

The widget uses the snapshot, because the tile also needs to know which
workspace and tab an agent belongs to in order to scope itself to one.

The snapshot nests workspaces > tabs > panes > agents. An agent record is the
one that carries `agent_status`, and that enum is fixed by Herdr's schema:

    idle | working | blocked | done | unknown

`blocked` is the status a person cares about: the agent stopped because it
wants an answer. So the tile sorts it to the top and the header counts it
first.

Two details worth remembering:

  * Herdr reports failures inside the JSON, as
    `{"error": {"code": ..., "message": ...}}`, and still exits 0. A non-zero
    exit is not the failure signal here; the envelope is.
  * Nothing in this file reads a file or opens a socket. The caller injects
    `run`, which is what the tests replace.

The session is the current one: Herdr's client resolves the server on its own
socket, so no session name is passed.
"""

import json
import math
import os
import subprocess
import sys

HERDR = "/usr/bin/herdr"
MAX_BYTES = 2000000

# Herdr's AgentStatus enum, most urgent first. Anything it sends that is not
# in this list still lands, at the bottom, as "unknown".
STATUSES = ("blocked", "working", "done", "idle", "unknown")
STATUS_RANK = {name: index for index, name in enumerate(STATUSES)}

# Poll fast while something is moving and slowly when it is not. The command
# costs a couple of milliseconds, so this is cheap either way.
POLL_BUSY_MS = 3000
POLL_IDLE_MS = 10000
POLL_OFF_MS = 20000

ALL = ""


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


def home_name(path):
    """A working directory reduced to something a tile can show.

    A home directory becomes `~`, and only the last two segments of a real
    path survive, so `/home/ande/Projects/omarchy-launcher-weather` reads as
    `Projects/omarchy-launcher-weather` rather than filling the row.
    """
    value = text(path, 400)
    if not value:
        return ""
    home = text(_home(), 200)
    if home and (value == home or value.startswith(home.rstrip("/") + "/")):
        value = "~" + value[len(home.rstrip("/")):]
    if value.startswith("~/"):
        value = value[2:]
    parts = [part for part in value.split("/") if part]
    if not parts:
        return ""
    return "/".join(parts[-2:])


def _home():
    return os.path.expanduser("~")


def allowed_command(args):
    """Only the read-only snapshot call is ever run.

    The length is part of the allowlist, not an afterthought: a command with
    anything appended to it is not the command that was vetted here. The list
    is built from constants rather than from anything the user typed, but this
    process runs a binary, so the gate is kept.
    """
    if not isinstance(args, (list, tuple)) or len(args) != 3:
        return None
    if str(args[0]) != HERDR:
        return None
    if str(args[1]) != "api" or str(args[2]) != "snapshot":
        return None
    return [HERDR, "api", "snapshot"]


def run_herdr(timeout=8, runner=subprocess.run):
    """Ask the running server for its session. Returns the parsed envelope."""
    command = allowed_command([HERDR, "api", "snapshot"])
    if command is None:
        raise ValueError("Refusing an unexpected command")
    try:
        result = runner(command, capture_output=True, text=True,
                        timeout=timeout, check=False)
    except FileNotFoundError:
        raise OSError("herdr is not installed")
    except subprocess.TimeoutExpired:
        raise OSError("herdr did not answer in time")
    except OSError as error:
        raise OSError(text(error, 200) or "herdr could not be run")
    raw = result.stdout or ""
    if len(raw) > MAX_BYTES:
        raise OSError("Herdr returned more than expected")
    if not text(raw, 5):
        # The CLI writes usage to stderr when the subcommand is malformed,
        # and prints nothing at all when no server is reachable.
        detail = text(result.stderr, 200)
        raise OSError(detail or "No herdr server is answering")
    try:
        envelope = json.loads(raw)
    except ValueError:
        raise OSError("Herdr sent something that was not JSON")
    if not isinstance(envelope, dict):
        raise OSError("Herdr sent an unexpected payload")
    return envelope


def envelope_error(envelope):
    """The failure Herdr reports inside a 200-shaped reply, if there is one."""
    if not isinstance(envelope, dict):
        return ""
    error = envelope.get("error")
    if not isinstance(error, dict):
        return ""
    code = text(error.get("code"), 60)
    message = text(error.get("message"), 200)
    if not code and not message:
        return ""
    if code and message and code not in message:
        return code + ": " + message
    return message or code


def snapshot_of(envelope):
    """Pull the snapshot object out of the CLI's response envelope."""
    if not isinstance(envelope, dict):
        return None
    result = envelope.get("result")
    if isinstance(result, dict):
        inner = result.get("snapshot")
        if isinstance(inner, dict):
            return inner
        # `herdr agent list` answers with the agents array directly.
        if isinstance(result.get("agents"), list):
            return {"agents": result["agents"]}
    if isinstance(envelope.get("snapshot"), dict):
        return envelope["snapshot"]
    return None


def normalize_status(value):
    name = text(value, 16).lower()
    return name if name in STATUS_RANK else "unknown"


def agent_label(raw):
    """Which agent this is, preferring what Herdr displays over its id."""
    if not isinstance(raw, dict):
        return ""
    for key in ("display_agent", "agent", "name"):
        value = text(raw.get(key), 40)
        if value:
            return value
    return ""


def agent_title(raw):
    """What the agent is doing, from the terminal's own title.

    Titles are long and change constantly, so this is the row's trailing text
    and the tile elides it. A directory is a better last resort than nothing.
    """
    if not isinstance(raw, dict):
        return ""
    for key in ("terminal_title_stripped", "terminal_title", "title"):
        value = text(raw.get(key), 120)
        if value:
            return value
    return home_name(raw.get("foreground_cwd") or raw.get("cwd"))


def parse_agent(raw):
    """One agent out of the snapshot's agents array."""
    if not isinstance(raw, dict):
        return None
    # Ids are not truncated. Herdr builds them as `<workspace>:<pane>`, and a
    # shortened id would fail the shape check the tile applies before it asks
    # the launcher to focus anything, quietly turning the row inert.
    pane = text(raw.get("pane_id"), 80)
    name = agent_label(raw)
    if not pane and not name:
        return None
    return {
        "paneId": pane,
        "tabId": text(raw.get("tab_id"), 80),
        "workspaceId": text(raw.get("workspace_id"), 80),
        "name": name,
        "title": agent_title(raw),
        "status": normalize_status(raw.get("agent_status")),
        "focused": bool(raw.get("focused")),
        "cwd": home_name(raw.get("foreground_cwd") or raw.get("cwd")),
        "revision": int(number(raw.get("revision"), 0) or 0),
        # A rising counter means something changed since the last poll. The
        # tile uses it to keep a scroll position from resetting on a no-op.
        "seq": int(number(raw.get("state_change_seq"), 0) or 0),
    }


def parse_agents(snapshot):
    rows = rows_of(snapshot.get("agents")) if isinstance(snapshot, dict) else []
    agents = []
    for raw in rows:
        agent = parse_agent(raw)
        if agent:
            agents.append(agent)
    return agents


def sort_agents(agents):
    """Blocked first, then working, then the quiet ones.

    Within a status, the focused pane leads, then the most recently changed,
    then the name, so a re-sort is stable between polls.
    """
    return sorted(agents, key=lambda a: (
        STATUS_RANK.get(a.get("status"), len(STATUSES)),
        0 if a.get("focused") else 1,
        -int(a.get("seq") or 0),
        str(a.get("name") or "").lower(),
    ))


def rows_of(value):
    """A list, or an empty one. The feed is trusted but not obeyed."""
    return value if isinstance(value, list) else []


def count_statuses(agents):
    counts = {name: 0 for name in STATUSES}
    for agent in agents:
        counts[normalize_status(agent.get("status"))] += 1
    return counts


def section_of(section_id):
    """Split a section id into the parts a filter needs.

    "" is every section, "w1" is a workspace, and "w1:t2" is one tab. Herdr
    builds these ids, so anything else is treated as "all" rather than
    guessing at a path. Both keys hold whole ids, because a tab is matched by
    its own full id and not by its tail.
    """
    value = text(section_id, 80)
    if not value:
        return {"id": ALL, "workspace": "", "tab": ""}
    if ":" in value:
        workspace, _, _tail = value.partition(":")
        return {"id": value, "workspace": text(workspace, 80), "tab": value}
    return {"id": value, "workspace": value, "tab": ""}


def in_section(agent, section):
    if not section or not section.get("id"):
        return True
    tab = section.get("tab")
    if tab:
        return agent.get("tabId") == tab
    return agent.get("workspaceId") == section.get("workspace")


def sections(snapshot):
    """Every section a person could attach the tile to, with agent counts.

    The order is the natural one: everything, then each workspace, then that
    workspace's tabs. Counts are what make the list pickable at a glance.
    """
    agents = parse_agents(snapshot)
    rows = [{
        "id": ALL,
        "kind": "all",
        "label": "All sections",
        "detail": "every workspace in this session",
        "count": len(agents),
    }]
    if not isinstance(snapshot, dict):
        # A missing session is not a reason to hand the panel an empty list.
        return rows
    # Drop junk before sorting: the sort key reads a field off every entry.
    workspaces = [w for w in rows_of(snapshot.get("workspaces")) if isinstance(w, dict)]
    tabs = [t for t in rows_of(snapshot.get("tabs")) if isinstance(t, dict)]
    for workspace in sorted(workspaces, key=lambda w: int(number(w.get("number"), 0) or 0)):
        workspace_id = text(workspace.get("workspace_id"), 80)
        if not workspace_id:
            continue
        number_text = text(workspace.get("number"), 4)
        label = text(workspace.get("label"), 60) or ("workspace " + number_text)
        own = [a for a in agents if a.get("workspaceId") == workspace_id]
        rows.append({
            "id": workspace_id,
            "kind": "workspace",
            "label": (number_text + " " + label) if number_text else label,
            "detail": "workspace",
            "count": len(own),
            "status": normalize_status(workspace.get("agent_status")),
        })
        for tab in sorted(tabs, key=lambda t: int(number(t.get("number"), 0) or 0)):
            if text(tab.get("workspace_id"), 80) != workspace_id:
                continue
            tab_id = text(tab.get("tab_id"), 80)
            if not tab_id:
                continue
            in_tab = [a for a in own if a.get("tabId") == tab_id]
            tab_number = text(tab.get("number"), 4)
            tab_label = text(tab.get("label"), 40) or tab_number
            rows.append({
                "id": tab_id,
                "kind": "tab",
                "label": "tab " + tab_label,
                "detail": label,
                "count": len(in_tab),
                "status": normalize_status(tab.get("agent_status")),
            })
    return rows


def section_label(snapshot, section_id):
    """A short name for the footer, falling back to the raw id."""
    wanted = text(section_id, 80)
    for row in sections(snapshot):
        if row["id"] == wanted:
            return row["label"]
    return wanted


def busy(agents):
    return [a for a in agents
            if normalize_status(a.get("status")) in ("blocked", "working")]


def build(snapshot, section_id=ALL, busy_only=False, error=None):
    """The whole tile payload from one snapshot."""
    if error:
        return error_view(error)
    if not isinstance(snapshot, dict):
        return error_view("Herdr sent an unexpected payload")

    section = section_of(section_id)
    everything = parse_agents(snapshot)
    shown = [a for a in everything if in_section(a, section)]
    if busy_only:
        shown = [a for a in shown
                 if normalize_status(a.get("status")) in ("blocked", "working")]
    shown = sort_agents(shown)

    counts = count_statuses(everything)
    scoped_counts = count_statuses([a for a in everything if in_section(a, section)])
    moving = busy(everything)

    poll_ms = POLL_IDLE_MS
    if moving:
        poll_ms = POLL_BUSY_MS
    elif not everything:
        poll_ms = POLL_OFF_MS

    focus = None
    for agent in shown:
        if agent.get("focused"):
            focus = agent
            break
    if focus is None and shown:
        focus = shown[0]

    return {
        "ok": True,
        "banner": "HERDR",
        "error": None,
        "pollMs": poll_ms,
        "agents": shown,
        "total": len(shown),
        "hidden": max(0, len(everything) - len(shown)),
        "counts": counts,
        "scopedCounts": scoped_counts,
        "focus": focus,
        "moving": len(moving),
        "section": section["id"],
        "sectionLabel": section_label(snapshot, section["id"]),
        "busyOnly": bool(busy_only),
        "version": text(snapshot.get("version"), 20),
        "workspaces": len(rows_of(snapshot.get("workspaces"))),
    }


def error_view(message="Herdr is not answering"):
    return {
        "ok": False,
        "banner": "HERDR",
        "error": text(message, 160) or "Herdr is not answering",
        "pollMs": POLL_OFF_MS,
        "agents": [],
        "total": 0,
        "hidden": 0,
        "counts": {name: 0 for name in STATUSES},
        "scopedCounts": {name: 0 for name in STATUSES},
        "focus": None,
        "moving": 0,
        "section": ALL,
        "sectionLabel": "All sections",
        "busyOnly": False,
        "version": "",
        "workspaces": 0,
    }


def collect(section_id=ALL, busy_only=False, run=run_herdr):
    """Read the current session and turn it into a tile payload.

    A Herdr error comes back as a payload with `ok` false rather than an
    exception: a stopped server is a thing the tile should draw, not crash on.
    """
    try:
        envelope = run()
    except OSError as error:
        return error_view(text(error, 160) or "Herdr is not answering")
    except Exception:
        return error_view("Herdr is not answering")

    reported = envelope_error(envelope)
    if reported:
        return error_view(reported)
    snapshot = snapshot_of(envelope)
    if snapshot is None:
        return error_view("Herdr sent an unexpected payload")
    return build(snapshot, section_id, busy_only)


def catalog(run=run_herdr):
    """The settings panel's section list, or a usable empty one."""
    empty = [{"id": ALL, "kind": "all", "label": "All sections",
              "detail": "Herdr is not answering", "count": 0}]
    try:
        envelope = run()
    except OSError:
        return empty
    except Exception:
        return empty
    if envelope_error(envelope):
        return empty
    snapshot = snapshot_of(envelope)
    if not isinstance(snapshot, dict):
        return empty
    rows = sections(snapshot)
    return rows or empty


def main(argv):
    args = argv[1:]
    try:
        if "--sections" in args:
            payload = {"ok": True, "rows": catalog()}
        else:
            section_id = ALL
            if "--section" in args:
                index = args.index("--section")
                section_id = text(args[index + 1] if index + 1 < len(args) else "", 80)
            payload = collect(section_id, "--busy" in args)
    except Exception as error:
        # collect() draws the failures it expects. This is for the rest, so the
        # tile still gets one JSON object instead of a traceback.
        payload = error_view(text(error, 160) or "Herdr is not answering")
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
