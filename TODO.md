# TODO

## Interop Bridge Quality Roadmap: 60% -> 90%

Current assessment: the project is around 55-60% complete as a practical
`TypeScript <-> MoonBit` interoperability bridge. It is usable for selected
packages under supervision, but not yet reliable enough for arbitrary npm or
MoonBit packages without inspection.

Target: reach about 90% practical quality for the declared supported surface.
This does not mean "all TypeScript semantics"; it means generated bridges are
predictable, self-diagnosing, build-backed, and runnable for a broad real-world
corpus without manual edits.

### 90% Quality Gate

- [x] `just ci` passes with all fixture-backed bridge/scaffold checks.
- [x] `just verify-realworld-typescript` passes with a fixed corpus of at least
  20 npm / Node entrypoints.
- [x] `just verify-realworld-moonbit` passes with a fixed corpus of at least 15
  local MoonBit packages.
- [x] Every generated TS -> MoonBit package in the real-world corpus passes:
  `moon check --target js`, `moon test --target js`, `moon build --target js`,
  and a Node smoke run.
- [x] Every generated MoonBit -> TS package in the real-world corpus passes:
  `moon build --target js`, TypeScript declaration typecheck, and a Node import
  smoke run for root and subpath exports.
- [x] Unsupported exports are either 0 or limited to explicitly-budgeted
  ambiguous surfaces with actionable diagnostics.
  - `just bridge-quality` now fails on unbudgeted unsupported exports and
    budgets only the single fixture-backed ambiguous re-export surface with
    explicit candidate diagnostics.
  - `just verify-realworld-typescript` also budgets the single zod
    `ZodFirstPartyTypeKind` empty compatibility enum stub as an omitted,
    runtime-safe unsupported surface.
- [x] `JSValue` usage is classified by reason, and budgets are stable per
  package instead of being treated as an opaque quality number.
  - Real-world TypeScript metrics now split `JSValue` surface usage into
    unknown / any, overload, conditional / mapped, callback / function,
    tuple / array, and namespace / value buckets, with per-package budgets.
- [x] Generated packages require no manual glue edits for the supported corpus.
  - Real-world TypeScript verification hashes generated glue files immediately
    after CLI generation and fails if smoke setup or builds mutate them.
  - Real-world MoonBit verification hashes generated package artifacts and
    fails if typecheck, import smoke, or consumer smoke steps mutate them.
- [x] `README.md` documents the supported surface, unsupported surface, and
  diagnostic interpretation clearly enough for external users.
  - README now documents the supported MoonBit -> TypeScript and TypeScript ->
    MoonBit bridge surfaces, known fallbacks, diagnostics files, quality
    reports, and the no-arbitrary-package-conversion caveat.

### Generated Code Review Follow-up (2026-05-01)

Review status:

- `just verify-examples` passes, including JS build smokes.
- `just bridge-quality` passes with 0 unbudgeted unsupported exports.
- `just verify-realworld-typescript` passes with package-local `JSValue` cause
  budgets and warning-free MoonBit checks.
- A node:fs-only real-world probe builds and runs with 0 unsupported exports.
  Current metrics after callback/option-bag, generic, tuple, and function-type
  cleanup: 2239 bridge lines, 327 declared functions, 12 `JSValue` refs, 2
  `JSValue` functions, and 11 `JSValue` surface lines.

Next implementation tasks:

- [x] Fix callable interface conversion at the JS boundary.
  - Current symptom: React `forwardRef` receives an object converted from
    `ForwardRefRenderFunction` instead of a callable JS function, producing
    `forwardRef requires a render function but was given object.`
  - Target: generated converters for interfaces with a `<call>` / `_call_`
    signature should pass through existing JS functions and wrap MoonBit
    records as callable JS functions while preserving optional properties.
  - Done: `ffi_struct_js_converter_decl` now emits callable wrappers for
    `<call>` interfaces, and the React examples no longer emit the runtime
    `forwardRef` warning.
- [x] Remove package-global opaque generic placeholders such as `type T`,
  `type P`, and `type S` from generated public APIs.
  - Target: preserve representable generics as MoonBit type parameters; if a
    TypeScript generic cannot be represented safely, widen only that local
    boundary to `JSValue` with diagnostics.
  - Done: interface type parameters are preserved in the AST and local generic
    placeholders are widened at the specific boundary instead of emitted as
    package-global opaque types; generated Hono/React/TypeScript AST examples no
    longer leak `type T` / `type P` style placeholders.
- [x] Lower or explicitly budget remaining anonymous literal-union public
  surfaces.
  - Current unbudgeted examples include React `OlHTMLAttributes`, Vitest
    `Assertion` / `VitestUtils` / `SerializedConfig`, and TypeScript AST
    `UserPreferences` / encoded classification request args.
  - Target: create stable synthetic names when a public owner can be inferred,
    otherwise keep the fallback but require an explicit budget and diagnostic.
  - Done: anonymous string literal unions now get stable synthetic enum names
    even when literal values are unsafe as MoonBit case names or appear inside
    function/object/union surfaces. `just bridge-quality` now has 0 unbudgeted
    unsupported exports.
- [x] Reduce node:fs JSValue regressions.
  - Previous node:fs metrics: 2015 bridge lines, 312 declared functions,
    117 JSValue refs, 81 JSValue functions, 0 unsupported exports.
  - Priority: callback aliases, overload-selected sync/promisify wrappers, and
    common option bag aliases such as stat/read/write options.
  - Done: inline callback parameters now receive stable synthetic callback
    opaque types instead of `JSValue`, and named option intersections such as
    `StatOptions & { bigint?: false }` collapse back to the named option bag;
    `StatsBase<T>` / `StatsFsBase<T>` now preserve `T`, and event-map tuple
    payloads keep `Array[Unit]`, `Array[Double]`, or `Array[Error_]` where
    representable. Function types now lower to MoonBit function arrows instead
    of `JSValue`; inline `Promise<{ ... }>` results such as
    `read.__promisify__` / `write.__promisify__` now get named result structs,
    and class method generic bounds keep stream listener event names as
    `String`. Common `writeFile*` / `appendFile*` string data and `cp*` string
    paths now stay typed; `glob*` string patterns and `create*Stream` option
    bags are preserved; promisify file-data wrappers no longer widen string
    data to `JSValue`; stream `path` properties now use `PathLike`, and
    `StatSyncFn` callable options use `StatSyncOptions?`. Stream listener
    payloads now use generated payload opaque types, and redundant
    encoding-dependent overload wrappers with wider returns are skipped.
    `BigIntStats` nanosecond fields now lower to `Int64`, and
    `FSWatcherEventMap.change` uses an opaque payload type instead of
    `Array[JSValue]`; `WatchOptions.encoding` now lowers to `String?`.
    Overload wrapper pruning keeps narrow overloads per arity, so the broad
    `fstatSync` / `statfsSync` union-return wrappers no longer leak `JSValue`
    while bigint variants remain callable. `readFileSync` /
    `readFile.__promisify__` buffer options now use `ReadFileBufferOptions?`,
    `readFileSync` also exposes a `BufferEncoding -> String` wrapper, broad
    `globSync` union-return wrappers are skipped, and `_GlobOptions.cwd`,
    `_GlobOptions.exclude`, and `CopyOptions.filter` now keep concrete MoonBit
    types. Current node:fs budget is 11 `JSValue` surface lines and 2
    `JSValue` functions.
  - Remaining quality debt: event payloads with heterogeneous values still use
    opaque payload boundaries, and custom `fs` implementation hooks / watcher
    ignore predicates still require `JSValue`.
