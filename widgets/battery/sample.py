#!/usr/bin/env python3
"""Print the battery tile sample as JSON."""

import json
import sys

import battery


def main(argv):
    json.dump(battery.collect(), sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
