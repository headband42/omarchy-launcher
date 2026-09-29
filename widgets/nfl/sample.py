import json
import sys
from datetime import datetime, timezone

import nfl


def main(argv):
    args = argv[1:]
    if "--teams" in args:
        payload = {"ok": True, "rows": nfl.catalog()}
    else:
        team_id = 0
        if "--team" in args:
            index = args.index("--team")
            raw = args[index + 1] if index + 1 < len(args) else 0
            team_id = int(nfl.number(raw, 0) or 0)
        try:
            payload = nfl.collect(team_id, datetime.now(timezone.utc))
        except Exception as error:
            payload = nfl.error_view(str(error) or "Scores unavailable", team_id)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
