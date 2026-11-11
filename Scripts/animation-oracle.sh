#!/bin/bash
#
# M4 animation frame oracle (report-only): dumps the same fixtures with the browser and the kit at
# known animation times and prints the per-frame differences.
#
# The browser part runs in the Example app (`AnimationOracleRunner`): WKWebView pauses every CSS
# animation and seeks it to t, while an SVGView freezes its Core Animation timeline at the same t.
# The test bundle then compares the rasters (`SVGAnimationFrameOracleTests`). The dump's location is
# recorded in `<repo>/.animation-rasters`.
#
# Usage: Scripts/animation-oracle.sh
#   SKIP_DUMP=1      reuse the rasters already in $RASTERS
#   SKIP_TESTS=1     only produce the rasters
#   RASTERS=<dir>    dump directory (default /tmp/svgrkit-animation-rasters)
#   FIXTURES=<dir>   fixture directory (default Example/Example/AnimationOracleFixtures)
#   DUMP_TIMEOUT=<s> how long the app may take (default 300)
#
# Exit code 0 when the dump is complete (the frame report never fails the build), 1 otherwise.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RASTERS="${RASTERS:-/tmp/svgrkit-animation-rasters}"
FIXTURES="${FIXTURES:-$REPO_DIR/Example/Example/AnimationOracleFixtures}"
POINTER="$REPO_DIR/.animation-rasters"
DUMP_TIMEOUT="${DUMP_TIMEOUT:-300}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/svgrkit-example-dd}"
BUNDLE_ID="clevertec.Example"
DUMP_LOG="${DUMP_LOG:-/tmp/svgrkit-animation-dump.log}"
TEST_LOG="${LOG:-/tmp/svgrkit-animation-oracle.log}"

cd "$REPO_DIR" || exit 1
status=0

if [ "${SKIP_DUMP:-0}" != 1 ]; then
  UDID=$(Scripts/pick-simulator.sh) || exit 1
  echo "simulator: $UDID"
  echo "building Example…"
  if ! xcodebuild -project Example/Example.xcodeproj -scheme Example -configuration Debug \
      -destination "id=$UDID" -derivedDataPath "$DERIVED_DATA" build > "$DUMP_LOG.build" 2>&1; then
    echo "::error::the Example app failed to build"
    grep -E "error:" "$DUMP_LOG.build" | head -10
    exit 1
  fi
  APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Example.app"
  xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1
  xcrun simctl install "$UDID" "$APP" || exit 1

  rm -rf "$RASTERS"
  rm -f "$POINTER" "$DUMP_LOG"
  echo "dumping kit and browser frames (fixtures $FIXTURES, dump $RASTERS)…"
  xcrun simctl launch --terminate-running-process --console-pty "$UDID" "$BUNDLE_ID" \
    -animationOracle "$FIXTURES" "$RASTERS" > "$DUMP_LOG" 2>&1 &
  LAUNCH_PID=$!
  for _ in $(seq "$DUMP_TIMEOUT"); do
    kill -0 "$LAUNCH_PID" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$LAUNCH_PID" 2>/dev/null; then
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1
    kill "$LAUNCH_PID" 2>/dev/null
    echo "::error::the animation dump did not finish within ${DUMP_TIMEOUT}s"
    tail -5 "$DUMP_LOG"
    exit 1
  fi
  wait "$LAUNCH_PID" 2>/dev/null

  grep -E "^ANIMATION_DUMP_(SUMMARY|FAIL)" "$DUMP_LOG" | tail -10
  SUMMARY=$(grep -E "^ANIMATION_DUMP_SUMMARY " "$DUMP_LOG" | tail -1)
  if [ -z "$SUMMARY" ]; then
    echo "::error::no ANIMATION_DUMP_SUMMARY in $DUMP_LOG — did the app start? (first lines:)"
    head -5 "$DUMP_LOG"
    exit 1
  fi
  if ! printf '%s\n' "$SUMMARY" | grep -qE " failed=0 "; then
    echo "::error::the animation dump is incomplete: $SUMMARY"
    status=1
  fi
  printf '%s\n' "$RASTERS" > "$POINTER"
  echo "animation rasters: $RASTERS (recorded in $POINTER)"
else
  echo "SKIP_DUMP=1: reusing $RASTERS"
fi

if [ "${SKIP_TESTS:-0}" = 1 ]; then
  echo "SKIP_TESTS=1: rasters are in $RASTERS"
  exit "$status"
fi

UDID="${UDID:-$(Scripts/pick-simulator.sh)}" || exit 1
echo "comparing kit and browser frames…"
SVGRENDERKIT_ANIMATION_RASTERS="$RASTERS" LOG="$TEST_LOG" DESTINATION="id=$UDID" \
  Scripts/run-tests.sh -only-testing:SVGRenderKitTests/SVGAnimationFrameOracleTests > /dev/null 2>&1
grep -aE "^ANIMATION_FRAME(_SUMMARY|_MISSING)? " "$TEST_LOG" | tail -90
if ! grep -aq "^ANIMATION_FRAME_SUMMARY " "$TEST_LOG"; then
  echo "::error::the frame report did not run (see $TEST_LOG)"
  status=1
fi
exit "$status"
