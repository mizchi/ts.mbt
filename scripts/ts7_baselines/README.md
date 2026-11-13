# TypeScript 7 conformance truth manifests

The conformance oracle correlates the checker against **TypeScript 7**
(the native compiler, `microsoft/typescript-go`), not the 6.x line.
typescript-go runs the conformance suite from its `_submodules/TypeScript`
pin and stores its complete own baselines under
`testdata/baselines/reference/submodule/conformance/`. Two facts derive
from the baseline FILE NAMES alone, so the repo vendors only name lists:

- `tsgo_ran_set.txt` — test basenames tsgo actually ran (any baseline
  artifact exists: `.types` / `.symbols` / `.js` / `.errors.txt`).
  Tests absent from this list were skipped by tsgo (e.g. every
  `target=es5` / `target=es3` variant — TS7 removed those targets) and
  are classified NOTRUN, excluded from TP/FP counts.
- `tsgo_errors_set.txt` — test basenames where TS7 reports >= 1 error
  (an `.errors.txt` baseline exists). Variant qualifiers
  (`name(target=es2015)`) are stripped; a test counts as erroring if any
  ran variant errors.

Provenance: microsoft/TypeScript tag `v7.1-beta`
(`3e9236361fa97a9e6c685f4833ac457ae2d8c50a`, the `gitHead` npm records for
`typescript@7.1.0-beta`). From 7.1 the native compiler lives in
microsoft/TypeScript itself, with its own conformance cases and baselines in
the same tree:

- baselines: `tsc/testdata/baselines/reference/conformance/` (flat)
- cases:     `tsc/testdata/tests/cases/conformance/`

The cases come from the `typescript7` submodule pinned to that commit. The
older `typescript` submodule (TS 6-era `src/compiler`, `src/lib`, `tests/`)
is kept for the parser tests and benches that read those trees, and is no
longer the conformance corpus.

Regenerate with:

```bash
git clone --filter=blob:none --no-checkout --depth 1 \
  --branch vX.Y-tag https://github.com/microsoft/TypeScript /tmp/ts7
cd /tmp/ts7
git ls-tree -r HEAD tsc/testdata/baselines/reference/conformance --name-only \
  | sed 's|.*/||' > names.txt
grep '\.errors\.txt$' names.txt \
  | sed -E 's/\.errors\.txt$//; s/\(.*\)$//' | sort -u > tsgo_errors_set.txt
grep -E '\.(types|symbols|js|errors\.txt)$' names.txt \
  | sed -E 's/\.(types|symbols|js|errors\.txt)$//; s/\(.*\)$//' | sort -u > tsgo_ran_set.txt
```

Then move the `typescript7` submodule to the same commit, and regenerate
`src/checker/lib_globals.mbt` (`scripts/gen_lib_globals.sh`, which reads
`typescript7/tsc/internal/bundled/libs`). Locally a sparse checkout of
`tsc/testdata/tests/cases/conformance/`, `tsc/testdata/baselines/reference/conformance/`
and `tsc/internal/bundled/libs/` is all the scripts need.