- [x] Split large generated MoonBit packages into reviewable files.
  - Target layout: `types.mbt`, `externs.mbt`, `converters.mbt`, and
    `guards.mbt` for large TS -> MoonBit scaffolds, while preserving generated
    `bridge.mbti` and package metadata.
  - Done: generated TS -> MoonBit packages over the review threshold now split
    MoonBit implementation code into `types.mbt`, `converters.mbt`,
    `externs.mbt`, `guards.mbt`, and `bridge.mbt`. Example/scaffold checks,
    real-world manifests, and bridge quality metrics now count the split source
    files instead of assuming all implementation code lives in `bridge.mbt`.
- [x] Add regression rails for generated-code ergonomics.
  - [x] React `forwardRef` warning should fail the smoke rail.
  - [x] TypeScript AST transformer smoke should reduce required `unsafeCast`
    usage around `ScriptTarget`, `transform`, visitors, and transformed arrays.
  - [x] node:fs budget regressions should fail with package-local diagnostics.

### Package-Specific Practical Coverage Pass (2026-05-01)

Implemented in the current real-world TypeScript probe order:

- [x] Small Node built-ins now target zero public `JSValue` fallback.
  - `node:path`, `node:os`, `node:url`, `node:querystring`, and `node:buffer`
    all generate with `JSValue surface = 0` in
    `_build/realworld-typescript/METRICS.md`.
  - The corresponding real-world budgets in
    `scripts/verify_realworld_typescript.sh` are fixed at 0 so regressions fail.
- [x] `node:crypto` focused pass.
  - Common option bags, AAD options, key-like parameters, WebCrypto algorithm
    parameters, `generateKeyPair` callbacks, and broad `generatePrimeSync`
    overloads are now specialized or pruned.
  - Current `node:crypto` metrics: `JSValue refs = 0`, `JSValue functions = 0`,
    `JSValue surface = 0`.
- [x] Hono practical route API smoke.
  - The real-world smoke now writes a route as
    `app.hono_get("/", realworld_hono_handler)`.
  - Route paths lower to `String`, handlers lower to `(Context) -> Response`,
    and common `Context` response helpers such as `text` return `Response`.
  - Current Hono budget is tightened to 55 `JSValue` surface lines and 36
    `JSValue` functions; remaining fallbacks are mostly generic context,
    router, and validation data surfaces.
- [x] Zod / Valibot / Preact fallback policy documented.
  - These packages remain buildable and smoke-tested, but their high-order
    schema, parser, JSX, and component generic surfaces are explicitly
    documented as budgeted `JSValue` fallback areas rather than natural MoonBit
    APIs.
- [x] Split real-world packages into explicit fallback policy classes.
  - `just verify-realworld-typescript` now appends a fallback policy table to
    `_build/realworld-typescript/METRICS.md` and fails if a new corpus package
    is not classified.
  - Active naturalization targets: Hono, React Router, JOSE, Glob, `date-fns`,
    `magic-string`, `source-map`, `node:sqlite`, `node:fs`, `node:assert`, and
    `node:util`.
  - Budgeted fallback probes: Zod, Valibot, Preact, and broad Playwright
    event/callback surfaces. These should stay buildable and smoke-tested, but
    are not currently claimed as naturally typed MoonBit APIs.
- [x] Add a first Glob naturalization for function-valued const exports.
  - `declare const hasMagic: (pattern: string | string[], options:
    GlobOptions) => boolean` now keeps the existing getter but also emits a
    MoonBit string-subset wrapper as `has_magic(pattern : String, options :
    GlobOptions) -> Bool`.
  - Function-valued const exports whose signatures do not widen to `@js.Any`
    also get direct callable wrappers, so `escape(pattern, options)` and
    `unescape(pattern, options)` no longer require `get_escape()` /
    `get_unescape()` first.
  - The real-world Glob smoke now calls `escape`, `unescape`, and
    `has_magic("src/*.mbt", options)` directly instead of manufacturing a
    `JSValue` pattern argument or calling getter-returned functions.
  - The Hono real-world example smoke now uses a typed MoonBit route handler
    `(Context) -> Response` directly with `app.get("/hello", handler)`.

### Phase 1: Measurement and Diagnostics (60% -> 65%)

- [x] Add a persistent quality score report for bridge generation.
  - Include generated lines, exported declarations, unsupported exports,
    `JSValue` refs, `JSValue` functions, runtime smoke coverage, and diagnostics.
  - Initial fixture-backed report is generated by `just bridge-quality` at
    `_build/bridge-quality/REPORT.md`.
- [x] Split `JSValue` metrics by cause:
  - unknown / any
  - overload fallback
  - conditional / mapped type fallback
  - callback / function type fallback
  - tuple / array fallback
  - namespace / value fallback
  - Initial breakdown is heuristic over generated `bridge.mbti` surface lines
    in `just bridge-quality`.
  - Real-world TypeScript verification uses the same buckets in
    `_build/realworld-typescript/METRICS.md` and fails on unbudgeted growth.
- [x] Make `SCAFFOLD_DIAGNOSTICS.md` explain what was widened, omitted, or
  bridge-wrapped, and whether each item is runtime-safe.
  - Diagnostics now include a summary table with decision, reason, runtime
    safety, and a decision vocabulary for widened / omitted / bridge-wrapped
    surfaces.
- [x] Add a `just bridge-quality` task that runs the fixture corpus and prints a
  single summary table.
- [x] Store real-world corpus package versions / paths in one config file so the
  score is reproducible across machines.
  - TypeScript real-world corpus entries now live in
    `corpus/realworld-typescript.tsv`; `scripts/verify_realworld_typescript.sh`
    records that path in `METRICS.md`.

### Phase 2: TypeScript -> MoonBit Surface Coverage (65% -> 72%)

- [x] Harden npm / Node type resolution:
  - [x] package `exports`
  - [x] `types` / `typings`
  - [x] subpath exports
  - [x] `typesVersions`
  - [x] `@types/*` fallback
  - [x] `node:*` built-in modules
  - Resolver tests now cover package fields, exports conditions, wildcard
    exports, subpaths, `typesVersions`, unscoped and scoped `@types` fallback,
    and `node:*` built-in declarations via `@types/node`.
- [x] Improve overload handling.
  - [x] Prefer overloads that can be represented with concrete MoonBit types.
    - Direct local overload resolution now uses the same widening score as the
      final generated binding collapse, so broad `unknown` / `any` signatures no
      longer hide later concrete signatures.
  - [x] Emit multiple safe wrappers when overloads are materially different and
    nameable.
    - Nameable non-preferred signatures now emit stable suffixed wrappers, e.g.
      `makeCounter_number`, while preserving the original runtime export name in
      generated JS FFI glue.
  - [x] Keep a stable fallback rule when overloads collapse to `JSValue`.
    - Equal-score overloads keep declaration order and still collapse to one
      generated binding.
