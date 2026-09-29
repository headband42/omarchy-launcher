import json
import sys
from datetime import datetime, timezone

import opencode


def main(argv):
    now = datetime.now(timezone.utc)
    try:
        payload = opencode.collect(now)
    except Exception as error:
        payload = opencode.error_view(str(error) or "OpenCode Go usage is unavailable", now)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
