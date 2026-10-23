#!/bin/bash
#
# Runs the SVGRenderKit package tests and force-terminates a hung xcodebuild.
#
# Why: after the last test `xcodebuild test` often does not exit on its own (Xcode 26/27) although
# the result is already printed, and tools waiting for the process hang. The script waits for the
# result line, gives the process GRACE_SECONDS to exit by itself, otherwise kills it and parses the
# log itself.
#
# Usage (from any directory):
#   Scripts/run-tests.sh                                            — all tests except the benchmarks
#   Scripts/run-tests.sh -only-testing:SVGRenderKitTests/SVGMemoryManagementTests
#   LOG=/tmp/svg.log DESTINATION='platform=iOS Simulator,name=iPhone 17' Scripts/run-tests.sh
#
# The verdict is printed at the end and written to "$LOG.verdict"; the last line is one of:
# PASSED, WARNINGS, FAILED, BUILD-FAILED, CRASHED, HUNG, NO-RESULT. Exit code: 0 only for PASSED.
#
# HUNG — the log has not grown for more than STALL_SECONDS (default 180): a hung test does not hold
# the run forever; the verdict names the test it stopped on.
# CLEAN=1 — a clean rebuild (the compiler then warns about every file of the package).
# PERF=1 — also run SVGPerformanceTests (skipped by default: Debug timings are not representative;
# measure in Release, see CLAUDE.md). Naming SVGPerformanceTests in -only-testing also runs them.

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${LOG:-$(mktemp -t svgrenderkit-tests).log}"
SCHEME="${SCHEME:-SVGRenderKit-Package}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
GRACE_SECONDS="${GRACE_SECONDS:-15}"
STALL_SECONDS="${STALL_SECONDS:-180}"

rm -f "$LOG" "$LOG.verdict"
cd "$ROOT_DIR" || exit 1

if [ "${CLEAN:-0}" = 1 ]; then
  xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" clean > /dev/null 2>&1
fi

SKIP_PERF=(-skip-testing:SVGRenderKitTests/SVGPerformanceTests)
if [ "${PERF:-0}" = 1 ] || printf '%s\n' "$*" | grep -q "SVGPerformanceTests"; then SKIP_PERF=(); fi

xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" ${SKIP_PERF[@]+"${SKIP_PERF[@]}"} "$@" test > "$LOG" 2>&1 &
PID=$!
DONE='\*\* TEST (SUCCEEDED|FAILED) \*\*|\*\* BUILD FAILED \*\*|Test Suite .(All tests|Selected tests). (passed|failed)'

LAST_SIZE=0
LAST_GROWTH=$(date +%s)
STALLED=0

while kill -0 $PID 2>/dev/null; do
  SIZE=$(stat -f %z "$LOG" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  if [ "$SIZE" != "$LAST_SIZE" ]; then
    LAST_SIZE=$SIZE
    LAST_GROWTH=$NOW
  elif [ $((NOW - LAST_GROWTH)) -ge "$STALL_SECONDS" ] && ! grep -qE "$DONE" "$LOG"; then
    kill $PID
    STALLED=1
    break
  fi
  if grep -qE "$DONE" "$LOG"; then
    for _ in $(seq $GRACE_SECONDS); do kill -0 $PID 2>/dev/null || break; sleep 1; done
    if kill -0 $PID 2>/dev/null; then
      kill $PID
      echo "xcodebuild hung after the result — killed" >> "$LOG.verdict"
    fi
    break
  fi
  sleep 2
done
wait $PID 2>/dev/null

# Warnings: unique `file:line:column: warning:` lines from the package's own files.
# Warnings of dependencies (.build/checkouts) and service ones without a path do not count.
COMPILER_WARNINGS=$(grep -E "^$ROOT_DIR/(Sources|Tests|Example)/.*\.swift:[0-9]+:[0-9]+: warning:" "$LOG" | sort -u)
COMPILER_COUNT=$(printf '%s' "$COMPILER_WARNINGS" | grep -c . || true)

{
  echo "--- verdict ($LOG) ---"
  if [ "$STALLED" = 1 ]; then
    grep -E "Test Case .* started" "$LOG" | tail -1 | sed "s/^[[:space:]]*/hung on: /"
  fi
  # Every test bundle prints its own result; sum one per bundle.
  awk '/Test Suite .*\.xctest. (passed|failed)/ { name = $3; want = 1; next }
       want && /Executed [0-9]+ tests/ && !(name in seen) { seen[name] = 1; n += $2; f += $5; want = 0 }
       END { if (length(seen)) printf "Executed %d tests, with %d failures, bundles: %d\n", n, f, length(seen) }' "$LOG"
  grep -c "Restarting after unexpected exit" "$LOG" | sed 's/^/restarts after a crash: /'
  grep -E "^\s+[A-Za-z]+Tests\.test[A-Za-z0-9_]*\(\)" "$LOG" | sort -u | sed 's/^[[:space:]]*/failed: /'
  grep -E "^/.*\.swift:[0-9]+(:[0-9]+)?: error:" "$LOG" | sort -u | head -10
  echo "compiler warnings: $COMPILER_COUNT"
  if [ "$COMPILER_COUNT" -gt 0 ]; then
    printf '%s\n' "$COMPILER_WARNINGS" | sed "s#^$ROOT_DIR/##" | head -20 | sed 's/^/  /'
  fi
  if [ "$STALLED" = 1 ]; then echo "HUNG"
  elif ! grep -q "Test Suite" "$LOG" && grep -qE "\*\* BUILD FAILED \*\*|\.swift:[0-9]+:[0-9]+: error:" "$LOG"; then echo "BUILD-FAILED"
  elif grep -q "Restarting after unexpected exit" "$LOG"; then echo "CRASHED"
  # Several bundles each print their own "All tests": a failure anywhere is FAILED.
  elif grep -qE "Test Suite .(All tests|Selected tests). failed|: error: -\[" "$LOG"; then echo "FAILED"
  elif grep -qE "Test Suite .(All tests|Selected tests). passed" "$LOG"; then
    if [ "$COMPILER_COUNT" -gt 0 ]; then echo "WARNINGS"; else echo "PASSED"; fi
  else echo "NO-RESULT"; fi
} | tee -a "$LOG.verdict"

[ "$(tail -1 "$LOG.verdict")" = "PASSED" ]
