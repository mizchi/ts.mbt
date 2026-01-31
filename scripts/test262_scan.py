#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
TEST_ROOT = ROOT / "test262" / "test"


@dataclass
class Meta:
    includes: list[str]
    flags: list[str]
    negative: bool


def parse_bracket_list(line: str) -> list[str]:
    m = re.search(r"\[(.*?)\]", line)
    if not m:
        return []
    inner = m.group(1)
    items = []
    for part in inner.split(","):
        item = part.strip()
        if not item:
            continue
        if item.startswith('"') and item.endswith('"') and len(item) >= 2:
            item = item[1:-1]
        items.append(item)
    return items


def parse_meta(text: str) -> Meta:
    includes: list[str] = []
    flags: list[str] = []
    negative = False
    meta_block = ""
    start = text.find("/*---")
    if start != -1:
        rest = text[start + 5 :]
        end = rest.find("---*/")
        if end != -1:
            meta_block = rest[:end]
    lines: list[str] = []
    if meta_block:
        lines = meta_block.splitlines()
    else:
        for line in text.splitlines():
            s = line.strip()
            if not s:
                continue
            if not s.startswith("//"):
                break
            lines.append(s[2:].strip())
    for raw in lines:
        s = raw.strip()
        if s.startswith("*"):
            s = s[1:].strip()
        if s.startswith("includes:"):
            includes.extend(parse_bracket_list(s))
        elif s.startswith("flags:"):
            flags.extend(parse_bracket_list(s))
        elif s.startswith("negative:"):
            negative = True
    return Meta(includes=includes, flags=flags, negative=negative)


SUPPORTED_INCLUDES = {
    "assert.js",
    "sta.js",
    "compareArray.js",
    "nans.js",
    "propertyHelper.js",
    "fnGlobalObject.js",
    "isConstructor.js",
    "deepEqual.js",
    "decimalToHexString.js",
    "proxyTrapsHelper.js",
    "testTypedArray.js",
    "detachArrayBuffer.js",
    "testBigIntTypedArray.js",
}


BANNED_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    # With statement (deprecated, not supported)
    ("with", re.compile(r"\bwith\s*\(")),
    # Eval (complex semantics, not fully supported)
    ("eval", re.compile(r"\beval\s*\(")),
    # Function constructor (dynamic code, not supported)
    ("Function", re.compile(r"\bFunction\s*\(")),
    # Import defer (ES2024, not supported)
    ("import-defer", re.compile(r"\bimport\s+defer\b")),
]


def reason_to_skip(path: Path, text: str) -> str | None:
    meta = parse_meta(text)
    if meta.negative:
        return "negative"
    if "async" in meta.flags:
        return "flag:async"
    missing = [i for i in meta.includes if i not in SUPPORTED_INCLUDES]
    if missing:
        return "includes:" + ",".join(missing)
    for name, pat in BANNED_PATTERNS:
        if pat.search(text):
            return "banned:" + name
    return None


def main() -> int:
    if not TEST_ROOT.exists():
        print(f"test262 not found at {TEST_ROOT}", file=sys.stderr)
        return 1
    allowlist: list[str] = []
    skiplist: list[tuple[str, str]] = []
    for path in sorted(TEST_ROOT.rglob("*.js")):
        if "harness" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except Exception as exc:  # pragma: no cover
            skiplist.append((str(path), f"read-error:{exc}"))
            continue
        reason = reason_to_skip(path, text)
        rel = str(path.relative_to(ROOT))
        if reason is None:
            allowlist.append(rel)
        else:
            skiplist.append((rel, reason))
    (ROOT / "test262.allowlist.txt").write_text("\n".join(allowlist) + "\n")
    (ROOT / "test262.skiplist.txt").write_text(
        "\n".join([f"{p}\t{r}" for p, r in skiplist]) + "\n"
    )
    print(f"allow: {len(allowlist)}")
    print(f"skip: {len(skiplist)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
