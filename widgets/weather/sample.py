import json
import sys

import weather


def main(argv):
    args = argv[1:]
    try:
        import os, time
        if os.environ.get("WEATHER_TRACE") == "1":
            log = os.path.expanduser("~/.cache/ande.launcher/weather/invocations.log")
            os.makedirs(os.path.dirname(log), exist_ok=True)
            with open(log, "a", encoding="utf-8") as fh:
                fh.write("%.3f %s\n" % (time.time(), " ".join(args)))
    except Exception:
        pass
    if "--search" in args:
        index = args.index("--search")
        query = args[index + 1] if index + 1 < len(args) else ""
        payload = weather.search_locations(query)
    else:
        location = {}
        for field in ("latitude", "longitude"):
            flag = "--" + field
            if flag in args:
                index = args.index(flag)
                location[field] = args[index + 1] if index + 1 < len(args) else ""
        for field in ("label", "timezone"):
            flag = "--" + field
            if flag in args:
                index = args.index(flag)
                location[field] = args[index + 1] if index + 1 < len(args) else ""
        mode = weather.cache_mode_from_args(args)
        payload = weather.collect(location, cache_mode=mode)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
