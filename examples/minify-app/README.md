# `minify-app`: an application to measure property mangling on

The other `examples/` directories are bridge-generation fixtures. This
one exists to be minified.

The distinction matters because the type-driven property rename in
`mtsc --mangle-properties` pays off in proportion to how *little* is
publicly reachable, and a library is the worst case for that: everything
it exports is part of somebody's ABI. An application is the best case —
it exports nothing at all, so door 1 (the export surface) is empty and
the only names that must survive are the ones that reach door 2 (a
side-effect sink) or come in from the host.

So this is a small but structurally realistic application: five modules,
about 300 lines, a validate → index → score → render pipeline over
synthetic event data, with ~30 declared interface fields and no
`export` on the entry.

## Measured

`node scripts/compare_terser.mjs --only minify-app`

| variant | bytes | gzip | vs bundle | behaviour |
| --- | --- | --- | --- | --- |
| `--bundle` (no minify) | 6,242 | 1,940 | — | baseline |
| `--minify --mangle --treeshake` | 3,372 | 1,359 | 46% | same output |
| `+ --mangle-properties` | **2,552** | **1,131** | **59%** | same output |
| terser `--compress --mangle` | 3,450 | 1,366 | 45% | same output |
| terser `+ --mangle-props` | 2,101 | 1,153 | 66% | **wrong output** |

`--treeshake` is in the mtsc column because terser's `--compress` drops
unreferenced top-level declarations by itself once `--module` is set.
Comparing without it measured mtsc-without-DCE against
terser-with-DCE.

Both tools minify the same unminified bundle, so the comparison is
between minifiers rather than between bundlers.

Three things to read off it.

**Safe property mangling is worth 25% here** (3,413 -> 2,561; 18% after
gzip) on top of identifier mangling. On the React stack it was worth
exactly 0 bytes — the CJS `exports` object is host-owned, the wildcard
fires, and the analysis correctly declines. Same flag, same compiler,
opposite result, and the difference is the target's shape.

**It beats terser's safe setting by 26%** (2,561 vs 3,450; 17% gzipped).
terser cannot rename a property without being told it is safe, so its
default leaves all of them alone.

**terser's unsafe setting is smaller raw and produces the wrong
answer** — `actors=0 rejected=1206` instead of `actors=17 rejected=4`.
It renamed the fields on the incoming data, which `validate.ts` reads
through computed string keys (`candidate[key]`), so validation rejected
every row. Those are exactly the names `--explain-mangle` lists as
reserved:

```
  enabled — no wildcard; only the names below are reserved.

  read off an external import or ambient global (3)
    log round MAX_SAFE_INTEGER
  reaches a side-effect sink (6)
    length eventId eventKind actorHandle occurredAtMs payloadBytes
  reachable through an observed value tree (4)
    eventKind peakBytes occurrences averageBytes
```

Note also that after gzip the safe output (1,134) is *smaller* than
terser's unsafe one (1,153): renaming fewer names, but consistently,
compresses better than renaming all of them.

Everything else — `trustScore`, `burstFactor`, `volumeRank`, `flagged`,
`byteTotal`, `firstSeenMs`, `displayLabel`, `volumeWeight` and the rest —
is proven unreachable and renamed.

## Running it

```sh
mtsc examples/minify-app/src/main.ts --bundle --out /tmp/app.mjs && node /tmp/app.mjs
mtsc examples/minify-app/src/main.ts --bundle --explain-mangle --out /dev/null
```

The entry type-checks clean, so no `--no-check` is needed.
