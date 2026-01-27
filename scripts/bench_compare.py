#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

LINE_RE = re.compile(
    r"^(?P<name>\S+)\s+"
    r"(?P<mean>[0-9.]+)\s*(?P<mean_unit>ns|µs|us|ms|s)\s+±\s+"
    r"(?P<std>[0-9.]+)\s*(?P<std_unit>ns|µs|us|ms|s)\s+"
    r"(?P<min>[0-9.]+)\s*(?P<min_unit>ns|µs|us|ms|s)\s+"
    r"\.\.\.\s+"
    r"(?P<max>[0-9.]+)\s*(?P<max_unit>ns|µs|us|ms|s)\s+"
    r"in\s+(?P<samples>\d+)\s+×\s+(?P<runs>\d+)\s+runs$"
)

UNIT_TO_NS = {
    "ns": 1.0,
    "us": 1_000.0,
    "µs": 1_000.0,
    "ms": 1_000_000.0,
    "s": 1_000_000_000.0,
}


def to_ns(value: str, unit: str) -> float:
    return float(value) * UNIT_TO_NS[unit]


def parse_output(text: str) -> dict:
    benches = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        line = line.replace("…", "...")
        m = LINE_RE.match(line)
        if not m:
            continue
        name = m.group("name")
        benches[name] = {
            "mean_ns": to_ns(m.group("mean"), m.group("mean_unit")),
            "std_ns": to_ns(m.group("std"), m.group("std_unit")),
            "min_ns": to_ns(m.group("min"), m.group("min_unit")),
            "max_ns": to_ns(m.group("max"), m.group("max_unit")),
            "samples": int(m.group("samples")),
            "runs": int(m.group("runs")),
            "raw": raw,
        }
    return benches


def format_ns(ns: float) -> str:
    if ns >= 1_000_000_000.0:
        return f"{ns / 1_000_000_000.0:.3f}s"
    if ns >= 1_000_000.0:
        return f"{ns / 1_000_000.0:.3f}ms"
    if ns >= 1_000.0:
        return f"{ns / 1_000.0:.3f}µs"
    return f"{ns:.3f}ns"


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare moon bench results to baseline")
    parser.add_argument(
        "--baseline",
        default="bench/baseline.json",
        help="Baseline JSON path",
    )
    parser.add_argument(
        "--output",
        default="bench/compare.json",
        help="Output JSON path",
    )
    parser.add_argument(
        "--raw",
        default="bench/compare.txt",
        help="Raw output path",
    )
    parser.add_argument(
        "--target",
        default="native",
        help="Target backend",
    )
    args = parser.parse_args()

    baseline_path = Path(args.baseline)
    if not baseline_path.exists():
        print(f"baseline not found: {baseline_path}")
        return 1
    baseline = json.loads(baseline_path.read_text())
    baseline_benches = baseline.get("benches", {})

    cmd = ["moon", "bench", "--target", args.target]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    output = proc.stdout
    if proc.returncode != 0:
        print(output)
        return proc.returncode

    current = parse_output(output)
    now = datetime.now(timezone.utc)

    comparisons = {}
    for name, base in baseline_benches.items():
        curr = current.get(name)
        if not curr:
            comparisons[name] = {
                "status": "missing",
                "baseline_mean_ns": base.get("mean_ns"),
            }
            continue
        base_mean = base.get("mean_ns", 0.0)
        curr_mean = curr.get("mean_ns", 0.0)
        delta = curr_mean - base_mean
        delta_pct = (delta / base_mean * 100.0) if base_mean else None
        comparisons[name] = {
            "status": "ok",
            "baseline_mean_ns": base_mean,
            "current_mean_ns": curr_mean,
            "delta_ns": delta,
            "delta_pct": delta_pct,
            "baseline_raw": base.get("raw"),
            "current_raw": curr.get("raw"),
        }

    extras = [name for name in current.keys() if name not in baseline_benches]

    data = {
        "created_at": now.isoformat(),
        "baseline": str(baseline_path),
        "command": " ".join(cmd),
        "target": args.target,
        "comparisons": comparisons,
        "extras": extras,
    }

    raw_path = Path(args.raw)
    raw_path.parent.mkdir(parents=True, exist_ok=True)
    raw_path.write_text(output)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(data, indent=2, sort_keys=True))

    header = f"compare (baseline={baseline_path})"
    print(header)
    for name in sorted(comparisons.keys()):
        item = comparisons[name]
        if item["status"] != "ok":
            print(f"{name}: missing in current run")
            continue
        base_mean = item["baseline_mean_ns"]
        curr_mean = item["current_mean_ns"]
        delta_pct = item["delta_pct"]
        sign = "+" if delta_pct is not None and delta_pct >= 0 else ""
        pct = f"{sign}{delta_pct:.2f}%" if delta_pct is not None else "n/a"
        print(
            f"{name}: {format_ns(base_mean)} -> {format_ns(curr_mean)} ({pct})"
        )
    if extras:
        print("extra benches:")
        for name in sorted(extras):
            print(f"  {name}")

    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
