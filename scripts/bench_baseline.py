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


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture moon bench baseline")
    parser.add_argument(
        "--output",
        default="bench/baseline.json",
        help="Output JSON path",
    )
    parser.add_argument(
        "--raw",
        default="bench/baseline.txt",
        help="Raw output path",
    )
    parser.add_argument(
        "--target",
        default="native",
        help="Target backend",
    )
    args = parser.parse_args()

    cmd = ["moon", "bench", "--target", args.target]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    output = proc.stdout
    if proc.returncode != 0:
        print(output)
        return proc.returncode

    benches = parse_output(output)
    now = datetime.now(timezone.utc)
    data = {
        "created_at": now.isoformat(),
        "command": " ".join(cmd),
        "target": args.target,
        "benches": benches,
    }

    raw_path = Path(args.raw)
    raw_path.parent.mkdir(parents=True, exist_ok=True)
    raw_path.write_text(output)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(data, indent=2, sort_keys=True))

    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
