#!/bin/bash
#
# Compares a corpus parity summary in an xcodebuild log against a committed baseline,
# so a visual regression that was added to `ParityTriage.reasons` still fails CI.
#
# Usage: check-parity.sh <xcodebuild.log> <parity-baseline.txt> [SUMMARY_PREFIX]
#
# SUMMARY_PREFIX selects the summary line to gate: `CORPUS_SUMMARY` (the CoreSVG oracle,
# the default) or `WEBKIT_SUMMARY` (the browser oracle, B122 — produced by
# `Scripts/webkit-parity.sh`). The checks are the same for both; a field the prefix does
# not carry (e.g. `referenceLimited` in `WEBKIT_SUMMARY`) is skipped.
#
# Rules (any violation fails):
#   - `kitError` and `referenceMissing` must be 0 (the parity test already asserts this,
#     repeated here so the gate is self-contained);
#   - `fail`, `referenceLimited` and `webkitMissing` must not grow past the baseline;
#   - `pass` must not shrink below the baseline.
set -uo pipefail

LOG="${1:?usage: check-parity.sh <log> <baseline> [SUMMARY_PREFIX]}"
BASELINE_FILE="${2:?usage: check-parity.sh <log> <baseline> [SUMMARY_PREFIX]}"
SUMMARY_PREFIX="${3:-CORPUS_SUMMARY}"

summary_line() { grep -aE "^$SUMMARY_PREFIX " "$1" 2>/dev/null | tail -1; }
value() { printf '%s\n' "$1" | grep -oE "(^| )$2=[0-9]+" | tail -1 | cut -d= -f2; }

ACTUAL=$(summary_line "$LOG")
EXPECTED=$(summary_line "$BASELINE_FILE")

if [ -z "$ACTUAL" ]; then
  echo "::error::no $SUMMARY_PREFIX line in $LOG — was the parity test skipped?"
  exit 1
fi
if [ -z "$(value "$ACTUAL" pass)" ]; then
  echo "::error::$SUMMARY_PREFIX in $LOG carries no pass=<n> — is the oracle enabled? ($ACTUAL)"
  exit 1
fi
if [ -z "$EXPECTED" ]; then
  echo "::error::no $SUMMARY_PREFIX line in $BASELINE_FILE"
  exit 1
fi

echo "$SUMMARY_PREFIX baseline: $EXPECTED"
echo "$SUMMARY_PREFIX actual:   $ACTUAL"

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
check_not_greater webkitMissing
check_not_less pass

if [ "$status" = 0 ]; then
  echo "$SUMMARY_PREFIX is within the baseline"
fi
exit "$status"
