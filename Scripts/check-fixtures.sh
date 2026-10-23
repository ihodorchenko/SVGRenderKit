#!/bin/bash
#
# Per-fixture parity gate. `check-parity.sh` only compares the summary counts, so an icon already
# accepted as a known divergence could degrade from 2% to 90% differing pixels and stay green.
# This gate keeps the `differing` fraction of every failing fixture in a committed baseline and
# fails when a fixture gets worse, or when a fixture that is not in the baseline starts failing.
#
# Usage: check-fixtures.sh <xcodebuild.log> <fixtures-baseline.txt> [FAIL_PREFIX]
#        check-fixtures.sh --update <xcodebuild.log> <fixtures-baseline.txt> [FAIL_PREFIX]
#
# FAIL_PREFIX selects the oracle: `CORPUS_FAIL` (CoreSVG, the default) or `WEBKIT_FAIL`.
# A baseline line is `<fixture name> <differing fraction>`. TOLERANCE (default 0.01) is the
# absolute growth of the fraction that is still accepted (rasterization noise between Xcodes).
# --update rewrites the baseline from the log (after an improvement, or a triaged new fixture).
#
# Rules (any violation fails):
#   - a failing fixture missing from the baseline;
#   - a failing fixture whose differing fraction grew by more than TOLERANCE.
# A baseline fixture that no longer fails is reported as an improvement (update the baseline).
set -uo pipefail

UPDATE=0
if [ "${1:-}" = "--update" ]; then UPDATE=1; shift; fi
LOG="${1:?usage: check-fixtures.sh [--update] <log> <baseline> [FAIL_PREFIX]}"
BASELINE_FILE="${2:?usage: check-fixtures.sh [--update] <log> <baseline> [FAIL_PREFIX]}"
FAIL_PREFIX="${3:-CORPUS_FAIL}"
TOLERANCE="${TOLERANCE:-0.01}"

# `<name> <differing>` for every failing fixture, sorted so the baseline diffs cleanly.
ACTUAL=$(grep -aE "^$FAIL_PREFIX " "$LOG" 2>/dev/null \
  | sed -E "s/^$FAIL_PREFIX ([^ ]+) differing=([0-9.]+).*/\1 \2/" | sort -u)

if [ "$UPDATE" = 1 ]; then
  printf '%s\n' "$ACTUAL" > "$BASELINE_FILE"
  echo "$BASELINE_FILE: $(printf '%s\n' "$ACTUAL" | grep -c .) fixtures"
  exit 0
fi

if [ -z "$ACTUAL" ] && ! grep -aqE "^${FAIL_PREFIX%_FAIL}_SUMMARY " "$LOG"; then
  echo "::error::no ${FAIL_PREFIX%_FAIL}_SUMMARY line in $LOG — was the parity test skipped?"
  exit 1
fi

RESULT=$(awk -v tol="$TOLERANCE" -v prefix="$FAIL_PREFIX" '
  NR == FNR { base[$1] = $2; next }
  { seen[$1] = 1
    if (!($1 in base)) { printf "::error::%s: %s fails and is not in the baseline (differing=%s)\n", prefix, $1, $2; bad = 1 }
    else if ($2 > base[$1] + tol) { printf "::error::%s: %s got worse: differing %s -> %s\n", prefix, $1, base[$1], $2; bad = 1 } }
  END {
    for (name in base) if (!(name in seen)) printf "improved: %s no longer fails (was %s) — run check-fixtures.sh --update\n", name, base[name]
    exit bad
  }' "$BASELINE_FILE" <(printf '%s\n' "$ACTUAL"))
status=$?
[ -n "$RESULT" ] && printf '%s\n' "$RESULT"
if [ "$status" = 0 ]; then
  echo "$FAIL_PREFIX: every failing fixture is within its baseline"
fi
exit "$status"
