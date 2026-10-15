#!/bin/bash
#
# Prints the UDID of the newest available simulator whose name starts with the given
# prefix (default "iPhone"), or fails.
#
# Why: `simctl list devices available | grep -m1 "iPhone"` picks whichever device the
# list happens to show first, which can be an old runtime. Picking the newest iOS
# runtime makes CI deterministic and fails loudly when nothing is installed.
#
# Usage:
#   Scripts/pick-simulator.sh          # newest iPhone
#   Scripts/pick-simulator.sh iPad     # newest iPad
set -uo pipefail

PREFIX="${1:-iPhone}"

UDID=$(xcrun simctl list devices available --json 2>/dev/null | PREFIX="$PREFIX" python3 -c '
import json, os, re, sys

try:
    devices = json.load(sys.stdin)["devices"]
except (ValueError, KeyError):
    sys.exit(0)

prefix = os.environ["PREFIX"]

def runtime_key(runtime):
    match = re.search(r"iOS-(\d+)(?:-(\d+))?", runtime)
    return tuple(int(part) for part in match.groups(default="0")) if match else (0, 0)

for runtime in sorted(devices, key=runtime_key, reverse=True):
    for device in devices[runtime]:
        if device.get("isAvailable") and device.get("name", "").startswith(prefix):
            print(device["udid"])
            sys.exit(0)
' || true)

if [ -z "${UDID:-}" ]; then
  echo "no available '$PREFIX' simulator installed" >&2
  exit 1
fi

echo "$UDID"