- [x] Expand common utility type lowering:
  - [x] `Pick` over resolvable interfaces and literal keys.
  - [x] `Omit` over resolvable interfaces and literal keys.
  - [x] `Record` as a named opaque JS object boundary.
  - [x] `Exclude` over directly comparable union members.
  - [x] `Extract` over directly comparable union members.
  - [x] `NonNullable` over optional-like unions.
  - [x] simple `ReturnType` / `Parameters` for direct function types.
- [x] Support the common mapped-type subset needed by real declaration files.
  - [x] Lower `Partial<T>`, `Required<T>`, and `Readonly<T>` over resolvable
    interfaces into named MoonBit option-bag structs.
  - [x] Parse and lower inline mapped object types with literal keys such as
    `{ [K in "a" | "b"]: T }`.
- [x] Support the common conditional-type subset used by React, Hono, Zod, and
  Node declarations.
  - [x] Lower statically decidable `A extends B ? X : Y` when both sides are
    direct primitive / union types.
  - [x] Lower `Awaited<Promise<T>>` / `Awaited<PromiseLike<T>>`.
  - [x] Cover standard conditional utilities already represented as direct
    utility forms: `NonNullable`, `Exclude`, `Extract`, direct `ReturnType`, and
    direct `Parameters`.
  - [x] Preserve or resolve infer-based conditional aliases instead of widening
    them to `JSValue`.
    - [x] Resolve concrete infer patterns such as
      `Promise<string> extends Promise<infer T> ? T : never`.
    - [x] Preserve generic infer aliases that still depend on type parameters.
      - Generic conditional aliases are retained in the AST and resolved when
        applied to concrete type arguments, e.g. `UnwrapPromise<Promise<string>>`.
- [x] Preserve optional and readonly field information where MoonBit can express
  it; otherwise emit diagnostics instead of silent widening.
  - Optional fields are preserved as optional-like MoonBit surface types.
  - Interface `readonly` fields are retained as metadata and emitted as
    declaration / FFI diagnostics because generated MoonBit structs do not
    enforce TypeScript readonly semantics.

### Phase 3: Runtime Bridge Correctness (72% -> 78%)

- [x] Make runtime namespace handling complete for declaration-merge patterns:
  `function x` + `namespace x`, `class X` + `namespace X`, and value namespaces.
  - Declaration-merged namespace fixtures now cover root function/class/value
    exports, runtime namespace member glue, and namespace-local type references
    such as `make.Options` lowering to `MakeOptions` without leaking
    unqualified helper types.
- [x] Strengthen CJS / ESM interop:
  - `export =`
  - `export default`
  - synthetic default imports
  - namespace imports
  - mixed named/default re-exports
  - Generated fixture smokes now cover `.cjs` `export = namespace`
    runtimes through synthetic default import, `node:path` namespace imports,
    relative/parent-relative default exports, bare CJS package default
    functions, and mixed default/named class re-exports.
- [x] Add runtime smokes for async and Promise-returning APIs.
  - `Promise<T>` / `PromiseLike<T>` now lower to `@js.Promise[T]` in
    declaration and FFI generation, and a generated JS-target fixture awaits
    Promise-returning APIs with `.wait()`.
- [x] Add runtime smokes for callback APIs where the callback can be represented
  safely.
  - Callback parameters are currently represented as `JSValue` / `@js.Any`;
    the generated fixture passes required and optional JS callbacks through
    MoonBit, verifies the runtime side effect on the JS target, and covers
    MoonBit `Option` unwrapping to JS `undefined` / raw callback values.
- [x] Add runtime smokes for object option bags with optional fields.
  - Generated fixture smoke now calls a declaration-merged namespace function
    with a runtime-created `MakeOptions` object containing an optional field,
    then checks the JS target bridge through `moon check` and
    `moon test --target js`.
- [x] Add runtime smokes for class instance properties, static properties, and
  static methods.
  - Existing generated fixtures exercise instance getters/setters, mutable
    static properties, readonly static properties, and static factory methods
    across direct and re-exported class bindings.
- [x] Ensure generated `bridge.js` never imports a missing runtime binding
  without a diagnostic.
  - `unique symbol` marker exports, such as `node:assert`'s internal
    `kOptions`, are now treated as non-runtime declarations and are omitted
    from generated JS glue instead of being imported.

### Phase 4: MoonBit -> TypeScript Package Quality (78% -> 84%)

- [x] Improve method / constructor facade generation beyond the current narrow
  safe subset.
  - Facade generation now includes non-generic async constructors and instance
    methods, emits Promise-returning TypeScript declarations, and post-processes
    generated JS so plain async exports return Promises while async+raise exports
    preserve the Result wrapper expected by the declaration contract.
- [x] Define the public rule for traits:
  - Public traits are represented as declaration-only structural TypeScript
    interfaces.
  - Local `impl Trait for Type` relationships are represented in `.d.ts` output
    as `extends Trait` or type intersections where possible.
  - Trait methods are not generated as runtime bridge exports or facade
    functions; omitted runtime members remain visible through autolink
    diagnostics.
- [x] Preserve MoonBit `raise` effects in TypeScript declarations as a documented
  error contract.
  - Top-level and trait method `raise` effects now render as
    `Result<Return, ErrorType>` in generated TypeScript declarations, matching
    the JS backend's result-wrapper runtime shape.
- [x] Improve child-package and subpath export coverage:
  - [x] root exports
  - [x] nested package exports
  - [x] generated `package.json` `exports`
  - [x] matching JS and `.d.ts` paths
  - The counter scaffold fixture now includes `./child/grand`, and
    `verify-scaffolds` imports the generated nested subpath through Node while
    checking matching package metadata and `.d.ts` declarations.
- [x] Add generated source map and package metadata checks to the verification
  rail.
  - `verify-scaffolds` checks generated `package.json` package names, subpath
    exports, runtime JS files, and source map files for the scaffold fixtures.
- [x] Make facade generation deterministic and diff-friendly for review.
  - Glue declarations, `link.js.exports`, generated package `exports`, and
    child-package runtime re-export files are sorted with an explicit ascending
    string comparator instead of relying on source or map iteration order.

### Phase 5: Real-World Corpus Expansion (84% -> 88%)

- [x] Lock a TypeScript corpus that covers different API shapes:
  - small function libraries: `clsx`, `date-fns`
  - class/value libraries: `chalk`, `dotenv`
  - schema libraries: `zod`
  - web libraries: `hono`, `preact`
  - Node built-ins: `node:fs`, `node:sqlite`, `node:path`, `node:crypto`,
    `node:os`, `node:url`, `node:querystring`, `node:assert`, `node:util`,
    `node:buffer`
  - callback-heavy APIs: `node:fs`, `node:util`
  - Promise-heavy APIs: `execa`
  - CJS / export-assignment style APIs: `source-map`, Node built-ins
  - Current locked probe entries: `clsx`, `chalk`, `dotenv`, `ignore`, `hono`,
    `zod`, `date-fns`, `colorette`, `magic-string`, `source-map`, `valibot`,
    `immer`, `execa`, `preact`, `node:sqlite`, `node:fs`, `node:path`,
    `node:crypto`, `node:os`, `node:url`, `node:querystring`, `node:assert`,
    `node:util`, `node:buffer`.
