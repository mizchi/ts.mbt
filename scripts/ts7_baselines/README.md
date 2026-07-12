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

Provenance: microsoft/typescript-go tag `typescript/v7.0.2`
(commit tree `testdata/baselines/reference/submodule/conformance`),
case files from microsoft/TypeScript @ `4d4f005c8541e0255a9d8791205fdce326e462bc`
(the `tsgo-port` branch pin referenced by that tag — the `typescript`
submodule points there).

Regenerate with:

```bash
git clone --filter=blob:none --sparse --depth 1 \
  --branch typescript/vX.Y.Z https://github.com/microsoft/typescript-go /tmp/tsgo
cd /tmp/tsgo
git ls-tree -r HEAD testdata/baselines/reference/submodule/conformance --name-only \
  | sed 's|.*/||' > names.txt
grep '\.errors\.txt$' names.txt \
  | sed -E 's/\.errors\.txt$//; s/\(.*\)$//' | sort -u > tsgo_errors_set.txt
grep -E '\.(types|symbols|js|errors\.txt)$' names.txt \
  | sed -E 's/\.(types|symbols|js|errors\.txt)$//; s/\(.*\)$//' | sort -u > tsgo_ran_set.txt
```

Then update the `typescript` submodule to typescript-go's
`_submodules/TypeScript` pin (`git ls-tree <tag> _submodules/TypeScript`).
