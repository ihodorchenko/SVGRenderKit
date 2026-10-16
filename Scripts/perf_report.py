#!/usr/bin/env python3
"""Turns an `xcodebuild test` log of SVGPerformanceTests into a report and a regression check.

Usage:
    perf_report.py LOG [--json OUT.json] [--baseline BASELINE.json]
                       [--fail-ratio 2.0] [--min-seconds 0.01] [--min-delta 0.05] [--max-rsd 35]

- Parses the XCTest `measured [Clock Monotonic Time, s] average: ...` lines.
- Prints a Markdown table (suitable for $GITHUB_STEP_SUMMARY), plus the `FEATURE_COST` corpus lines.
- With --json, writes {"<test>": {"clock": seconds, "rsd": percent}} (use it as the next baseline).
- With --baseline, adds a ratio column and exits 1 when a test is slower than `fail-ratio` times its
  baseline AND by at least `min-delta` seconds in absolute terms. Tests whose baseline is below
  `min-seconds`, or whose relative standard deviation (baseline or current run) is above `max-rsd`
  percent, are only reported (marked `~`): their averages are dominated by runner noise.

Baseline numbers must come from the same kind of machine (CI runner), not a developer laptop: download
`perf.json` from a successful run on main and commit it as `.github/perf-baseline.json`.
"""
import argparse
import json
import re
import sys

MEASURED = re.compile(
    r"Test Case '-\[\S+\.SVGPerformanceTests (?P<name>\w+)\]' measured \[Clock Monotonic Time, s\] "
    r"average: (?P<avg>[0-9.]+), relative standard deviation: (?P<rsd>[0-9.]+)%"
)
FEATURE = re.compile(r"^(FEATURE_COST\S*) (.*)$")


def parse(path):
    results, features = {}, []
    with open(path, errors="replace") as log:
        for line in log:
            match = MEASURED.search(line)
            if match:
                results[match["name"]] = {"clock": float(match["avg"]), "rsd": float(match["rsd"])}
                continue
            feature = FEATURE.match(line.strip())
            if feature:
                features.append(line.strip())
    return results, features


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("log")
    parser.add_argument("--json")
    parser.add_argument("--baseline")
    parser.add_argument("--fail-ratio", type=float, default=2.0)
    parser.add_argument("--min-seconds", type=float, default=0.01)
    parser.add_argument("--min-delta", type=float, default=0.05)
    parser.add_argument("--max-rsd", type=float, default=35.0)
    args = parser.parse_args()

    results, features = parse(args.log)
    if not results:
        print("No performance measurements found in the log.")
        return 1

    baseline = {}
    if args.baseline:
        try:
            with open(args.baseline) as handle:
                baseline = json.load(handle)
        except FileNotFoundError:
            print(f"_No baseline at `{args.baseline}`; reporting only._\n")

    regressions = []
    print("| Test | Clock (s) | RSD |" + (" Baseline (s) | Ratio |" if baseline else ""))
    print("|---|---:|---:|" + ("---:|---:|" if baseline else ""))
    for name in sorted(results):
        current = results[name]
        row = f"| `{name}` | {current['clock']:.4f} | {current['rsd']:.1f}% |"
        if baseline:
            base = baseline.get(name, {}).get("clock")
            if base:
                ratio = current["clock"] / base
                flag = ""
                slower = ratio > args.fail_ratio and current["clock"] - base >= args.min_delta
                noisy = max(current["rsd"], baseline[name].get("rsd", 0.0)) > args.max_rsd
                if base >= args.min_seconds and slower:
                    if noisy:
                        flag = " ~noisy"
                    else:
                        regressions.append((name, base, current["clock"], ratio))
                        flag = " ⚠️"
                row += f" {base:.4f} | {ratio:.2f}x{flag} |"
            else:
                row += " – | – |"
        print(row)

    if features:
        print("\n```")
        print("\n".join(features))
        print("```")

    if args.json:
        with open(args.json, "w") as out:
            json.dump(results, out, indent=2, sort_keys=True)

    if regressions:
        print(f"\n**{len(regressions)} regression(s) above {args.fail_ratio}x:**")
        for name, base, now, ratio in regressions:
            print(f"- `{name}`: {base:.4f}s → {now:.4f}s ({ratio:.2f}x)")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