- [x] Lock a MoonBit corpus that covers:
  - root-only packages
  - child-package exports
  - effectful APIs
  - generic APIs
  - private root types
  - packages with external JS bindings
  - Current checked entries: `mizchi/ast_printer`, `mizchi/js`,
    `mizchi/jsonschema`, `mizchi/markdown`, `mizchi/nom`,
    `mizchi/pixelmatch`, `mizchi/ripple`, `mizchi/semver`, `mizchi/svg`,
    `mizchi/syntree`, `mizchi/tempfile`, `mizchi/threads`, `mizchi/vfs`,
    `mizchi/jwt.mbt`, `mizchi/zlib`.
- [x] Add per-package smoke programs that use meaningful APIs, not only compile
  the generated bridge.
  - The TypeScript real-world corpus now emits package-specific MoonBit smoke
    programs and runs the built JS with Node after `moon build --target js`.
  - The MoonBit real-world corpus now includes package-specific Node smokes for
    representative APIs, including `svg`, `threads`, and `zlib`.
- [x] Keep each real-world failure as a minimized fixture before fixing it.
  - The `node:assert` missing runtime binding failure is covered by
    `unique-symbol-runtime-export-entry.d.ts`.
- [x] Track corpus status in a generated markdown report checked by CI or an
  opt-in verification task.
  - `just verify-realworld-typescript` writes
    `_build/realworld-typescript/METRICS.md`.
  - `just verify-realworld-moonbit` writes
    `_build/realworld-moonbit/REPORT.md`.

### Phase 6: Productization and Safety (88% -> 90%)

- [x] Define the public CLI contract:
  - [x] `tsmbt --input mizchi/foo --out dist`
  - [x] `tsmbt --input npm-package --out dist --direction ts-to-mbt`
  - [x] `--module-spec`
  - [x] `--diagnostics`
  - [x] `--strict`
  - Unified CLI help, parser tests, and README now document the public contract.
- [x] Add strict mode that fails on any unsupported export or unbudgeted
  `JSValue` fallback.
  - TS -> MoonBit strict mode rejects ambiguous/unsupported export surfaces
    before generation and generated `JSValue` fallback occurrences after
    generation, while writing diagnostics.
  - MoonBit -> TypeScript strict mode rejects omitted autolink members reported
    in `AUTOLINK_DIAGNOSTICS.md`.
- [x] Add non-strict mode that always emits a buildable scaffold with diagnostics
  when possible.
  - Unified TS -> MoonBit now always writes `SCAFFOLD_DIAGNOSTICS.md` or the
    requested `--diagnostics` path after scaffold generation.
  - Unified MoonBit -> TypeScript continues to write `AUTOLINK_DIAGNOSTICS.md`
    and can mirror it to `--diagnostics`.
- [x] Add snapshot tests for generated file layout and package metadata.
  - Unified MoonBit -> TypeScript and TypeScript -> MoonBit tests now assert
    generated file layouts and package metadata for the public CLI path.
- [x] Document supported TypeScript and MoonBit subsets with examples.
  - README now includes supported subset examples for both bridge directions.
- [x] Add a release checklist:
  - [x] fixture CI
  - [x] real-world TypeScript probe
  - [x] real-world MoonBit probe
  - [x] generated docs update
  - [x] changelog entry

### Explicit Non-Goals Before 90%

- [ ] Do not attempt full TypeScript type-checker parity.
- [ ] Do not implement arbitrary TypeScript conditional/mapped type semantics
  unless a real-world target needs the subset.
- [ ] Do not promise arbitrary npm package conversion without diagnostics.
- [ ] Do not hide widened or omitted API surfaces; every fallback must be
  inspectable.

## Parser / Semantics Real-World Gaps

### Current bug
- [x] `emit-moonbit-decl` / `emit-moonbit-js-ffi` should not resolve non-exported opaque type imports.
  - Symptom: an entry like `import { ResultAsync, type Result } from "neverthrow"` crashed when the package actually existed under `/tmp/.../node_modules`.
  - Cause: `load_type_module_graph` eagerly resolved every import specifier even when the imported binding was never exported or re-exported from the entry surface.
  - Fix direction: keep re-exports / exported imports in the graph, but leave plain opaque imports unresolved.

### Remaining work
- [x] Add a stable end-to-end regression harness for the external `/tmp/tsmbt-realworld-check` repro instead of relying on ad-hoc local verification.
  - Covered by the `/tmp/ts_mbt_neverthrow_like_*` regression tests in `src/main_wbtest.mbt`, which exercise `emit_moonbit_decl_text` / `emit_moonbit_js_ffi_texts` against a pnpm-style temp project layout.
- [x] Minimize a fixture from the actual `neverthrow` package if more parser coverage is needed beyond the graph-resolution fix.
  - Covered by `fixtures/resolver/project/types/neverthrow-like-entry.d.ts` plus the pnpm-style `fixtures/resolver/project/node_modules/neverthrow-like` fixture, and exercised through decl / JS FFI / scaffold generation.

## MoonBit / TypeScript Package Bridge Plan

Generate TypeScript-consumable bridge artifacts from MoonBit package interfaces without hand-writing `link.js.exports`, and keep the reverse `TS -> MoonBit` path aligned around the same surface model.

### Batch 1: MBTI autolink bootstrap

- [x] Emit `link.js.exports` JSON config from `.mbti` top-level public free functions.
- [x] Exclude methods / constructors / trait methods from the generated JS export surface.
- [x] Add CLI coverage so the generated config can be written directly from `pkg.generated.mbti`.

### Next batches

- [x] Add a recursive `.mbti` resolver so generated `.d.ts` imports can be rewritten to generated sibling packages instead of raw MoonBit package specifiers.
- [x] Add a high-level `MoonBit -> TS package scaffold` command that generates temporary autolink glue, runs `moon build --target js`, and emits a JS-backed `.d.ts` package.
- [x] Align the reverse `TS -> MoonBit bridge package` flow on the same top-level export surface model and resolver assumptions.

## Bridge / Scaffold Operational Hardening

### P0

- [x] Harden unsupported export handling in `emit-moonbit-scaffold-from-ts`.
  - Namespace exports are supported as opaque getters, and ambiguous re-exports no longer block scaffold generation; they are widened/omitted consistently with the low-level emitters and reported in `SCAFFOLD_DIAGNOSTICS.md`.
- [x] Add `just verify-scaffolds` and wire it into `just ci`.
  - Acceptance: `emit-typescript-scaffold-from-mbti` produces build-backed `index.js`, is compiled with `tsc`, and is smoke-tested through Node import; `emit-moonbit-scaffold-from-ts` is compiled/tested with `moon check/test --target js`.
- [x] Add external import rewrite mapping for `emit-typescript-scaffold-from-mbti`.
  - `emit-typescript-package-from-mbti` / `emit-typescript-scaffold-from-mbti` now accept an optional JSON rewrite map and apply it before writing external `.d.ts` imports.

### P1

- [x] Generate publish-ready metadata for `MoonBit -> TS` scaffold output.
  - `emit-typescript-scaffold-from-mbti` now writes `package.json` with `name`, `type`, `types`, `import`, and per-subpath `exports.types` entries alongside build-backed `index.js` / `.d.ts` files. Temporary `moon.pkg.json` glue is created only inside the source module and removed after `moon build --target js`.
- [x] Decide how to handle methods / static members omitted from `link.js.exports`.
  - The default scaffold still emits `AUTOLINK_DIAGNOSTICS.md` so omissions are explicit, strips runtime-inaccessible method declarations from package `.d.ts`, and `emit-typescript-facade-scaffold-from-mbti` now provides an opt-in wrapper path for root-package local non-generic methods / constructors.

