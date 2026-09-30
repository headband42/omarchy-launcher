#!/usr/bin/env python3
"""Print the docker tile sample as JSON."""

import json
import sys

import docker


def main(argv):
    json.dump(docker.collect(), sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
