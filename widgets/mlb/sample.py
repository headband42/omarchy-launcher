#!/usr/bin/env python3
"""Print the MLB tile, or the club list for its settings panel.

    sample.py [--team ID]
    sample.py --teams
"""

import json
import sys
from datetime import datetime

import mlb


def main(argv):
    args = argv[1:]
    now = datetime.now().astimezone()
    if "--teams" in args:
        rows = mlb.team_catalog(mlb.fetch_json(mlb.teams_url(now)))
        # `divisions` is the flat list an already-open settings page still reads.
        # `rows` pairs AL and NL for the current page.
        json.dump({
            "divisions": mlb.division_groups(rows),
            "rows": mlb.division_rows(rows),
        }, sys.stdout)
        sys.stdout.write("\n")
        return 0
    team_id = 0
    if "--team" in args:
        index = args.index("--team")
        if index + 1 >= len(args):
            json.dump(mlb.error_view(), sys.stdout)
            sys.stdout.write("\n")
            return 0
        team_id = mlb.team_id_from_settings({"teamId": args[index + 1]}) or 0
    json.dump(mlb.collect(team_id, now, mlb.fetch_json), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