### P2

- [x] Minimize a stable real-world fixture from `neverthrow` if broader package-surface coverage is still needed.
  - `just verify-scaffolds` now exercises the stable `neverthrow-like` fixture end-to-end, including generated MoonBit scaffold compile/test under JS.

### P3

- [x] Revisit broader `namespace export` support after the scaffold path is stable.
  - `emit-moonbit-scaffold-from-ts` now accepts namespace exports and exposes them as opaque getter functions in the generated package. Ambiguous re-exports are emitted conservatively and surfaced in scaffold diagnostics instead of failing fast.

## TS Bridge Constraints

- [x] Prefer direct `#module("...")` imports when the runtime `moduleSpec` is non-relative.
  - Works for bare specifiers, `node:*`, and rooted specifiers like `/src/api/client.ts`.
  - This now covers top-level function exports, instance methods/properties, and class constructors.
  - Bare package `default` function exports are intentionally routed through
    `bridge.js`; this avoids MoonBit JS backend default binding mismatches for
    CJS packages such as `express`.
- [x] Keep `bridge.js` fallback for relative module specs like `./client.js` and `../client.js`.
  - MoonBit currently rejects relative paths in `#module("...")`.
- [x] Keep wrappers for static members / value exports / namespace exports for now.
  - `= "Counter.from"` / `= "Counter.version"` style dotted import names compile poorly in the current JS backend.
  - `#module(...)` combined with inline `#|` JS also does not lower correctly for imported module bindings in the current backend.

## TS Enum / Literal Union Design

Goal: represent the safe TypeScript enum-like subset as MoonBit `enum` without
lying at the JS boundary. The generated public MoonBit API should be pleasant to
use, while the generated bridge must still pass the exact primitive values that
TypeScript runtimes expect.

### Scope

- [x] Support named string literal unions as closed MoonBit enums:
  - `type Variant = "primary" | "secondary"` ->
    `pub(all) enum Variant { Primary; Secondary }`.
  - Optional unions preserve optionality:
    `"primary" | "secondary" | undefined` -> `Variant?`.
  - Direct anonymous literal unions on exported fields / params / returns now
    receive stable synthetic names such as `ButtonOptionsVariant` and
    `RenderButtonReturn`.
- [x] Support boolean literal unions only when they are not just `boolean`:
  - `true | false` remains `Bool`.
  - `true | undefined` remains `Bool?`.
  - Named boolean literal aliases now resolve through primitive `Bool` /
    `Bool?` bridge signatures instead of emitting enum wrappers.
- [x] Support numeric literal unions only when every member is an integer-like
  literal and the runtime bridge can convert losslessly.
  - [x] Named numeric literal union aliases lower to closed MoonBit enums and
    bridge through raw `Int` params / returns.
  - [x] Direct anonymous numeric literal unions use the same synthetic naming
    pass and bridge through raw `Int` params / returns.
- [x] Support ambient / declaration enum surfaces:
  - `declare enum Mode { Read = "read" }`
  - `declare const enum Mode { Read = "read" }`
  - implicit numeric members are allowed only when all previous values can be
    evaluated statically.
  - [x] Parser preserves `declare enum` / `declare const enum` in `TsModule`,
    including declared namespaces, and bridge package output now exposes those
    enums in both `bridge.mbt` and `bridge.mbti`.
  - [x] Raw extern wrappers keep string enums primitive and expose public
    MoonBit enum wrappers for params and returns.
  - [x] Optional string enum params / returns use `Variant?` conversion and
    keep JS `undefined` behavior.
  - [x] Raw extern wrappers keep statically evaluable numeric enums as `Int`
    and expose public MoonBit enum wrappers for params and returns, including
    optional `Variant?` conversion.
- [x] Defer heterogeneous enum unions and non-literal computed enum values to
  the existing primitive / `JSValue` fallback with diagnostics.

### Internal Model

- [x] Replace or extend the current `TsType::Literal(String)` representation.
  - Current parser stores string `"1"` and numeric `1` both as `Literal("1")`,
    which is not precise enough for bridge conversion.
  - Add a typed literal model, e.g. `TsLiteralValue::{String, Number, BigInt,
    Bool}`, and keep helper functions so existing `keyof` / object-key logic
    can continue treating string keys uniformly.
  - `TsType` now keeps string literal/object keys as `Literal(String)` while
    preserving non-string literal types as `NumberLiteral`, `BigIntLiteral`,
    and `BooleanLiteral`.
- [x] Add AST nodes for enum declarations:
  - `TsEnumDecl { name, members, is_const, is_declare }`
  - `TsEnumMember { name, value : TsLiteralValue? }`
  - Store them in `TsModule` and `TsModuleBlock`, parallel to interfaces and
    type aliases.
  - [x] Added `TsEnumDecl`, `TsEnumMember`, and `TsEnumMemberValue` to
    `TsModule`; module-block export collection now recognizes
    `export declare enum` for bridge export surfaces.
  - [x] `TsEnumMember.is_computed` now distinguishes implicit numeric enum
    members from non-literal computed initializers.
  - [x] `TsModuleBlock` still needs a first-class enum array if script-level
    enum declarations need to be preserved beyond export metadata.
- [x] Normalize type aliases that are pure string literal unions into an enum-lowering
  candidate before `emit_moonbit_decl` / `emit_moonbit_js_ffi` renders types.
  - Keep the original alias name as the MoonBit enum name.
  - If the alias is anonymous inside a parameter or field, keep the current
    primitive fallback until a stable synthetic naming rule is needed.

### MoonBit Surface

- [x] Emit public enum declarations in both `bridge.mbt` and `bridge.mbti`.
  - This must mirror the recent struct rule: generated implementation and
    interface files expose the same public shape.
  - [x] Ambient enum exports are emitted as `pub(all) enum` in both package
    implementation and interface output.
  - [x] Runtime TypeScript `export enum` declarations are preserved through
    `TsModuleBlock` export discovery and emitted in package bridge output.
- [x] Generate stable constructor names:
  - sanitize to PascalCase;
  - suffix MoonBit keywords;
  - disambiguate collisions deterministically;
  - preserve the original TS literal in generated conversion helpers.
- [x] Keep raw externs primitive and wrap them for string enums:
  - Params: public function accepts `Variant`, private/raw extern accepts
    `String`.
  - Returns: raw extern returns primitive, public wrapper converts to
    `Variant`.
  - Optional params / returns use `Variant?` wrappers and keep JS `undefined`
    behavior through generated optional conversion helpers.

Example target shape:

```moonbit
pub(all) enum ButtonVariant {
  Primary
  Secondary
} derive(Eq, Debug)

fn ButtonVariant::to_js(self : ButtonVariant) -> String {
  match self {
    Primary => "primary"
    Secondary => "secondary"
  }
}

fn button_variant_from_js(value : String) -> ButtonVariant {
  match value {
    "primary" => Primary
    "secondary" => Secondary
    _ => abort("unexpected ButtonVariant value")
  }
}

extern "js" fn render_button_raw(variant : String) -> Unit = "__ts_mbt_render_button"

pub fn renderButton(variant : ButtonVariant) -> Unit {
  render_button_raw(variant.to_js())
}
```

### JS Bridge Rules

