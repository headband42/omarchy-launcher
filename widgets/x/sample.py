#!/usr/bin/env python3
"""X tile model CLI. Network happens here; Widget.qml only parses JSON.

    sample.py [--woeid ID] [--place NAME] [--max N] [--cookies PATH]
              [--cache-first|--cache-only]
    sample.py --places
"""

import json
import sys

import x as xmod


def main(argv):
    args = argv[1:]
    try:
        import os
        import time

        if os.environ.get("X_WIDGET_TRACE") == "1":
            log = os.path.expanduser("~/.cache/ande.launcher/x/invocations.log")
            os.makedirs(os.path.dirname(log), exist_ok=True)
            with open(log, "a", encoding="utf-8") as fh:
                fh.write("%.3f %s\n" % (time.time(), " ".join(args)))
    except Exception:
        pass

    if "--places" in args:
        payload = xmod.places_payload()
        json.dump(payload, sys.stdout)
        sys.stdout.write("\n")
        sys.stdout.flush()
        return 0

    settings = {}
    if "--woeid" in args:
        index = args.index("--woeid")
        settings["woeid"] = args[index + 1] if index + 1 < len(args) else ""
    if "--place" in args:
        index = args.index("--place")
        settings["placeName"] = args[index + 1] if index + 1 < len(args) else ""
    if "--max" in args:
        index = args.index("--max")
        settings["maxHeadlines"] = args[index + 1] if index + 1 < len(args) else ""
    if "--cookies" in args:
        index = args.index("--cookies")
        settings["cookiesPath"] = args[index + 1] if index + 1 < len(args) else ""

    mode = xmod.cache_mode_from_args(args)
    payload = xmod.collect(settings, cache_mode=mode)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
