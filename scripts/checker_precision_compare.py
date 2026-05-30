#!/usr/bin/env python3
"""Compare two checker-precision JSON baselines and report regressions.

Usage:
  checker_precision_compare.py <baseline.json> <current.json>

Exit codes:
  0  no regressions
  1  one or more files show increased issue counts (regression)

A file that previously had 0 issues and now has > 0 is always a regression.
A file that now has fewer issues is flagged as an improvement (exit 0).
New files in current but not in baseline are reported but not blocking.
Files in baseline but missing from current are reported as warnings.
"""
import json
import sys


def load(path: str) -> dict[str, int]:
    if path == "/dev/stdin" or path.startswith("/proc/"):
        import io
        data = sys.stdin.read() if path == "/dev/stdin" else open(path).read()
    else:
        data = open(path).read()
    return json.loads(data)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <baseline.json> <current.json>", file=sys.stderr)
        return 2

    baseline = load(sys.argv[1])
    current = load(sys.argv[2])

    regressions: list[tuple[str, int, int]] = []
    improvements: list[tuple[str, int, int]] = []
    new_issues: list[tuple[str, int]] = []
    missing: list[str] = []

    for path, old_count in sorted(baseline.items()):
        if path not in current:
            missing.append(path)
            continue
        new_count = current[path]
        if new_count > old_count:
            regressions.append((path, old_count, new_count))
        elif new_count < old_count and old_count >= 0:
            improvements.append((path, old_count, new_count))

    for path, new_count in sorted(current.items()):
        if path not in baseline and new_count > 0:
            new_issues.append((path, new_count))

    # ---- Report ----
    if improvements:
        print(f"\n✓ Improvements ({len(improvements)}):")
        for path, old, new in improvements:
            print(f"  {path}: {old} → {new} ({new - old:+d})")

    if new_issues:
        print(f"\n~ New files with issues ({len(new_issues)}):")
        for path, count in new_issues:
            print(f"  {path}: {count} issues")

    if missing:
        print(f"\n? Missing from current run ({len(missing)}):")
        for path in missing:
            print(f"  {path}")

    if regressions:
        print(f"\n✗ REGRESSIONS ({len(regressions)}):")
        for path, old, new in regressions:
            print(f"  {path}: {old} → {new} ({new - old:+d})")
        return 1

    total = len(baseline)
    print(
        f"\n✓ No regressions ({total} files checked, "
        f"{len(improvements)} improvements)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
