#!/usr/bin/env python3
"""Print the repo tile sample as JSON.

    sample.py [--path DIR]
"""

import json
import os
import sys

import repo


def main(argv):
    args = argv[1:]
    path = os.path.expanduser("~")
    if "--path" in args:
        index = args.index("--path")
        if index + 1 < len(args) and args[index + 1]:
            path = os.path.expanduser(args[index + 1])
    json.dump(repo.collect(path), sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