- [x] Do not pass MoonBit enum runtime objects directly to JS APIs for string
  enums.
  - MoonBit JS backend enums are tagged values; TypeScript libraries expect the
    primitive literal value.
- [x] Prefer MoonBit-side conversion wrappers over JS-side enum construction.
  - JS bridge code cannot reliably construct MoonBit enum values unless those
    constructors are exported by the compiled MoonBit package.
  - Return conversion should therefore happen in generated MoonBit wrapper
    code from raw primitive externs.
- [x] Reuse the existing optional object-field converter only after enum values
  have been converted to primitives.

### Diagnostics and Safety

- [x] Add diagnostics for every enum-like surface that is not lowered:
  - [x] mixed string/number enum;
  - [x] computed enum member;
  - [x] duplicate literal values after sanitization;
  - [x] mixed / non-integer / bigint named literal-union aliases;
  - [x] anonymous literal union without a stable public name.
- [x] Keep strict mode behavior unchanged: unsupported enum lowering in a
  public surface must either fall back within budget or fail with an actionable
  diagnostic.
- [x] Add real-world probes after fixtures pass:
  - [x] Node string modes / flags;
  - [x] React string literal props;
  - [x] Hono option modes;
  - [x] TypeScript AST `SyntaxKind`-style numeric enum as an `Int` bridge
    stress case.

### TDD Order

- [x] Red: parser tests for string/numeric/const enum declarations and typed
  literal unions.
- [x] Green: AST + parser support without bridge lowering.
- [x] Red: declaration generation tests for named literal-union aliases.
- [x] Green: emit MoonBit enum declarations in `.mbt` / `.mbti`.
- [x] Red: JS-target smoke where a MoonBit enum argument reaches a TS function
  expecting a string literal.
  - `fixtures/bridge_smoke/enum-entry.d.ts` verifies generated code passes
    primitive string enum values through `moon check --target js` and
    `moon test --target js`.
- [x] Green: raw extern + public wrapper conversion for params.
- [x] Red: JS-target smoke where a TS function returns a literal union and
  MoonBit pattern matches the result.
  - Named string literal union aliases are covered by
    `fixtures/bridge_smoke/literal-union-alias-entry.d.ts`.
- [x] Green: primitive return conversion with an explicit unexpected-value
  abort path.
- [x] Refactor: share enum metadata between decl, FFI, and package bridge
  emitters so literal-union and `declare enum` use the same lowering path.
  - [x] Share ambient enum case/value/unsupported-reason lowering between
    declaration diagnostics and FFI generation.
  - [x] Share literal-union alias enum declaration lowering through
    `enum_lowering_type_alias_enum_decl`.

## Normalized DTS Shape-Merge Scope

- [x] Keep object-shape compatibility checks inside `src/bridge/object_shape_merge.mbt`.
  - The helper exists to support `normalize-moonbit-dts`, not to become a full TypeScript checker.
- [x] Keep the shape-merge scope narrow.
  - Current responsibility: decide whether object-like interface expansions can be flattened safely, or should fall back to intersections.
  - Current coverage: duplicate properties, `readonly`, optional-property keys, and "do not merge methods / overload-like members".
- [x] Avoid growing the bridge normalization helper into a full semantic checker unless a separate goal is explicitly chosen.
  - If future work needs real TS semantics, define that as a separate milestone instead of quietly expanding the normalization helper.

## Bridge Const-Table Batch Plan

Reduce the need to pick one edge case at a time by shipping the next `default export const table` batch together and keeping the smoke rail in sync.

### Batch scope

- [x] `import * as tables from "./x"` where `x` exports a const table.
- [x] `import tables from "./x"` where `x` re-exports a named `const TABLES`.
- [x] `import tables from "./x"` where `x` directly `export default { ... }`.
- [x] `import tables from "./x"` where `x` does `export default { ... } as const`.
- [x] `import tables from "./x"` where `x` does `export default (() => ({ ... }))()`.
- [x] `import tables from "./x"` where `x` does `export default (() => { const ...; return TABLES })()`.
- [x] `import tables from "./x"` where `x` does `export default (function() { const ...; return TABLES })()`.

### Acceptance rail

- [x] Add parser regression proving exported const-value collection for each new default-export shape.
- [x] Add decl / JS FFI / bridge-package regressions for each new shape.
- [x] Add bridge smoke fixtures so `just verify-generated-fixtures` and `just ci` execute the generated package under JS.

### Next batch: IIFE local let handling

- [x] `import tables from "./x"` where `x` does `export default (() => { let ...; return TABLES })()`.
- [x] `import tables from "./x"` where `x` does `export default (function() { let ...; return TABLES })()`.
- [x] Keep local `let` mutation conservative: if the returned table depends on reassigned locals, widen instead of resolving statically.
- [x] Add parser / decl / JS FFI / bridge-package regressions for the `let` cases.
- [x] Add bridge smoke fixtures for positive `let` cases and the conservative widened case.

### Next batch: IIFE local mutation conservative handling

- [x] `import tables from "./x"` where `x` mutates `KEYS.nested` before returning the table.
- [x] `import tables from "./x"` where `x` mutates `INDEXES[0]` before returning the table.
- [x] Keep local property/index mutation conservative even when the final runtime value is unchanged.
- [x] Add parser / decl / JS FFI / bridge-package regressions for the mutation cases.
- [x] Add bridge smoke fixtures for the conservative widened mutation cases.

## React / JSX Real-World Support

Keep pushing real package support through `.d.ts` surface parsing and scaffold generation before adding a full JSX expression parser.

### Current status

- [x] Accept `export as namespace ...` without crashing `emit-moonbit-scaffold-from-ts`.
- [x] Flatten `export = React; declare namespace React { ... }` style surfaces into top-level scaffold exports.
- [x] Surface nested `JSX` namespace types from `react`, `react/jsx-runtime`, and `react/jsx-dev-runtime`.
- [x] Normalize the first round of React utility types:
  - `PropsWithChildren<T>`
  - `ComponentProps<"tag">`
  - `ComponentPropsWithoutRef<"tag">`
  - `ComponentPropsWithRef<"tag">`
  - nested `PropsWithChildren<ComponentPropsWithoutRef<...>>`
- [x] Convert known React hook tuple returns into named synthetic result types.
- [x] Preserve optional React-style props/params as `T?` instead of widening everything to `JSValue`.
- [x] Make generated MoonBit identifiers safe for reserved words and dotted ambient names.

### Next work

- [x] Reduce widening around React overload-heavy APIs.
  - Priority targets: `createElement`, `cloneElement`, `forwardRef`, `memo`.
  - [x] Lower `keyof JSX.IntrinsicElements` parameters to `String` for `createElement` / JSX runtime entrypoints instead of `JSValue`.
- [x] Model exotic/callable component surfaces more explicitly.
  - Priority targets: `FunctionComponent`, `ForwardRefExoticComponent`, `MemoExoticComponent`, `NamedExoticComponent`.
  - Callable React component surfaces are emitted as opaque external JS callable types in FFI output instead of fake record structs with `<call>` fields.
- [x] Improve utility/conditional type lowering beyond the first pass.
  - Priority targets: `ReactNode`, `ComponentRef`, `ElementRef`, `LibraryManagedAttributes`, `RefAttributes`.
  - `Partial<T>` / `Readonly<T>` pass through to `T`; `LibraryManagedAttributes<C, P>` lowers to `P`; `ComponentRef<T>` / `ElementRef<T>` lower to `Ref`; `ReactNode` lowers to `JSValue` / `@js.Any` at the generated bridge boundary.
