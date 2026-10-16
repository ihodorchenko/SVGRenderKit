#!/bin/bash
#
# Renders the SVG corpus in a real browser (WKWebView, inside the Example app) and then runs the
# corpus parity test with those rasters as the browser oracle (B122), gating *both* oracles:
# CoreSVG (`CORPUS_SUMMARY`) and the browser (`WEBKIT_SUMMARY`).
#
# Why the browser runs in an app: WebKit's WebContent process refuses to start in a bare unit-test
# bundle — on iOS 26 the logs show an RBS assertion that the target "does not have entitlement
# com.apple.developer.web-browser-engine.*" — so the rasters are dumped by the Example app
# (`WebKitParityRunner`, `-webkitParity`) and the test bundle only reads them. That way the very
# same kit raster is judged by both oracles, in one report. The dump's location is recorded in
# `<repo>/.webkit-rasters`, so later plain test runs (`Scripts/run-tests.sh`) report the browser
# numbers too; `SVGRENDERKIT_WEBKIT_RASTERS=<dir>` overrides that where the environment reaches
# the test process.
#
# Usage: Scripts/webkit-parity.sh
#   SKIP_DUMP=1       reuse the rasters already in $RASTERS (the browser pass is skipped)
#   SKIP_TESTS=1      only produce the rasters (and print their summary)
#   RASTERS=<dir>     where the rasters are written (default /tmp/svgrkit-webkit-rasters)
#   BATCH=<n>         fixtures per page call (default 5)
#   DUMP_TIMEOUT=<s>  how long the app may take (default 900; the app itself gives up at 600)
#
# Exit code 0 only when the rasters are complete and both gates pass.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RASTERS="${RASTERS:-/tmp/svgrkit-webkit-rasters}"
POINTER="$REPO_DIR/.webkit-rasters"
BATCH="${BATCH:-5}"
DUMP_TIMEOUT="${DUMP_TIMEOUT:-900}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/svgrkit-example-dd}"
BUNDLE_ID="clevertec.Example"
CORPUS="$REPO_DIR/Example/Example/data"
DUMP_LOG="${DUMP_LOG:-/tmp/svgrkit-webkit-dump.log}"
TEST_LOG="${LOG:-/tmp/svgrkit-webkit-parity.log}"

cd "$REPO_DIR" || exit 1
status=0

# ── The browser pass ────────────────────────────────────────────────────────────────────────────
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
  echo "rendering the corpus in WKWebView (batch $BATCH, dump $RASTERS)…"
  xcrun simctl launch --terminate-running-process --console-pty "$UDID" "$BUNDLE_ID" \
    -webkitParity "$CORPUS" "$BATCH" "$RASTERS" > "$DUMP_LOG" 2>&1 &
  LAUNCH_PID=$!
  # The app gives up on its own after its budget; this only catches a stuck simctl/app.
  for _ in $(seq "$DUMP_TIMEOUT"); do
    kill -0 "$LAUNCH_PID" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$LAUNCH_PID" 2>/dev/null; then
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1
    kill "$LAUNCH_PID" 2>/dev/null
    echo "::error::the browser pass did not finish within ${DUMP_TIMEOUT}s"
    tail -3 "$DUMP_LOG"
    exit 1
  fi
  wait "$LAUNCH_PID" 2>/dev/null

  grep -E "^WEBKIT_(DUMP_SUMMARY|PARITY_ERROR)" "$DUMP_LOG" | tail -5
  DUMP_SUMMARY=$(grep -E "^WEBKIT_DUMP_SUMMARY " "$DUMP_LOG" | tail -1)
  if [ -z "$DUMP_SUMMARY" ]; then
    echo "::error::no WEBKIT_DUMP_SUMMARY in $DUMP_LOG — did the app start? (first lines:)"
    head -5 "$DUMP_LOG"
    exit 1
  fi
  if ! printf '%s\n' "$DUMP_SUMMARY" | grep -qE " failed=0 "; then
    echo "::error::the browser could not rasterize every fixture: $DUMP_SUMMARY"
    grep -E "^WEBKIT_DUMP_FAIL " "$DUMP_LOG" | head -10
    status=1
  fi
  FIXTURES=$(find "$CORPUS" -name '*.svg' | wc -l | tr -d ' ')
  if ! printf '%s\n' "$DUMP_SUMMARY" | grep -qE " total=$FIXTURES "; then
    echo "::error::the dump covers a different corpus than $CORPUS ($DUMP_SUMMARY, expected total=$FIXTURES)"
    status=1
  fi
  if [ "$status" != 0 ]; then
    echo "re-run without SKIP_DUMP after fixing the corpus/dump; rasters are in $RASTERS"
    exit "$status"
  fi
  # The test bundle cannot see this shell's environment, so it reads the location from here.
  printf '%s\n' "$RASTERS" > "$POINTER"
  echo "browser rasters: $RASTERS (recorded in $POINTER)"
else
  echo "SKIP_DUMP=1: reusing $RASTERS"
fi

if [ "${SKIP_TESTS:-0}" = 1 ]; then
  echo "SKIP_TESTS=1: rasters are in $RASTERS"
  exit "$status"
fi

# ── The comparison (both oracles on the same kit raster) ────────────────────────────────────────
UDID="${UDID:-$(Scripts/pick-simulator.sh)}" || exit 1
echo "running the corpus parity test against ${RASTERS}…"
SVGRENDERKIT_WEBKIT_RASTERS="$RASTERS" LOG="$TEST_LOG" DESTINATION="id=$UDID" \
  Scripts/run-tests.sh -only-testing:SVGRenderKitTests/SVGRenderParityTests/testCorpusParity > /dev/null 2>&1
grep -aE "^(CORPUS_SUMMARY|WEBKIT_SUMMARY) " "$TEST_LOG" | tail -4

Scripts/check-parity.sh "$TEST_LOG" .github/parity-baseline.txt || status=1
Scripts/check-parity.sh "$TEST_LOG" .github/webkit-baseline.txt WEBKIT_SUMMARY || status=1

if [ "$status" = 0 ]; then
  echo "both oracles are within their baselines"
fi
exit "$status"
