import json
import sys

import herdr


def main(argv):
    args = argv[1:]
    if "--sections" in args:
        payload = {"ok": True, "rows": herdr.catalog()}
    else:
        section_id = ""
        for index, arg in enumerate(args):
            if arg == "--section" and index + 1 < len(args):
                section_id = args[index + 1]
        try:
            payload = herdr.collect(section_id, "--busy" in args)
        except Exception as error:
            payload = herdr.error_view(str(error) or "Herdr is not answering")
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