- [x] Add stable end-to-end verification for generated React scaffolds under `moon check/test --target js`.
  - `just verify-scaffolds` now checks React-like JSX, `react/jsx-runtime`, `react/jsx-dev-runtime`, and the Hono options fixture with generated packages under the JS target. The React cases use a local `mizchi/js/core` stub instead of depending on a separate checkout.
- [x] Add stable fixture coverage for `react`, `react/jsx-runtime`, `react/jsx-dev-runtime`, and `hono/jsx`.
  - Keep real-world probe findings as minimized fixtures instead of ad-hoc `/tmp` checks.
  - Minimized package fixtures live under `fixtures/resolver/project/node_modules/react` and `fixtures/resolver/project/node_modules/hono`; `just verify-scaffolds` now compiles/tests generated MoonBit packages against those package names.
- [x] Keep JSX parser work deferred until `.d.ts` type-surface parsing is no longer the blocker.
  - Re-evaluate only if React/Hono support hits syntax that cannot be represented from declaration files alone.

## Codegen Type Mismatch Bugs

- [x] Re-verify the historical wasmtime mismatch regressions against the current codegen.
  - `src/codegen/codegen_wbtest.mbt` now passes end-to-end under the current wasmtime-backed runner, including the previously tracked `if-else`, `int factorial`, `js simple arithmetic`, `typed module with nested scopes`, `switch`, `switch default only`, and `do-while` cases.
  - The old hand-maintained mismatch list was stale and has been retired in favor of the executable regression suite.

## Expansion Plan (easy + coverage mix)

### Implemented (recent)
- [x] Comma operator (Seq) codegen + compilability
- [x] Logical `&&` / `||` short-circuit (i32/f64)
- [x] Unary `void` (evaluate side effects, return undefined)
- [x] `typeof` (restricted: only when operand type is statically known; return string literal)
- [x] Logical assignments `&&=` / `||=` / `??=` (Var/Prop/Index variants)
- [x] Template literals (untagged only, string-typed expressions only; desugar to concat)
- [x] Full template literals (ToString coercion for non-strings)
- [x] Computed property access in literals (const key only)
- [x] Spread in array literals and known-signature function calls
- [x] Conditional named function call expressions, e.g. `(flag ? f : g)(x)`
- [x] IIFE call expressions for arrow/function expressions with expression or single-return block bodies
  - Covered shapes now include zero-arg wrappers, multi-arg wrappers, named function IIFEs, nested IIFEs, and reusable function values when they are called directly without escaping.
- [x] Local reusable function value aliases and conditional calls over local function values.
  - Covered shapes include `const fn = inc; fn(x)` and
    `(flag ? inc : dec)(x)` where `inc` / `dec` are local arrow or function
    expression values.
- [x] Static reassignment and conditional aliasing of local reusable function values.
  - Covered shapes include `let fn = inc; fn = dec; fn(x)` and
    `const fn = flag ? inc : dec; fn(x)` when both branches are local
    function values.
- [x] Inline conditional callees and assignment-expression function value calls.
  - Covered shapes include
    `(flag ? ((x) => x + 1) : ((x) => x - 1))(n)`,
    `(fn = dec)(n)`, and `(fn = flag ? inc : dec)(n)` followed by later
    `fn(...)` reuse.
- [x] Static higher-order IIFE calls where local function values are passed as
  inline parameters and called inside the IIFE body.
  - Covered shapes include `((fn, x) => fn(x))(inc, n)` and the same pattern
    through function expressions or conditional local function aliases.
- [x] Static returned function-value calls where an inline IIFE returns a local
  function value and the result is immediately called.
  - Covered shapes include `((() => inc)())(n)`,
    `((function () { return dec })())(n)`, `(((fn) => fn)(inc))(n)`, and
    conditional returned aliases such as `((() => flag ? inc : dec)())(n)`.
- [x] Static returned function values stored across statement boundaries.
  - Covered shapes include `const fn = (() => inc)(); fn(n)`,
    `const fn = ((value) => value)(inc); fn(n)`, conditional returned aliases,
    and reassignment via `fn = (() => dec)()` before a later call.
- [x] Static function values stored in data structures.
  - Covered shapes include `const fns = [inc]; fns[0](n)`, `box.fn(n)`,
    conditional static array indexes, returned function values inside object
    fields, and reassigned object tables.
- [x] Local function factories returning static function values across a local
  function-expression boundary.
  - Covered shapes include `choose(flag)(n)` where `choose` is an arrow or
    function expression, factories returned from an IIFE, `const fn =
    choose(flag); fn(n)`, and `const box = { fn: choose(flag) }; box.fn(n)`.
- [x] Top-level factories returning top-level function references.
  - Covered codegen shapes include `choose(flag)(n)`, `const fn =
    choose(flag); fn(n)`, and `const box = { fn: choose(flag) }; box.fn(n)`
    when `choose` returns top-level function references such as `inc` / `dec`.
- [x] Module-aware compilability for top-level factory object storage.
  - `can_compile_to_wasm_in_module(func, mod)` and the module-level analysis
    rail now resolve `const box = { fn: choose(flag) }; box.fn(n)` when
    `choose` returns top-level function references.
- [x] Immutable captured values in returned local function values.
  - Covered shapes include `const make = (base) => (x) => x + base; const fn =
    make(seed); fn(n)`, function-expression factories, and object factories
    that store captured returned functions in fields.

### Next in order
1. Continue from substitution-based immutable captures toward real closure
   values that can cross top-level function boundaries, or add conservative
   rejection tests for mutable captures.

### Candidates (need more groundwork)
- Arbitrary call expressions where function values escape, are reassigned, or
  require captured mutable environments.

## Real-World MoonBit Package Probe

- [x] Support `tsmbt --input mizchi/foo --out dist/` style ghq package resolution for MoonBit packages.
- [x] Verify build-backed `MoonBit -> TypeScript` scaffold generation through `moon build --target js` for local `mizchi/ripple`, `mizchi/semver`, and `mizchi/tempfile` checkouts.
  - `just verify-realworld-moonbit` is optional and skipped package-by-package when those local ghq checkouts are absent.
- [x] Broaden the local real-world probe set to `mizchi/ast_printer`, `mizchi/js`, `mizchi/jsonschema`, `mizchi/markdown`, `mizchi/nom`, `mizchi/pixelmatch`, `mizchi/syntree`, `mizchi/tui`, `mizchi/vfs`, and `mizchi/jwt.mbt`.
- [x] Resolve ghq packages whose repository name differs from their MoonBit module name by reading `moon.mod.json` metadata.
- [x] Preserve MoonBit `raise` effects in temporary glue wrappers so effectful packages such as `mizchi/semver` build.
- [x] Skip facade wrappers that would expose private root types from the source package; the generated `.d.ts` can still document those opaque types, but glue packages cannot refer to private MoonBit symbols.
- [x] Qualify local root trait bounds in temporary glue wrappers so generic packages such as `mizchi/nom` build.
- [x] Emit child-package runtime re-export files and facade declarations so recursive MoonBit -> TypeScript packages expose matching `.d.ts` and JS subpaths.
- [x] Add stable real-world MBTI declaration snapshots for `mizchi/ast_printer` and `mizchi/jsonschema` to default fixture typechecking.
- [x] Re-run the local real-world MoonBit probe and confirm the current package set passes generated JS import and declaration typecheck.
- [x] Investigate packages that fail before or during source JS build for reasons outside the generated glue surface.
  - `mizchi/ast_printer` was fixed by updating its `moonbitlang/parser` dependency from `0.1.15` to `0.2.5` and adapting the printer to the current parser AST (`type P = Point` aliases, no removed top-level alias constructors, `TypeDesc::Record(fields~, ..)`).

