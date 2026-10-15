#!/bin/bash
#
# Compares the corpus parity summary in an xcodebuild log against a committed baseline,
# so a visual regression that was added to `ParityTriage.reasons` still fails CI.
#
# Usage: check-parity.sh <xcodebuild.log> <parity-baseline.txt>
#
# Rules (any violation fails):
#   - `kitError` and `referenceMissing` must be 0 (the parity test already asserts this,
#     repeated here so the gate is self-contained);
#   - `fail` and `referenceLimited` must not grow past the baseline;
#   - `pass` must not shrink below the baseline.
set -uo pipefail

LOG="${1:?usage: check-parity.sh <log> <baseline>}"
BASELINE_FILE="${2:?usage: check-parity.sh <log> <baseline>}"

summary_line() { grep -aE '^CORPUS_SUMMARY ' "$1" 2>/dev/null | tail -1; }
value() { printf '%s\n' "$1" | grep -oE "(^| )$2=[0-9]+" | tail -1 | cut -d= -f2; }

ACTUAL=$(summary_line "$LOG")
EXPECTED=$(summary_line "$BASELINE_FILE")

if [ -z "$ACTUAL" ]; then
  echo "::error::no CORPUS_SUMMARY line in $LOG — was the parity test skipped?"
  exit 1
fi
if [ -z "$EXPECTED" ]; then
  echo "::error::no CORPUS_SUMMARY line in $BASELINE_FILE"
  exit 1
fi

echo "baseline: $EXPECTED"
echo "actual:   $ACTUAL"

status=0
check_zero() {
  local actual; actual=$(value "$ACTUAL" "$1")
  if [ -n "$actual" ] && [ "$actual" != "0" ]; then
    echo "::error::$1 must be 0, got $actual"
    status=1
  fi
}
check_not_greater() {
  local actual expected; actual=$(value "$ACTUAL" "$1"); expected=$(value "$EXPECTED" "$1")
  if [ -n "$actual" ] && [ -n "$expected" ] && [ "$actual" -gt "$expected" ]; then
    echo "::error::$1 grew from $expected to $actual (triage the new fixture or fix it)"
    status=1
  fi
}
check_not_less() {
  local actual expected; actual=$(value "$ACTUAL" "$1"); expected=$(value "$EXPECTED" "$1")
  if [ -n "$actual" ] && [ -n "$expected" ] && [ "$actual" -lt "$expected" ]; then
    echo "::error::$1 dropped from $expected to $actual (fixtures missing?)"
    status=1
  fi
}

check_zero kitError
check_zero referenceMissing
check_not_greater fail
check_not_greater referenceLimited
check_not_less pass

if [ "$status" = 0 ]; then
  echo "corpus parity is within the baseline"
fi
exit "$status"
