import json
import sys

import weather


def main(argv):
    args = argv[1:]
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
        payload = weather.collect(location)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