## CI Notes

- Default `just ci` remains fixture-based and does not require local ghq checkouts.
- `just verify-realworld-moonbit` is intentionally outside default CI because it probes developer-local MoonBit repositories and writes temporary glue packages into those source modules during `moon build --target js`.
- `just verify-realworld-typescript` is intentionally outside default CI because it probes a developer-local npm package corpus via `TSMBT_REALWORLD_TYPESCRIPT_NODE_MODULES`.

## Beyond 90%: Bridge Quality Gaps for Tier 2 / Tier 3 Packages (2026-05-03)

After the 90% gate, the remaining `naturalize-target` and `budgeted-fallback`
JSValue surfaces are dominated by a small set of structural limitations rather
than ad-hoc fixes. The previous demand-driven plateau was reached at hono = 50,
date-fns = 22, jose = 84, react-router = 194, etc., where each remaining
fallback traces to one of the items below. Each item is a multi-commit
structural change, not a one-off lowering tweak.

Priority is by impact on real-world bridge JSValue surface, not by ease.

### 1. Heterogeneous union -> auto-enum (highest ROI, bridge-local)

Patterns: `number | string | Date` (jose setters), `(string | number)[]` (immer
Patch.path), `string | string[]`, `boolean | "boundary"` (magic-string hires),
`boolean | OverwriteOptions` (magic-string), schema-leaf branches in zod /
valibot.

- [ ] Detect heterogeneous unions whose members can each be discriminated at
  runtime (`typeof` for primitives, `instanceof` for known classes, optional
  fallback for plain objects).
- [ ] Lower the alias / synthetic-named union into a `pub(all) enum` with one
  case per member, where each case wraps the lowered MoonBit type (e.g.
  `Number(Double) | StringValue(String) | DateValue(Date)`).
- [ ] Generate paired conversion helpers: MoonBit-side `to_js(self) -> JSValue`
  using primitive coercions, and JS-side discrimination wrappers in
  `bridge.js`.
- [ ] Reuse the existing literal-union synthetic naming pass for anonymous
  heterogeneous unions on params / fields / return types.
- [ ] Emit diagnostics and stay on JSValue when discrimination is ambiguous
  (e.g. two struct members with overlapping shapes).
- [ ] Add real-world budgets: jose, magic-string, immer, and zod / valibot
  schema leaves where applicable.

### 2. Method-level generics preserved through bridge

Patterns: `Hono<E,S,P>.get<Path extends string>(path: Path, handler):
Hono<E, S, P | Path>`, `Session.get<Key extends keyof Data>(key: Key)`,
`zod.object<T extends ZodRawShape>(shape: T)`.

- [ ] Capture method-level type parameter lists (and bounds) on
  `TsClassMethodDecl` and `TsInterfaceMethodSignature`.
- [ ] Plumb method-level generics through bridge generation so MoonBit method
  signatures expose them where the bound is representable.
- [ ] Apply bound substitution at the method boundary, parallel to the existing
  alias-level bound substitution introduced for `Record<P, ...>`.
- [ ] Add post-lowering type-param filtering so unused method generics drop
  cleanly without `unused_type_variable` warnings.
- [ ] Update the parser-side allowlist (`moonbit_should_preserve_interface_type_params`)
  to reach method-level generics for hono / react-router.

### 3. Mapped type partial evaluation + conditional reduction depth

Patterns: zod `output<T>` / `infer<T>` mapped types, valibot equivalent,
date-fns `EachDayOfIntervalResult<I, O>` (Array<conditional + infer + indexed
access>), jose key-typed builders.

- [ ] Extend `simplify_type` so distributive conditional types reduce when each
  branch resolves to the same concrete shape after bound substitution and
  infer extraction.
- [ ] Add a "branch-join" pass: when an `Array<Conditional<...>>` survives all
  reduction passes, collect leaf branches and accept the join only if every
  leaf is structurally compatible with the conditional's terminal default.
- [ ] Lower mapped types with key remapping (`{ [K in keyof T as ...]: ... }`)
  for the common output-shape pattern used by zod / valibot.
- [ ] Treat unresolvable infer patterns as their bound rather than `JSValue` so
  generic `infer DateType extends Date` collapses to `Date` at the bridge
  boundary.

### 4. Template literal types

Patterns: node:util `InspectColorBackground = bg${Capitalize<InspectColorForeground>}`,
react-router path patterns, zod template-literal validators.

- [ ] Add AST nodes for template literal types (`TsType::TemplateLiteral`)
  including `Capitalize` / `Lowercase` / `Uppercase` / `Uncapitalize` intrinsic
  string-mapping types.
- [ ] Resolve template literal types to a string-literal union when the
  parameter is a finite string-literal union.
- [ ] Reuse the existing string-literal-union enum-lowering path for template
  literal types whose parameter union is small and safely PascalCase-able.
- [ ] Otherwise fall back to `String` rather than `JSValue` when the template
  shape is statically known to produce strings.

### 5. JSX / component layer

Patterns: preact / react-router component definitions, `FunctionComponent<P>`,
`ForwardRefExoticComponent`, JSX intrinsic elements.

- [ ] Decide whether a JSX-aware bridge layer ships as a separate generator
  output or as MoonBit-native types in the existing bridge.
- [ ] Preserve `FunctionComponent<P>` as a callable opaque whose props are
  represented as the resolved `P` struct.
- [ ] Lower `JSX.Element` to a JS-opaque type that round-trips through bridge
  glue without widening to `JSValue` for every render call.
- [ ] Re-evaluate preact and react-router naturalize budgets after JSX layer.

### 6. Class static-side / index signature / module augmentation

Patterns: jose builder pattern (`new SignJWT(payload).setIssuedAt()...`),
magic-string `MagicString` static helpers, hono `c.set()` per-context
augmentation, React `HTMLAttributes` index signatures.

- [ ] Separate class static-side (`typeof Class`) from instance-side at the
  bridge boundary so static factories / properties live in their own MoonBit
  module surface.
- [ ] Lower `[key: string]: V` index signatures to a paired
  getter / setter pair on the generated MoonBit struct.
- [ ] Decide whether module augmentation gets a first-class lowering or stays
  as a documented diagnostic.

### 7. Modern syntax follow-ups (smaller)

- [ ] `satisfies` operator at the expression level.
- [ ] Stage-3 decorators (parser support).
- [ ] `using` / `await using` declarations.
- [ ] Const generics (`<const T>`).

### Non-Goals (still)

- [ ] Do not turn this list into a checklist for "all of TypeScript". Each item
  must justify itself by removing real-world JSValue surface from the locked
  corpus.
- [ ] Do not pursue `any` / `unknown` AST distinction unless a downstream
  consumer needs it; the JSValue count is unaffected.
