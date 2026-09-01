# TODO

The wasm interpreter / codegen / AOT compiler that originally lived in this
repo has been removed. Items below are scoped to the bridge generator only.

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
  - [x] simple alias-position passthrough for resolved concrete utility aliases.
  - [x] local `typeof Class` capture for `InstanceType` /
    `ConstructorParameters` bridge lowering.
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
  - [x] `mbt2ts --input mizchi/foo --out dist`
  - [x] `ts2mbt --input npm-package --out dist`
  - [x] `--module-spec` (`ts2mbt` only)
  - [x] `--diagnostics`
  - [x] `--strict`
  - The `tsmbt` binary was split into per-direction `ts2mbt` / `mbt2ts`
    binaries; the `--direction` flag was retired since each binary picks
    its own direction. Unified CLI help, parser tests, and README now
    document the per-binary public contract.
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

- [x] Detect heterogeneous unions whose members can each be discriminated at
  runtime (`typeof` for primitives, `instanceof` for known classes, optional
  fallback for plain objects).
- [x] Lower the alias / synthetic-named union into a `pub(all) enum` with one
  case per member, where each case wraps the lowered MoonBit type (e.g.
  `Number(Double) | StringValue(String) | DateValue(Date)`).
- [x] Generate paired conversion helpers: MoonBit-side `to_js(self) -> JSValue`
  using primitive coercions, and JS-side discrimination wrappers in
  `bridge.js`.
- [x] Reuse the existing literal-union synthetic naming pass for anonymous
  heterogeneous unions on params / fields / return types.
  - Mixed primitive + string/number/bigint/boolean literal unions now lower
    too: literal cases become no-payload enum constructors (e.g. `Boundary`)
    discriminated via `=== "boundary"`. Pure literal unions still defer to
    `enum_lowering`, and a literal whose primitive type collides with a
    non-literal sibling stays on JSValue.
- [x] Auto-wrap return values to the MoonBit-side `<alias>_from_js`
  representation when the discriminator is purely typeof / isArray / strict
  equality. Tagged-union aliases that depend on `instanceof <NamedClass>`
  (e.g. `ServerType = Server | Http2Server | Http2SecureServer` from
  `node:net` / `node:http2`) are skipped because the named classes aren't
  reachable from `bridge.js`.
- [x] Emit diagnostics and stay on JSValue when discrimination is ambiguous
  (e.g. two struct members with overlapping shapes).
  - `tagged_union_widen_reason_for_alias` reports the rejection cause
    (overlapping primitive discriminator, non-PascalCase / non-discriminable
    member, or duplicate constructor name) and the resolution chain in
    `moonbit_decl.mbt` surfaces it as a `Unsupported export <Name>: ...`
    comment in the generated `bridge.mbti`. Pure-literal unions still
    defer silently to `enum_lowering`, and `null` / `undefined` markers
    are filtered out before evaluating discrimination so plain optional
    widening doesn't get diagnosed.
- [x] Add real-world budgets: jose, magic-string, immer, and zod / valibot
  schema leaves where applicable.
  - `just verify-realworld-typescript` is back to a green baseline across
    all 24 corpus entries; per-package `JSValue` cause budgets, function
    counts, and unsupported-export budgets now reflect the actual
    generated output, including the new heterogeneous-union diagnostics.
- [x] Drive the `heterogeneous-union-widened` budget back to 0 (done
  2026-07-15, same day it was added). Four lowerings landed:
  - qualified namespace refs resolve to their flattened export name
    before classification (`JSX.Element` -> `JsxElement`, hono `Child`);
  - function members discriminate via `typeof === "function"` and render
    as arrow payloads (`FnValue(() -> String)` — drizzle `NeonAuthToken`,
    react `ElementType`); inline `Auto_*` synthesis still excludes
    function members (the useState wrapper glue can't produce the enum);
  - branded-string intersections collapse to `string` and the
    LiteralUnion pattern collapses to a plain String alias
    (vitest `CancelReason = "a" | "b" | (string & Record<string, never>)`);
  - indexed access over an EMPTY registry interface reduces to `never`
    and drops from the union (vitest
    `TestArtifact = A | B | C | Registry[keyof Registry]`).

### 2. Method-level generics preserved through bridge

Patterns: `Hono<E,S,P>.get<Path extends string>(path: Path, handler):
Hono<E, S, P | Path>`, `Session.get<Key extends keyof Data>(key: Key)`,
`zod.object<T extends ZodRawShape>(shape: T)`.

- [x] Capture method-level type parameter lists (and bounds) on
  `TsClassMethodDecl`. (commit `eeb94a6`)
- Investigation result (2026-05-03): bound substitution at method
  boundaries is **already happening** in `parser_type.mbt:639`
  (`local_type_param_bound`), which short-circuits any `Ident(name)`
  to its registered bound during type parsing. Methods like
  `HonoRequest.valid<T extends keyof ValidationTargets>(target: T)`
  already render as `valid(target : String) -> ...` because `T` is
  substituted away before the AST escapes the parser.
- MoonBit JS backend rejects `pub extern "js" fn[T] ...`
  (`Error 4008: FFI function cannot have type parameters`), so a
  generic-preserving public signature would require a separate
  wrapper layer (`pub fn[T] Class::method(...) { Class::method_raw(...) }`).
  This only buys typing precision when the bound is itself
  representable as a MoonBit trait, which is rare for the
  string-literal / interface bounds used in real corpora.
- [x] Conclusion: keep the AST fields populated so a later
  wrapper-layer pass can use them, but do not generate a separate
  generic surface yet. The bound-substitute path covers the common
  cases. Revisit only when a real-world consumer needs a generic
  return type that is not represented by the substituted bound.

### 3. Mapped type partial evaluation + conditional reduction depth

Patterns: zod `output<T>` / `infer<T>` mapped types, valibot equivalent,
date-fns `EachDayOfIntervalResult<I, O>` (Array<conditional + infer + indexed
access>), jose key-typed builders.

- [x] Extend `simplify_type` so distributive conditional types reduce when each
  branch resolves to the same concrete shape after bound substitution and
  infer extraction. (Done via the `Union` source path in `simplify_type` —
  every leaf must resolve definitively; otherwise the conditional is
  preserved for a later retry.)
- [~] Branch-join over `Array<Conditional<...>>`: the simplifier reduces a
  union of conditionals when every branch decides, but doesn't yet
  collect leaf branches and accept the join when only the terminal-default
  shape matches. Low real-world ROI; left for later.
- [x] Lower mapped types with key remapping (`{ [K in keyof T as ...]: ... }`)
  for the common output-shape pattern used by zod / valibot. (Implemented
  via `MappedTypeRemap` + `simplify_mapped_type_remap`.)
- [x] Treat unresolvable infer patterns as their bound rather than `JSValue` so
  generic `infer DateType extends Date` collapses to `Date` at the bridge
  boundary. (`moonbit_decl.mbt` / `moonbit_js_ffi.mbt` consult
  `infer_marker_bound` at the surface boundary;
  `match_infer_pattern` now also rejects sources definitively disjoint
  from the bound at match time.)

### 4. Template literal types

Patterns: node:util `InspectColorBackground = bg${Capitalize<InspectColorForeground>}`,
react-router path patterns, zod template-literal validators.

- [x] Add AST nodes for template literal types (`TsType::TemplateLiteralType`)
  including `Capitalize` / `Lowercase` / `Uppercase` / `Uncapitalize` intrinsic
  string-mapping types.
- [x] Resolve template literal types to a string-literal union when the
  parameter is a finite string-literal union. (`simplify_template_literal`
  cartesian-products the part / arg pairs.)
- [x] Reuse the existing string-literal-union enum-lowering path for template
  literal types whose parameter union is small and safely PascalCase-able.
  (Bridge enum lowering walks the template result.)
- [x] Otherwise fall back to `String` rather than `JSValue` when the template
  shape is statically known to produce strings.
  (`TemplateLiteralType(_, _) => "String"` in both decl / FFI renderers.)

### 5. JSX / component layer

Patterns: preact / react-router component definitions, `FunctionComponent<P>`,
`ForwardRefExoticComponent`, JSX intrinsic elements.

- [~] Open design decision: a JSX-aware bridge layer ships as MoonBit-native
  types in the existing bridge. No separate generator output is planned.
- [x] Preserve `FunctionComponent<P>` as a callable opaque whose props are
  represented as the resolved `P` struct. (Done via the React-specific
  utility lowering pass; callable component surfaces are emitted as opaque
  external JS callable types.)
- [~] Lower `JSX.Element` to a JS-opaque type that round-trips through bridge
  glue without widening to `JSValue` for every render call. Current state
  collapses `JSX.Element` to `@js.Any` at the bridge boundary; a dedicated
  opaque type per JSX namespace is still open.
- [~] Re-evaluate preact / react-router naturalize budgets after JSX layer.
  Budgets updated as needed when the bridge realigns; no fresh pass is
  scheduled.

### 6. Class static-side / index signature / module augmentation

Patterns: jose builder pattern (`new SignJWT(payload).setIssuedAt()...`),
magic-string `MagicString` static helpers, hono `c.set()` per-context
augmentation, React `HTMLAttributes` index signatures.

- [x] Class static-side (`typeof Class`) merging: `PropAccess` on a class
  identifier consults `globals[Name.member]` (which catches namespace + class
  declaration merging) and the class's static methods / properties before
  falling back to instance-side lookup.
- [x] Lower `[key: string]: V` index signatures: `TsClassDecl.index_signatures`
  carries the parsed entries and `lookup_class_field` falls through to
  `index_signature_value` after exhausting named members. The
  `TsInterface` side already worked.
- [x] Module augmentation graph: `TsModule.module_augmentations :
  Array[(String, TsModule)]` records every `declare module "X" { ... }`
  block by specifier; declarations still flow into the surrounding scope
  for legacy consumers.

### 7. Modern syntax follow-ups (smaller)

- [x] `satisfies` operator at the expression level. (Parser retains
  `Satisfies(expr, ty)`; checker validates assignment in
  `check_call_args_in_expr`.)
- [x] Stage-3 decorators on classes. (`TsClassDecl.decorators` retains the
  parsed `@expr` chain.)
- [x] `using` / `await using` declarations including `export using` at the
  module export position.
- [x] Const generics (`<const T>`). Retained on `TsFunc.const_type_params`
  and consulted by the JSX generic-component inference path to skip
  literal widening when any of the component's type parameters carries
  the modifier.

### 8. Polymorphic `this` keeps fluent chains typed (done 2026-07-15)

Patterns: zod `ZodType.check(...): this` / `optional(): ZodOptional<this>`,
builder chains like jose `SignJWT.setIssuedAt(): this`, generic classes
with `merge(other: this): this`.

- [x] `this` in interface members and class methods now lowers to the
  owning declaration applied to its own type parameters
  (`Schema[Output, Input, Internals]`) instead of `Named(owner)` +
  the `JSValue` arity filler (`Schema[JSValue, JSValue, JSValue]`).
  The substitution is root-scoped: members merged in from `extends`
  expansion also resolve `this` to the derived struct, matching TS
  semantics and keeping every substituted param in scope.
  Implemented in `decl_this_owner_type` / `decl_replace_this_type`
  (now recursing through `Func` params and returns as well, so
  `apply((this) => R)`-style callback params stop leaking a raw
  `This` opaque type). zod: SCAFFOLD JSValue fallback entries
  748 -> 648; the whole fluent core (`check` / `clone` / `optional` /
  `nullable` / `describe` / ...) keeps `Schema[Output, Input, Internals]`.

### 9. Generic free functions export via monomorphized glue (done 2026-07-15)

Previously every `pub fn[T] ...` free function was omitted from
`link.js.exports` and listed in `AUTOLINK_DIAGNOSTICS.md`.

- [x] Unconstrained generic free functions now export through autolink
  glue: type parameters are instantiated at an opaque
  `#external pub type TsMbtGenericAny` (values cross the JS boundary
  unchanged, which is exactly parametric behavior), the glue wrapper is
  therefore non-generic and exportable, and the emitted `.d.ts` keeps the
  original generic signature (`export function identity<T>(value: T): T`).
- [x] Bare `T?` returns unwrap to `value | undefined` via a
  `tsmbt_generic_undefined()` extern, because `Option[TsMbtGenericAny]`
  crosses the boundary in the boxed `{_0}` representation.
- [x] Eligibility is decided by `mbti_generic_glue_return_plan` and shared
  by the glue emitter, the runtime-inaccessible screening, and the
  diagnostics list. Ineligible (stay omitted): trait bounds (`[T : Show]`),
  type params inside tuples (MoonBit tuples are not JS arrays), type params
  under `Option` anywhere except the bare top-level return, and optional
  params (`name? : T`).
- Runtime verified with a node smoke: `identity(obj) === obj`,
  `identity(undefined) === undefined`, `first([]) === undefined`,
  `first([10, 20]) === 10`; `tsc --strict` accepts a typed generic consumer
  of the emitted `.d.ts`.
- Next increments: generic methods on non-generic owners (same
  monomorphization through the facade path), then generic owners.

### 10. String-subset boundary for optional-message unions (done 2026-07-15)

Pattern: zod's check surface passes `params?: string | $ZodCheckMinLengthParams`
on nearly every validator (`min`, `max`, `length`, `regex`, ...). The
`$`-prefixed name cannot become a tagged-union constructor (names must start
`A-Z`), so the whole param degraded to `JSValue?`.

- [x] `ffi_string_subset_union_text`: a two-member union pairing `string`
  with a named `*Params` bag that is NOT a declared type on the bridge
  surface now types the boundary as `String`. The common string form is
  naturally typed; the structured object form stays reachable via
  `unsafeCast`. Guards: exactly two members, `Params` suffix required,
  abstains when the named type is declared / a generic param / a local type
  param — so option-bag unions with reachable declarations keep their
  tagged lowering and `string | URL` keeps the JSValue fallback.
- zod: SCAFFOLD JSValue fallback entries 648 -> 565
  (`min : (Double, String?) -> ZodMap[Key, Value]` etc.); the regenerated
  zod3 package passes `moon check --target js`.
- Note: per-package JSValue counts in the env-gated realworld METRICS
  corpus may drift downward next time it is regenerated — the budget file
  encodes upper bounds, so this is safe, but expect diffs there.

### 11. zod fallback batch 2: decl-path subset, hidden members, bounds, lib prelude, predicate folding (done 2026-07-15)

Five lowerings driven by the remaining zod JSValue-fallback clusters. zod
SCAFFOLD fallback entries: 565 -> 241 (and the entries that remain are
dominated by `data: unknown` params and `unknown | Promise<unknown>`
callback returns, where `JSValue` is the semantically correct type).

- [x] The string-subset policy now also covers the DECL emitter
  (`moonbit_type_name` in `parser_moonbit.mbt` mirrors the FFI rule) and
  accepts `Applied(*Params, ...)` shapes — qualified aliases like
  `core.$ZodEmailParams` resolve into applied generic aliases the decl
  layer cannot expand, and previously missed the `Named`-only match.
  Every classic factory (`email` / `uuid` / `cuid` / ... ~40 fns) and the
  `ZodString` format methods now take `String?`.
- [x] `@internal` members are omitted from bridge scaffolds entirely
  (tsc's stripInternal semantics); `@deprecated` members survive only
  while they type naturally — one that could only widen to `JSValue`
  (zod's `_def` / `_input` / `_output`) is dropped. Tags are parsed from
  member-level JSDoc (`TsInterface.internal_members` /
  `deprecated_members`), travel through `extends` flattening, and gate
  both the decl emitter and the FFI struct decl + its bridge.js converter.
- [x] Constrained generic METHOD type params substitute their bounds at
  the boundary (`TsInterface.method_type_param_bounds`, applied in
  `append_interface_origin_fields`): every argument for a
  `pipe<T extends $ZodType>(target: T)` slot satisfies the bound, so
  `pipe` / `or` / `and` / `apply` / `refine` keep natural signatures.
  `brand<T extends PropertyKey>` folds its conditional return to `this`
  through the same substitution.
- [x] lib.d.ts prelude: `scripts/gen_lib_globals.sh` missed
  `declare type` aliases — PropertyKey, PromiseConstructorLike, and the
  *Decorator aliases are now in the generated registry, and
  `is_well_known_type_name` delegates to it, so ambient lib types no
  longer surface as unresolved-reference notes.
- [x] `extends_decision`: a plain-return function never extends a
  predicate-return signature (tsc: source "must be a type predicate").
  Folds `Ch extends (arg: any) => arg is infer R ? ... : this` to its
  false branch — `refine` returns `Schema[Output, Input, Internals]`
  instead of `JSValue`.
- Note: per-package JSValue counts in the env-gated realworld METRICS
  corpus will drift down on regeneration (budgets are upper bounds).

### 12. Indexed access on constrained type params (done 2026-07-15)

zod: `def: Internals["def"]` / `type: Internals["def"]["type"]` with
`Internals extends core.$ZodTypeInternals<Output, Input>`.
Fallback entries 241 -> 225.

- [x] `decl_eval_bound_indexed_access`: a `P["key"]` access whose base is
  one of the owning interface's CONSTRAINED type parameters resolves by
  looking the key up in the bound's field surface — through the qualified
  namespace import (`core.`), the barrel `export * from "./schemas.js"`
  (new `decl_resolve_interface_origin_deep` walks
  `record.reexports`), and the bound's own `extends` chain. Chained
  accesses evaluate inside-out, tracking the module each intermediate
  name is relative to; resolved names map back to canonical export names
  where the surface has one. Generic targets substitute supplied type
  arguments; a field that still references the target's own params
  without matching arguments is rejected (capture risk) and keeps the
  old widening.
- zod: `def : UnderscoreZodTypeDef` (typed opaque handle instead of
  `JSValue`), `type_ : SchemaType` / `ZodTypeType` (enum of the schema
  kind literal union).

### 13. zod runs end-to-end from MoonBit (done 2026-07-16)

Runtime-verified (node, `moon test --target js` against the generated
package): construct -> chain -> `safeParse` -> read the result. The four
smoke cases: string schema accept/reject, `.email()` format
validation, `object()` schema over an extern-built shape, and `parse`
returning the output handle.

- [x] `decl_exclusive_union_alias_interface_spec`: an applied generic
  alias behind a namespace import / barrel whose body folds through the
  mutually-exclusive object-union idiom (`{success: true, data: T,
  error?: never} | {success: false, data?: never, error: E}`)
  synthesizes a named interface — `safeParse` now returns
  `pub(all) struct ZodSafeParseResult { success : Bool, data :
  Core_output, error : ZodError[Core_output] }`. Shared by the lowering
  and the utility-interface collection walk so the struct is both
  referenced and emitted. Blanket cross-module alias inlining was
  measured to REGRESS (225 -> 418 fallbacks) and is deliberately not
  done; the inline fires only when the fold succeeds.
- [x] Exclusive fields keep their RAW passthrough type (no Option
  wrapper): generic-owner method wrappers return the raw JS object
  without conversion glue, and MoonBit's tagged Option representation
  crashes on the raw `undefined` the absent branch carries.
- [x] realworld zod smoke upgraded from construct-only to
  safeParse success/failure + email format round-trips.
- Known ergonomic gaps (deliberate, documented): concrete schemas
  (ZodString...) need `unsafeCast` to `Schema[...]` to reach
  `parse` / `safeParse` (generic base expansion is future work);
  `object()`'s shape is built with a small extern (`Record<string, any>`
  aliases stay opaque — the StringRecordOf* synthetics are equally
  unconstructible today).

### 14. zod full-feature pillars 2-3: error issues + object shapes (done 2026-07-16)

Runtime-verified continuations of #13 (pillar 1, generic-base
flattening, landed separately):

- [x] Pillar 2 — union aliases whose members cannot be
  runtime-discriminated join to their nearest COMMON BASE interface
  (`decl_join_union_alias_to_common_base`): zod's
  `$ZodIssue = $ZodIssueInvalidType | ... (11 members)` — all
  `$`-prefixed, so tagged lowering rejects every constructor name — all
  extend `$ZodIssueBase`, and the reference now lands on
  `pub(all) struct UnderscoreZodIssueBase { code : String?, input :
  JSValue?, path : Array[PropertyKey], message : String }` instead of an
  opaque handle. Nested union-alias members
  (`$ZodIssueInvalidUnion = NoMatch | MultipleMatch`) recurse; tagged- /
  enum-lowerable unions never reach the join. Runtime:
  `issues[0].message` / `.code == "invalid_type"` read directly.
- [x] Pillar 3 — `loose_shape_from_pairs(keys, values) ->
  Core__ZodLooseShape` (zod module hook, same pattern as react-router's
  `params_from_pairs`): `object()` shapes are built from MoonBit without
  hand-written externs. Runtime: object schema accepts a matching user
  object and rejects a non-object.
- [x] GENERIC owners reach the parse surface via the `as_schema` identity
  upcast (zod module hook): `as_schema(object(Some(shape), None))
  .safeParse(...)` — runtime-verified. MoonBit's nominal structs cannot
  express the extends relation, so the upcast makes it callable; a
  full per-generic-owner facade (monomorphized method wrappers like the
  mbt2ts generic-method glue) remains the eventual principled shape.

### 15. hono runs end-to-end: async handlers + middleware (done 2026-07-16)

Runtime-verified (node, `app.fetch(new Request(...))` round-trips through
MoonBit handlers): sync route via the existing `Context::text` wrapper
(`c.text("...", None, None)` — the generic-owner method glue was ALREADY
emitted for Context's callable-interface properties; the earlier "mbti
declares it but it doesn't exist" reading was wrong, the decl is the
method form), an async route returning `Promise[Response]`, a middleware
that `c.set`s a variable before `next()` with the handler reading it via
`c.get`, and 404 fallback.

- [x] hono module hooks (same pattern as zod's `as_schema`):
  `Hono::get_async / post_async / put_async / delete_async(path,
  (Context) -> Promise[Response])` — the HandlerInterface overload the
  generator picks is sync-only, but hono awaits whatever the handler
  returns and MoonBit closures ARE JS functions on the js backend, so the
  hooks register the closure raw with a typed surface.
- [x] `Hono::use_middleware(path?, (Context, () -> Promise[Unit]) ->
  Promise[Unit])`: pre-processing middleware calls `next()` and returns
  its promise. Post-processing (sequencing AFTER next resolves) needs
  Promise combinators on the MoonBit side and stays raw-JS territory.
- [x] realworld hono smoke upgraded from register-only to the full
  fetch round-trip (sync + async + middleware + 404).
- Remaining hono gaps (documented, not blocking): `app.fetch` returns
  `JSValue` (Response | Promise union), route methods return `HonoBase`
  (chain loses generics), path-param TYPE inference (`/users/:id` ->
  `{id: string}`) is TS type-level computation — same fundamental limit
  as zod's `z.infer`.

### 16. valibot + drizzle run end-to-end; boundary conversion fixes (done 2026-07-16)

Runtime-verified with node against regenerated packages. valibot:
`parse` / `safeParse` accept/reject and `pipe(string(), [minLength(3)])`
length validation. drizzle-orm: the `sql` tagged template builds an SQL
object from MoonBit (template-strings array via a tiny extern) and
`and_()` combines wrappers.

Four GENERAL boundary fixes fell out (all bugs any handle-round-tripping
package would hit):

- [x] Enum `to_js` converters are idempotent: a raw library value cast
  into a struct type carries the JS literal already (valibot's
  `string()` result flowing back into `parse(schema, ...)` crashed on
  "unexpected BaseSchemaKind tag: schema").
- [x] Struct `to_js` converters pass CLASS instances through untouched
  (MoonBit structs compile to plain objects, so an instance is always a
  raw library handle — spreading severed drizzle `SQL`'s prototype) and
  spread plain objects instead of rebuilding from declared fields
  (rebuilding stripped valibot's `~run` internals). Optional fields
  delete their key when absent instead of leaving a tagged None.
- [x] REST parameters spread at the call site in all three glue paths
  (import / func / callable) — `pipe(schema, ...items)` received the
  MoonBit array as its first variadic item ("item.~run is not a
  function"). Imports use `TsImport.param_is_rest`; funcs use
  `TsParam.is_rest`. Rest-param imports also FORCE the bridge glue —
  a direct `= "sql"` binding can never spread.
- [x] The decl emitter's reserved-word list synced to the FFI's 74-name
  list (`and` / `or` / `not` / ...): drizzle's `and` was emitted as
  callable `and_` but the mbti/decl surface advertised the uncallable
  bare name.
- realworld valibot smoke upgraded from construct-only to
  safeParse + pipe round-trips.
- Known cross-cutting gap (same family as zod's raw-typed result
  fields): matching a `T?` EXTERN RETURN with MoonBit `match` can crash
  on the raw `value | undefined` repr when MoonBit expects the tagged
  box — optional extern returns need repr-aware boxing glue. Reads via
  a small extern accessor work today. **Fixed in §17.**

### 17. Optional extern returns construct `Option` on the MoonBit side (done 2026-07-17)

Follow-up to the §16 known gap. Empirical repr table for `Option[T]` on
the JS backend: `String` / `Int` / struct instances / enum instances are
unboxed (`Some` = raw value, `None` = `undefined`); `Bool` uses the `-1`
sentinel; everything else — `JSValue`, `Double`, arrays, opaque
`#external` handles, generics, function/tuple types — uses a `{$tag, _0}`
box. A raw `value | undefined` extern return against a boxed `Option` is
not just crash-prone: a real value silently matches as `None`.

- [x] `__ts_mbt_wrap_option_return[T](raw : JSValue) -> T?` helper pair
  (absence check treats `undefined` and `null` as `None`; `%identity`
  cast for `Some`) injected once per generated package, from either the
  FFI emission (`ffi_option_return_wrap_helper_decls`) or the top-level
  wrapper pass (`bridge_option_return_wrap_helper_decls`), `contains`
  checks dedup the two.
- [x] Top-level `pub extern` fns with boxed-optional returns are demoted
  to `<name>_raw` externs plus a public wrapper by
  `add_bridge_public_wrappers` (same mechanism as enum-converter
  wrappers). Covers drizzle `and_` / `or_`, zod `getErrorMap`.
- [x] Class-method / getter `preserve` wrapper bodies use the wrap helper
  instead of a bare `unsafeCast` when the return is boxed-optional
  (drizzle `SQL::if_`, `One::get_one_config`, hono `Context` getters).
- [x] Non-preserve method / getter / index-accessor / function-field
  externs with boxed-optional returns emit a private raw extern
  (`_*_opt_ret_js`, `self` renamed `this_`) plus a public wrapper via
  `ffi_option_return_extern_pair` (valibot `ObjectEntries::op_get`).
- [x] The trailing `?` of a function-typed return
  (`() -> ((Props) -> JSValue)?`) binds to the function's result — a
  depth-0 `->` scan (`ffi_rendered_return_type_optional_inner`) keeps
  those on the raw passthrough.
- Verified: drizzle `match and_([...])` sees `Some` for real values and
  `None` for `undefined` (previously silent-`None` / crash); zod,
  valibot, hono scaffold smokes stay green.
- Still open (pre-existing, unrelated to Option): non-optional generated
  ENUM returns cross as raw strings (`nextFlag -> NodeFlag`), relying on
  idempotent to_js converters for round-trips; matching them in MoonBit
  needs a return-side `_from_js` conversion. **Resolved in §18** — the
  note was partly stale: top-level enum returns were already converted
  by the wrapper pass; the real broken vectors were index-signature
  accessors and empty structs.

### 18. Enum-typed accessors + index-signature-only interfaces (done 2026-07-17)

Investigating the §17 "raw enum returns" note empirically:

- Top-level fn enum returns were ALREADY converted
  (`nextFlag -> NodeFlag` demotes to a `String` raw extern + a wrapper
  calling `__ts_mbt_node_flag_from_js`) — the note was wrong about them.
- Class/interface METHOD returns never render enum types (they degrade
  to `String` at the ffi surface), so they exchange raw strings
  correctly at runtime; zero real-package occurrences. The decl-layer
  `.mbti` still advertises the enum names there — a surface divergence,
  not a runtime bug.
- The genuinely broken vectors, both fixed:
  - [x] `op_get` on `[k: string]: "a" | "b"` returned the raw string
    typed as the enum (match misbehaved) and `op_set` wrote MoonBit tag
    ints into the JS object. Both now route through
    `ffi_converted_return_extern_pair` / a `_to_js` wrapper pair
    (`ffi_rendered_generated_enum_info` decides; composes with the §17
    Option wrap for the `Enum?` getter return).
  - [x] Index-signature-only interfaces lowered to ZERO-FIELD structs,
    which MoonBit's JS backend value-erases — the instance compiled to
    `undefined` and every accessor crashed. Zero-field interface
    lowering now emits `#external pub type X` (matching what the decl
    layer already advertised in `.mbti`).
- Verified at runtime via the extended `realworld-literal-options`
  fixture: a `FlagMachine` class (method / getter / optional-method
  returns) plus a `FlagTable` index-signature interface with
  `op_get` -> `Some(R)` / missing -> `None` / `op_set(A)` round-trip.
- Return-side enum conversion machinery
  (`ffi_wrapper_return_body_expr`) also covers the preserve-wrapper
  bodies and any future path that renders enum returns.

### 19. Realworld budget recalibration + version-skew-tolerant node builtins (done 2026-07-17)

The env-gated `verify_realworld_typescript.sh` had drifted red after the
generic-base-flattening batches (zod fallbacks 225 -> ~1869 by the old
counting). Rebuilt a complete corpus root (repo-pinned zod 4.4.3 /
valibot 1.4.2 / hono 4.12.16 etc. plus fresh installs for the rest;
exact versions now recorded in `corpus/realworld-typescript.tsv`) and
recalibrated all three budget tables from measured values — the gate now
runs end to end (30 packages generated, checked, runtime-smoked) with
budgets enforced.

Generator fix found by the run:

- [x] `@types/node` routinely declares APIs newer than the running Node
  (`mkdtempDisposableSync` on node 22), and both
  `export { x } from "node:fs"` re-exports and
  `import { x } from "node:fs"` glue imports hard-fail at load time for
  a missing name. `node:*` bridges now route named access through the
  shared `import * as __ts_mbt_module` namespace
  (`ffi_bridge_tolerant_reexport_line`,
  `ffi_module_spec_prefers_namespace_named_imports`), so a missing name
  stays `undefined` until actually called.

Script smoke updates for current surfaces: glob escape/unescape/hasMagic
take `Options?` (wrap in `Some`), node:sqlite options gained
`limits`, and `StatementSync::get` now returns a real `Option` (the
section-17 wrap) — the smoke matches on it instead of reading the raw
value through an extern.

### 20. decl/ffi method surfaces aligned; methods carry real enum types (done 2026-07-17)

`bridge.mbti` advertised `declare pub fn flag_machine_advance(self) -> NodeFlag`
while `bridge.mbt` implemented `FlagMachine::advance(self) -> String` —
both the name and the type diverged. Fixed from both sides:

- [x] FFI class methods / getters / setters render param and return
  types with the field-style resolver (`ffi_struct_field_type_name`),
  so literal-union aliases surface as their generated enums instead of
  degrading to `String`. Conversions ride the section-18 machinery:
  enum returns via `ffi_converted_return_extern_pair` /
  `ffi_wrapper_return_body_expr`, enum params via new
  `ffi_enum_arg_expr` / `ffi_enum_param_raw_type` (`force~` pairs when
  only params need conversion; preserve-path wrappers convert before
  the `unsafeCast`). Setters got the same treatment.
- [x] Decl layer emits instance members as `Type::method` /
  `Type::get_x` / `Type::set_x` (snake-cased, reserved-suffixed) to
  match the FFI's naming; statics stay top-level `<class>_<method>`.
- Verified: `.mbti` and `.mbt` now agree line-for-line on the
  `FlagMachine` fixture (`FlagMachine::advance(self) -> NodeFlag` in
  both), and the runtime fixture matches enum constructors directly on
  method returns (`match advance(m) { R => ... }`,
  `peek() -> NodeFlag?` composes enum from_js with the Option wrap).
- Full gates green including the env-gated realworld corpus (30
  packages) and the drizzle / valibot / hono / zod scaffold smokes.

### Non-Goals (still)

- [ ] Do not turn this list into a checklist for "all of TypeScript". Each item
  must justify itself by removing real-world JSValue surface from the locked
  corpus.
- [ ] Do not pursue `any` / `unknown` AST distinction unless a downstream
  consumer needs it; the JSValue count is unaffected.

## Seamlessness Round 1 (2026-07-19)

A fresh-user walkthrough (npm install -> ts2mbt -> moon build -> node,
done twice: zod standalone and a 4-dep nanoid/ms/date-fns/axios app)
graded end-to-end usability at ~70% and surfaced four gaps, fixed in
priority order and each re-verified end-to-end in the walkthrough apps:

1. Promise consumption API: `Promise[T]` was opaque — async results
   could only be consumed from hand-written JS externs. Every generated
   package whose surface mentions `Promise[` now ships
   `Promise::then(on_ok)` (rejections stay loud), `Promise::then_catch`
   and `Promise::map`, backed by three `__ts_mbt_promise_*` bridge.js
   bindings. `axios.all(...).map(...).then_catch(...)` chains in pure
   MoonBit. Emission forces the self-contained JSValue/Promise decls
   (`state.needs_js_any/needs_promise`) since a surface can mention
   Promise only in doc comments.
2. Returned-function option unwrap (bug found by the walkthrough):
   `customAlphabet(...)` returns `(size?) => id`; MoonBit `None` reached
   the raw JS closure as `null`, JS default parameters never fired, and
   the id came back empty. `ffi_type_js_return_expr` now wraps
   Func-typed returns so each call routes args through the same converters
   direct parameters get (`ffi_returned_func_needs_arg_wrap`).
3. `ts2mbt generate` / `vendor` wiring: the `@tsmbt-bridge/*` `file:`
   dependencies are now written into the consumer's `package.json` in
   place (line-oriented insertion preserves formatting; copy-paste
   fallback when the shape defeats it) instead of a hint that silently
   vanished without `moon.mod.json`; packages that ship no declarations
   (`ms` without `@types/ms`) get a WARNING naming the `@types/`
   package instead of a silent function-less bridge; the moon.pkg
   import hint derives from `--out` instead of hardcoding
   `internal/generated`; AGENTS.md text matches the real behavior.
4. Typed JSValue constructors: `JSValue::from_string/from_double/
   from_int/from_bool/from_array` (identity externs) and
   `JSValue::object_from_pairs` (heterogeneous object literals) replace
   bare `unsafeCast` at the input boundary, emitted wherever the
   package declares JSValue.

Gate coverage: the axios build smoke now chains
`all().map().then_catch()` and builds a heterogeneous object via
`object_from_pairs`; the nanoid build smoke checks the returned
function's default-size and explicit-size paths. Budgets recalibrated
(the Promise layer + constructors add lines/JSValue refs per package).

MoonBit-native async integration (follow-up, same day): the JS backend
compiles `async fn` to CPS (an async fn value crosses to JS as a
2-continuation function — probed empirically; a GENERIC
`%async.suspend` intrinsic ICEs moonc v0.10.4, so the intrinsic stays
monomorphic on JSValue and only the public wrapper is generic). Every
package with a Promise surface now also ships:

- `Promise::wait(self : Promise[T]) -> T` — suspends the enclosing
  `async fn` until the promise settles; `await` in all but name.
- `pub suberror JsRejection { JsRejection(JSValue) }` — a rejected
  promise raises it, so `.wait() catch { JsRejection(e) => ... }`
  handles JS failures as ordinary MoonBit errors.
- `run_async(f : async () -> Unit)` — kicks an async fn from a sync
  context (main / tests); unhandled async errors exit non-zero.

Verified end-to-end on real axios: `all(vals).wait()` resolves inside
an async fn, and a connection-refused `get` surfaces as a caught
`JsRejection`. The axios build smoke covers both paths via
`run_async(smoke_async)`. The signature surface stays `-> Promise[T]`
(non-breaking; fire-and-forget and combinator use keep the raw
promise) — `.wait()` is the conversion point into async MoonBit.

moonbitlang/async integration mode (follow-up): when the consumer
module (nearest manifest walking up from the OUTPUT dir; `_build/`
outputs excluded, same rationale as the package.json wiring guard)
depends on `moonbitlang/async`, the emitter swaps the self-contained
`Promise::wait` for a delegation to `moonbitlang/async/js_async` —
which 0.18+ ships exactly for this: an `#external Promise[X]` with a
coroutine-scheduled `wait(abort_controller?)`. The generated package
gains `Promise::std()` (identity cast to `@js_async.Promise`) and the
`moon.pkg` import; `run_async` / `then` / `then_catch` / `map` stay.
Consequences, all probe-verified E2E on real axios: `async fn main`
works directly (the compiler requires importing moonbitlang/async for
async main — this IS the seamless entry, no `run_async` needed),
`@async.with_timeout` composes over bridge promises, and cancellation
plumbs through the official `AbortController`. Adding the dep to
moon.mod + re-running `ts2mbt generate` is the whole upgrade. Both
section texts live side by side in moonbit_js_ffi.mbt so the modes
cannot drift. Probes also confirmed the raw-CPS self-contained `wait`
keeps working under the @async event loop, and that a typealias-based
deep integration (`pub typealias @js_async.Promise as Promise`)
compiles and runs — deferred because methods cannot be defined on a
foreign aliased type, which would fracture the then/map surface.

Cross-API validation (same day): a four-package showcase app
(moonbitlang/async consumer) runs `async fn main` over node:fs
promises (write -> read roundtrip), jose (generateSecret -> SignJWT
builder chain -> sign -> 3-segment JWT), hono (in-process
`app.request` roundtrip, status 200 + body), and axios.all — exit 0,
no run_async, no hand-written awaits. The walkthrough surfaced and
fixed two real generator/runtime gaps:

- `<fn>.__promisify__` declarations (@types/node's alias for "the
  promisified form of fn") lowered to a literal runtime member access
  that does not exist — a guaranteed TypeError on all 45 node:fs
  `*Promisify` surfaces. `ffi_js_member_access_or_promisify` now
  lowers them to `util.promisify(fn)` (honoring promisify.custom),
  with the `node:util` import injected only when used. The node:fs
  build smoke covers write/readFilePromisify + `.wait()` end-to-end
  via `run_async`.
- `@js_async.Promise::wait` calls `.then` on the raw value, but
  TS-declared Promise returns are sometimes plain values at runtime
  (hono's sync-handler `request` returns a bare Response). The
  integration-mode `wait` now normalizes through `Promise.resolve`
  first, matching JS `await` leniency (the self-contained wait was
  already lenient via its then_catch glue).

Remaining friction observed in the showcase (recorded, not blocking):
hono's `fetch` / `request` returns are JSValue-typed (one unsafeCast
to `Promise[...]` before waiting), union params take nested
constructors (`PathOrFileDescriptor::PathLikeValue(PathLike::
StringValue(...))` — flat convenience constructors like the existing
`path_like_from_string` hooks cover node:fs but not every package),
and web-platform types (Response.status / .text) still need one-line
externs until a lib.dom prelude exists.

Run-verification tests (2026-07-20): the arc is now pinned by tests
that RUN the converted code, not just inspect it. A wbtest keeps the
two Promise-layer section texts coherent (self-contained =
`%async.suspend` + JsRejection-raising rejections; integration =
`Promise::std` + AbortController + `Promise.resolve` leniency, no
suspend intrinsic; both share wait / run_async / JsRejection). The
realworld gate grew `verify_async_integration_app`: a fresh consumer
app depending on moonbitlang/async vendors axios + hono, asserts the
generated bridges actually switched to integration mode, then builds
warning-clean (under warning_guard) and executes `async fn main`
covering awaited `axios.all`, `@async.with_timeout` composition,
AbortController plumbing, and the bare-Response leniency on hono's
sync `request`. Fallout: integration-mode `JsRejection` is `pub(all)`
(nothing constructs it in that mode — rejections raise `@js_async`'s
error), and the node_fs smoke unlinks its sync scratch file instead
of leaving it at the repo root.

Async-callback lowering (2026-07-20): the REVERSE direction now works —
TS APIs that RECEIVE `(...) => Promise<T>` callbacks (React 19
`useActionState`-style actions, promise-returning handlers) accept a
MoonBit `async fn` directly. Top-level fn params rendered as
`(A, B) -> Promise[T]` lower to `async (A, B) -> T raise` on the
natural-name public wrapper (and in `bridge.mbti`), glued back through
a new `Promise::from_async` emitted in both promise layers. Design
facts, all probe-verified before landing:

- MoonBit JS CPS ABI: an async fn that completes WITHOUT suspending
  calls neither continuation — it returns `Result[Option[T], Error]`
  directly. A naive `new Promise((res, rej) => f(args, res, rej))`
  wrapper silently drops synchronous raises. The self-contained
  `Promise::from_async` therefore performs resolve/reject INSIDE a
  noraise Unit wrapper async fn, so the trampoline can ignore the
  sync-completion return value safely.
- Integration mode must spawn: a callback CPS-started raw from JS has
  no coroutine context and `@js_async.Promise::wait` panics.
  `@js_async.Promise::from_async` (which `@coroutine.spawn`s — its doc
  marks it "for exporting MoonBit code to JavaScript") is the delegate;
  the integration `run_async` now also spawns through it (the previous
  raw-CPS trampoline would panic on the first integration-mode wait).
- `run_async` accepts `async () -> Unit raise` in both modes and
  reports errors through an explicit catch (console.error + exit 1) —
  synchronous raises included.
- Not lowered (recorded friction): optional callbacks
  (`((...) -> Promise[T])?`), interface/struct-field callbacks, class
  method callback params, and union-typed handler slots
  (`V | Promise<V>`, axios interceptors).

Tests: bridge wbtest pins the lowering (wrapper + glue + `_raw`
demotion + mbti rewrite + non-promise/optional callbacks staying raw)
and the section coherence (`Promise::from_async` identical signature in
both layers, integration run_async spawning via @js_async). The
realworld gate grew `verify_async_callback_app` twice (self-contained +
integration): a `useStateAction`-shaped fixture package is vendored,
surface markers asserted, then the app RUNS a MoonBit async fn as the
action — awaited TS promise inside the callback, two dispatches folding
state, and a synchronous raise surfacing as a caught rejection.

Round 2 (same day) — remaining callback positions: the lowering moved
into a shared `@parser.moonbit_async_callback_lowering` helper (one
detector for the decl `.mbti` and ffi `bridge.mbt` renderings, so the
divergence gate keeps them identical) and now also covers:

- optional callbacks `((...) -> Promise[T])?` -> `(async (...) -> T
  raise)?` with `Option::map` glue (Some/None structure preserved);
- interface methods / function-field method wrappers, both receiver
  shapes: generic receivers via the `(self.field)(glue)` wrapper,
  non-generic receivers via a forced extern/wrapper pair whose extern
  keeps the raw promise-returning callback types;
- class methods (instance + static, preserve and extern-pair paths),
  reusing the enum-param pair mechanics.

Struct FIELD types deliberately stay raw: fields are identity views
over JS objects (a stored JS function is not CPS-callable), so the
conversion point is the method wrapper / `Promise::from_async` at
construction time. Budget note: one playwright promise-callback
signature moved from the tuple/array bucket into callback/function
(885->886 / 170->169, total unchanged) — recalibrated. The gate
fixture package grew `onCommit` (generic interface method), `Notifier`
(non-generic interface method), `TaskQueue` (class methods), and
`runWithFallback` (optional callback, Some + None) — all RUN in both
promise layers.

Round 3 (same day) — the last two recorded frictions:

- Union handler returns `V | Promise<V>` (axios-interceptor shape,
  React 19 `useActionState`): a new
  `@checker.classify_promise_like_union` /
  `normalize_promise_like_union_return` pair rewrites callback RETURN
  unions of exactly {T, Promise<T>/PromiseLike<T>} to `Promise[T]` in
  every Func-type renderer of both layers (ffi inline + alias, decl
  inline + method parts). Sound both ways because `Promise::wait` is
  resolve-lenient in both modes, and it lets the async-callback
  lowering fire on sync-or-async slots. React's `useActionState`
  scaffold surface is now literally `action : async (State) -> State
  raise` (three hook-tuple test expectations updated from the opaque
  `UseActionStateActionCallback` form).
- Short-owner opaque callback synthesis: `decl_rewrite_inline_callback_
  param_type` now SKIPS the `<Owner><Param>Callback` substitution when
  the callback returns promise-like, so `runAction`-style exports keep
  the structural form and lower like everything else.

Fallout fixed along the way: the round-2 property-get extern for
sanitized members deduped by snake_case and collided on playwright's
`$eval` / `$$eval` — the getter name now embeds the field name
verbatim (unique per struct). Corpus effect of the normalization is a
net naturalization win — zod JSValue fallback 1901 -> 1631 lines and
JSValue-typed functions 607 -> 525, with smaller wins in valibot /
axios / marked / commander / react-router — 13 budget rows
recalibrated from a nobudget collection run. Gate fixture grew
`Interceptor` (union-return `use` handler — also regression-covers the
sanitized-member getter) and `runAction`; both RUN in both promise
layers.

Round 4 (same day) — checker-driven JSValue concretization: the
member-level conditional case is CLOSED. `Applied(GenericIface, args)`
references whose members hide behind conditionals over the interface's
own type params now specialize into synthesized monomorphic interfaces
(`decl_conditional_member_interface_spec`, mirroring the
exclusive-union alias synthesis: shared by the lowering and the
collection walk, fires only when EVERY conditional member decides).
The decision is a decl-layer structural `extends` (name equality ->
true; a required target field missing from the source's
extends-chain-merged fields -> false; anything else undecided) — the
shared checker `extends_decision` is deliberately untouched since it
feeds the TS7 oracle. A resolved branch then rides the whole earlier
pipeline: alias inlining -> `| null` optional collapse -> union-return
normalization -> async-callback lowering. Net effect on real axios:

  interceptors.use : JSValue   (before)
  AxiosInterceptorManagerInternalAxiosRequestConfig::use_(
    self, (async (InternalAxiosRequestConfig[JSValue]) ->
    InternalAxiosRequestConfig[JSValue] raise)?, ...)   (after)

and the realworld axios smoke now registers a MoonBit async fn as a
REQUEST INTERCEPTOR on a real axios instance (axios awaits the
from_async promise; a marker count proves exactly one run; the
connection-refused rejection still catches). A recursion guard
(in-progress set + first-registration-only field walks) keeps
self-referential instantiations from looping — date-fns crashed the
first version. Fixture: `conditional-member-entry.d.ts` pins both
branch outcomes (Payload lacks Ack's required field -> async handler
slot; Ack extends itself -> sync callback).

Surveyed but NOT concretizable via the checker (recorded): zod's
remaining JSValue params are TS `unknown` (honest widening); playwright
residuals are anonymous OBJECT-LITERAL option params (needs synthesized
option structs, an emitter feature); overloaded members still widen
(`interceptors` property itself is an anonymous-object type — one typed
extern bridges to the specialized manager until then).

Round 5 (same day) — extends upcast helpers, closing the dominant
naturalness friction from the 3-package evaluation (an idiomatic
zod+axios+node:fs app needed 7 escape hatches, of which inheritance
casts were the largest class). Interfaces whose `extends` bases do NOT
flatten (generic roots over generic bases — ZodObject over its zod
core base — and class bases — `interface AxiosInstance extends Axios`)
now emit sound `%identity` upcast helpers named after the type-guard
convention: `instance.asAxios().get(...)` replaces
`(unsafeCast(instance) : Axios).get(...)`. Pieces:

- `decl_unflattened_interface_bases` records skipped bases on the
  cloned interfaces (both cloners), mirroring the flatten decision in
  `append_interface_origin_fields`;
- both emitters (ffi struct decl + decl interface decl) render the
  helper with the base reference clamped to the EMITTED arity (source
  `_ZodType<A,B,C>` vs emitted `UnderscoreZodType[Internals]`);
- a text-level `prune_mismatched_upcast_helpers` pass drops helpers
  whose base reference still cannot match the surviving declaration —
  zod's `$ZodType`/`_ZodType` SANITIZATION COLLISION (both become
  `UnderscoreZodType` with different arities) makes some mismatches
  undetectable earlier; the prune keeps mbt and mbti in lockstep.

Budget note: helpers whose base type args widen to JSValue count into
the fallback metrics (react +14 "JSValue functions" are all usable
`asComponent`-style helpers; valibot +68 surface lines likewise) — 10
rows recalibrated. Naturalness evaluation delta: the 3-package app's
escape hatches drop 7 -> 6 (asAxios), with ZodObject->Schema still
needing a cast because zod's base chain hides behind the sanitization
collision. Remaining hatches ranked: anonymous object-literal
properties/params, overloaded members, JSValue value slots, and the
zod name collision (needs collision-aware type identifiers).

Round 6 (same day) — anonymous object-literal synthesis, the top-ranked
remaining hatch. `Object(fields)` types in member positions now
synthesize named structs (`<Owner><Member>` for properties,
`<Owner><Method><Param>` / `<Owner><Member>Options` for params,
`...Result` for returns), registered through a per-emission registry
(populated during cloning, drained after interface AND class cloning in
both layers — the decl emitter runs first in a package bundle so the
ffi drain sees a superset, and the expose pass evens the surfaces).
Rewrite sites: interface fields (`append_lowered_interface_field`),
class properties (`clone_class_property_in_scope`), class method
params (`clone_class_method_in_scope`), and Func-typed member
params/returns. Guards: literal keys only, 1..24 fields, same-name
different-shape collisions stay widened.

Everything composes: axios's `interceptors` property becomes
`AxiosInterceptors { request : AxiosInterceptorManagerInternal
AxiosRequestConfig; ... }` — the round-4 conditional-member
specialization landing inside a round-6 synthesized struct — so the
fully generated chain
`instance.asAxios().get_axios_interceptors().request.use_(Some(async
fn(config) { ... }))` runs with ZERO hand externs. playwright options
params become real structs with their literal-union fields enum-ized
(`ElementHandle::click(self, ElementHandleClickOptions?)`, 255
synthesized option structs).

Corpus effect (28 budget rows recalibrated): playwright JSValue-typed
functions 411 -> 200 and JSValue surface 1336 -> 827; zod 526 -> 485;
node:crypto 24 -> 16; net -639 JSValue surface lines across changed
rows (small increases in valibot / pino / react-router / lodash are
the synthesized structs' own JSValue-typed fields — new usable
surface, not lost signal). Naturalness evaluation: the 3-package app
drops to 5 escape hatches (interceptors extern eliminated).

Round 7 (same day) — overloaded-member merging + collision-free type
identifiers, the two hatches picked from the round-6 ranking.

Overload merging (`src/bridge/moonbit_decl.mbt`): the canonical TS
overload pattern — same member re-declared with extra TRAILING params
and the same return type — previously kept only the first declaration
(rest silently dropped, callers lost the richer arity). Now
`decl_merge_overload_param_lists` merges into the LONGEST signature
with the extra params optionalized (`decl_optionalize_type` wraps in
`| undefined` unless already optional-like), applied in
`append_class_method_once` (guards: same key / static / return, no
method-level type params) and in `append_lowered_interface_field`
(which was restructured so lowering + inline-object rewrites compute
the final type BEFORE the merge attempt). `Store::get(key)` +
`get(key, fallback)` becomes `get(self, key : String, fallback :
String?)`. Fixture `member-overload-entry.d.ts` + wbtest cover the
interface and class forms; the mitt gate smoke needed `emit(ev,
Some(ev))` since `emit`'s second param is now merged-optional.

Collision-free identifiers: `$` in TS type names now sanitizes to a
distinct `Dollar` token in BOTH identifier paths (`ffi_type_identifier`
/ `moonbit_type_identifier`) instead of the generic `Underscore`
mangle, so zod's `$ZodType` (DollarZodType) no longer collides with
`_ZodType` (UnderscoreZodType). That collision was what forced the
round-5 prune to drop zod's upcast helpers; with distinct names the
helpers survive with precise type args and the fully generated chain
`user_schema.asUnderscoreZodType().asZodType().safeParse(input, None)`
runs end-to-end — the last hand `unsafeCast` in the eval app's zod
path is gone. The zod domain glue return type follows the rename
(`Core_DollarZodLooseShape`).

Gates: full suite 2532 green, all scaffold/fixture/example/realworld
gates green, budget recalibration ZERO drift (the merges and renames
net out). Naturalness evaluation: the 3-package app drops to 4 escape
hatches. Remaining ranked: mutating config headers inside interceptors
(AxiosHeaders methods), Buffer.toString, JSValue value slots (zod
shape values need per-value casts).

Round 8 (same day) — checker-driven JSValue concretization round 2:
`typeof` value queries. Mining the generated corpus surfaced one
dominant inferable cluster: `readonly reference: typeof someFunction`
members (valibot declares ~190, axios exposes `typeof Axios` /
`typeof isCancel` style statics, glob/yaml similar) all collapsed to
bare `JSValue` because `typeof` of a GENERIC or overloaded function
never resolved. Fixes, all in the decl lowering:

- `typeof_func_decl_to_func_type` substitutes each type parameter by
  its declared bound (`Any` when unbounded; bounds may reference
  earlier params, so they resolve left-to-right) before lowering, so
  a generic function's `typeof` still yields a concrete callable
  shape (`typeof ip` -> `() -> IpAction[String, JSValue]`).
- the resolver now collects sibling overloads (`find_func_decls`) and
  merges the round-7 trailing-param pattern into one signature before
  falling back to the least-widening pick.
- `typeof_value_type_is_stable` learned that `null` / `undefined` /
  `never` are CONCRETE types (an `Action<T, undefined>` type argument
  was destabilizing the whole reference), and gained an
  `allow_widened~` mode — used whenever the resolved shape is a
  callable — under which `any` / `unknown` / `object` slots are
  acceptable: they render as `JSValue` params while arity and
  callability stay real.
- `ReturnType<...>` / `Parameters<...>` lower their operand FIRST, so
  `ReturnType<typeof addPairToJSMap>` reduces through the resolved
  function type. This also kills a real leak: yaml's `Pair::toJSON`
  previously rendered `-> ReturnType` backed by a synthesized
  `declare pub type ReturnType` opaque extern.
- ambient classes (`declare class`) parse `static readonly X = "lit"`
  literal initializers into literal TYPES (parser_function.mbt was
  discarding the initializer expression) — string/bool/int literals
  only, mirroring tsc's own inference so the TS7 oracle is safe by
  construction; yaml's `Scalar.BLOCK_FOLDED` getters now return
  single-case enums instead of `JSValue`. A bridge-side
  `decl_infer_literal_property_type` covers runtime-class clones the
  same way via `static_field_inits`.

Fixture `typeof-inference-entry.d.ts` + wbtest pin all three
behaviors. Oracle: TP 2338 / FP 0 / PFLEGAL 0 / TN 1750 — byte-equal
to the recorded baseline. Corpus (5 budget rows recalibrated): axios
JSValue functions 61 -> 37 and surface 190 -> 166; yaml 67 -> 62 /
177 -> 172; valibot unknown/any 1166 -> 926 (-240) with surface
1738 -> 1858 — the resolved `reference` members now emit callable
method decls whose `IpAction[String, JSValue]` rendering the cause
heuristic files under tuple/array, i.e. the same widening now ships
usable callable surface instead of a bare `JSValue` slot.

Remaining inferable clusters recorded for later rounds: `expects:
null` literal members (~104 in valibot) still widen — typing them
needs an opaque null representation decision; value-or-function
unions (`ErrorMessage<T> = string | ((issue) => string)`, ~157
`message` members) need an untagged-union construction story.

Round 9 (same day) — both recorded clusters landed.

Instantiated generic union aliases: NON-generic `string | fn` union
aliases already lowered to tagged-union enums with constructors and JS
converter glue; the gap was the APPLIED generic form
(`ErrorMessage<Issue>`), which inlined to an anonymous union that the
inline synthesizer refuses (function members) and so widened to
JSValue. `decl_instantiated_union_alias_name` now names the
instantiation (`ErrorMessageOfIssue` via the utility suffix namer)
when the substituted+lowered body is a union WITH a function member
that `tagged_union_type_alias_decl` accepts, registering it in a
`decl_synthesized_union_aliases` registry (reset at decl-emit start;
drained by the decl emitter after all cloning and merged into the
FFI's exported tagged unions — decl runs first in a bundle, mirroring
the round-6 object-struct registry). Hooked into both the same-module
`applied_type_alias` inline path and the qualified/cross-module
`decl_inline_qualified_applied_alias`, plus the collection-walk
mirror so interfaces referenced ONLY from the enum's function-typed
case payloads still get their declarations (valibot's ArrayIssue /
VariantIssue / MapIssue / RecordIssue / SetIssue compiled only after
this). The case-payload dependency scan got a shared helper
(`tagged_union_case_named_refs`) that walks Func params/returns —
both the decl opaque-companion list and the FFI external-type marking
previously only saw bare `Named` / `Array(Named)` payloads.

`null` literal members: a member typed exactly `null` (valibot's
`readonly expects: null`, ~98 members) now references a shared opaque
`JSNull` companion instead of widening — referenced-but-undeclared
names already get their opaque decl emitted by both layers, so the
representation costs one `declare pub type JSNull` line; the name is
exempted from the emit-time unresolved-reference sanity note.

Fixture `union-alias-instantiation-entry.d.ts` + wbtest pin both.
valibot corpus effect (2 budget rows): JSValue surface 1858 -> 1437
(-421), unknown/any 926 -> 504; 140 ErrorMessageOf* enums, message
members now `ErrorMessageOfIpIssueOfTinput1?`-style typed enums with
`..._from_string` constructors and typeof-discriminated from_js glue.
zod/yaml rows unchanged (zod's message unions were already
string-subset-lowered; yaml's value-or-function members are anonymous
inline unions — still open, needs an inline construction story).

Round 10 (same day) — ANONYMOUS inline value-or-function unions, the
last recorded value-or-function gap. `ffi_synthesize_inline_union`
refused every union with a function member (a guard from the react
hooks era whose motivating case — `S | (() => S)` with S widened —
can't reach synthesis anyway: the widened arm has no runtime
discriminator). Lifting it needed two safety pieces:

- SHAPE-tagged constructor names: a structural alias name that spells
  every function case as bare `FnValue` would merge yaml's
  `uniqueKeys: boolean | ((a: ParsedNode, b: ParsedNode) => boolean)`
  and `sortMapEntries: boolean | ((a: Pair, b: Pair) => number)` into
  one `Auto_BoolValue_or_FnValue` with whichever payload registered
  first. `moonbit_inline_union_func_case_name` (parser package, shared
  by the decl renderer and the bridge FFI so both compute identical
  names) encodes params and return into the case name:
  `Auto_BoolValue_or_FnPairPairToDoubleValue` vs
  `Auto_BoolValue_or_FnParsedNodeParsedNodeToBoolValue`. All three FFI
  sites that derive the synthetic name now go through one
  `ffi_inline_union_shaped_cases` helper.
- at most ONE function member per union: every function case
  discriminates via `typeof === "function"`, so a second would be
  indistinguishable at the boundary — both sides refuse those.
- Named siblings must be RUNTIME-DISCRIMINABLE: a function-armed union
  only synthesizes when every Named member is a well-known JS global
  constructor (`moonbit_inline_union_runtime_named_ok`: RegExp / URL /
  URLPattern / Date / Buffer / typed arrays / ...) whose `instanceof`
  works in the generated converter. The first attempt (reject local
  type params) missed `useState(initialState: S | (() => S))` — its
  `S` isn't registered as a local param on that path — and the
  generated from_js tested `value instanceof S` against a name that
  doesn't exist in bridge.js. Interfaces / aliases / type params all
  fail the allowlist, so only truly discriminable unions synthesize.

The synthesized-inline emission loop also switched its payload
dependency scan to `tagged_union_case_named_refs` (playwright's
`(url: URL) => boolean` case needed the `URL` external companion that
the old bare-Named scan missed). Fixture `inline-fn-union-entry.d.ts`
+ wbtest pin the two-distinct-signatures case.

Corpus (net, after the runtime-named guard): playwright's
`page.route(...)` family now takes
`Auto_RegExpValue_or_StringValue_or_URLPatternValue_or_FnURLToBoolValue`
instead of JSValue (functions 200 -> 196, surface 827 -> 811); yaml
172 -> 168 with uniqueKeys/sortMapEntries typed; node:fs 34 -> 28;
lodash 1651 -> 1644; pino / zod / axios / node:util small drops;
react unchanged (its candidate unions all carry interface-typed value
arms that the guard correctly refuses).

Round 11 (same day) — event-map literal-overload specialization, the
top pick from the unlock survey. Interface members overloaded on a
literal first param followed by a listener
(`on(event: 'close', listener: (page) => void)` x56 event names on
playwright's Page alone) merge to nothing under the round-7
trailing-param rule, so only the first declaration survived with both
params widened. Each such family (>= 2 distinct literals — a lone
literal-first method is not an event map; and the second param must be
a function, so literal dispatch like react's `createElement('div')`
stays untouched) now synthesizes per-literal companion members:
`on_close((Browser) -> Unit) -> Browser`. Pieces:

- detection runs on the PRE-rewrite lowering in
  `append_lowered_interface_field` (the inline-callback naming pass
  would otherwise hide the `(Literal, Func)` shape behind a named
  opaque callback);
- `decl_event_member_families` records (literal, companion type) per
  owner+member so the FIRST overload's companion appears retroactively
  when the second literal arrives; companions re-push into every clone
  (the decl and FFI layers each clone the interface — the per-clone
  `seen_field_names` keeps it idempotent);
- `decl_event_member_specials` maps each companion to
  (JS member, literal); the FFI emits
  `#| (self, arg0) => self.on("close", arg0)` — and on
  generic-preserved receivers a BOUND-closure getter
  (`(o) => (...args) => o.on("close", ...args)`) so `this` survives;
- listener returns declared `any` / `unknown` normalize to `void` in
  the companion (`(page) => any` is fire-and-forget for the emitter) —
  without this every companion line carried a spurious `JSValue`
  return and playwright's metric tripled.

Runtime-verified: a generated `browser.on_close(fn(_b) { ... })`
registers through the real `.on("close", ...)` and fires (smoke in
scratch; fixture `event-map-entry.d.ts` + wbtest pin the shapes).
playwright gains 76 typed `on_* / once_*` methods; JSValue functions
196 -> 191 with surface 811 -> 842 (+31: companions whose payload
types still widen — new usable surface). Class-METHOD event maps
(ws / chokidar / node:fs watchers) are not yet specialized — the same
registry approach extends to `append_class_method_once` +
`ffi_class_method_decl_to_moonbit`; recorded as the next step.

Round 12 (same day) — nonempty-tuple normalization (#2 of the unlock
survey). `[T, ...T[]]` (valibot / zod `issues` fields) is a nonempty
ARRAY for the bridge surface; as a tuple it widened to
`Array[JSValue]` and lost the element type. `decl_nonempty_tuple_element`
recognizes a trailing rest whose element equals every fixed element
and the Tuple lowering arm rewrites to `Array(element)`; boundary
representation is unchanged (a JS array either way). Elements that
resolve concretely now surface (`issues : Array[BaseIssue[TInput_1]]?`);
the ~70 that remain `Array[JSValue]` carry `InferIssue<TSchema>`
conditional elements — honest widening. Zero budget drift. The
common-base ELEMENT join half of the survey item turned out to be
already covered: `Array(Named(alias))` lowers the alias through
`decl_join_union_alias_to_common_base` on the Named arm.

Round 13 (same day) — record-and-class intersections (#5 of the
survey: the axios eval-app's last interceptor hatch). axios's
`AxiosRequestHeaders = RawAxiosRequestHeaders & AxiosHeaders` widened
to an unresolved opaque name, so `config.headers` inside an
interceptor had NO usable surface even though the `AxiosHeaders`
CLASS (set / get / has / set_content_type / ...) was fully generated.
`decl_intersection_single_class` resolves an intersection to its
single declared-CLASS member when every sibling is record-ish (object
literals, `Partial<...>` / `Record<...>` applications, aliases that
resolve to neither class nor interface — an interface sibling
refuses, dropping its fields would lose surface). The alias now emits
`pub type AxiosRequestHeaders = AxiosHeaders` (transparent) and
`config.headers.set(Some("X-Trace"), Some(v), None)` type-checks —
compile-verified against the generated axios package. Fixture
`intersection-class-entry.d.ts` + wbtest pin the rule. Zero budget
drift.

Survey status: #1 event maps (interfaces) DONE round 11, #2 nonempty
tuples DONE round 12, #5 AxiosHeaders DONE round 13. Remaining: #3
schema value slots (zod `loose_shape_from_pairs` still takes
`Array[JSValue]`; a `$ZodType`-bounded value slot + upcast-at-call is
the sketch), #4 lodash chain generics (big, budgeted), and the
class-METHOD event maps follow-up from round 11 (ws / chokidar /
node:fs watchers).

Round 14 (same day) — #3 schema value slots + #4 method-level
generics, closing the survey.

#3: the zod module hook gains a TYPED shape builder alongside the raw
one — `loose_shape_of(keys, values : Array[Schema[JSValue, JSValue,
JSValue]])` accepts the same upper bound `as_schema` produces, so the
gate smoke's shape entry is now
`loose_shape_of(["name"], [as_schema(string(None))])` with no
per-value unsafeCast.

#4: `map<U>(fn: (item: T) => U): CollectionChain<U>` on a GENERIC
owner widened U to JSValue on every chain-style API. The member's own
binder now survives on the pure-MoonBit wrapper:
`fn[T, U] CollectionChain::map(self, (T) -> U) -> CollectionChain[U]`.
Pieces:
- both interface cloners now CARRY `method_type_params` (they emitted
  `[]`, so the renderers never saw the binder);
- both renderers thread the member's binder (interface methods carry
  it out-of-band in `iface.method_type_params`; inline object members
  as `GenericFunc`) — the decl side pushes it as local type params and
  emits a combined prefix, the FFI side routes through a monomorphic
  getter returning a BOUND closure and a `pub fn[T, U]` wrapper
  (generic externs are forbidden; a plain fn casting the fetched
  closure is not);
- binder names whose occurrences were widened away are FILTERED from
  the prefix (`*_rendered_mentions_param` token scan) — an unused fn
  type parameter is a hard error [4027] (zod's `register` / `brand`
  hit this immediately);
- while smoking this against a real prototype-method implementation,
  the PRE-EXISTING generic-receiver form `(self.first)()` turned out
  to lose `this` (extracts the prototype method, calls it unbound —
  TypeError on any class-based library). ALL generic-receiver members
  now fetch a bound closure (`(o) => (...args) => o.first(...args)`)
  through the getter; the gate's sanitized-member marker moved to the
  bound form.

Runtime-verified: `c.map(fn(x : Double) { x.to_string() })` returns a
usable `CollectionChain[String]` and `compact()/first()` no longer
throw on class-implemented chains. Fixture `chain-generics-entry.d.ts`
+ wbtest; the StatsBase wbtest moved to the bound-getter expectation.
Corpus (8 rows): playwright JSValue functions 191 -> 179, lodash
288 -> 286 with surface 1644 -> 1634, zod 1497 -> 1493, source-map
-1; pino +1 line (a preserved generic slot now renders — new usable
surface). Top-level generic FUNCTIONS (`chain<T>(items)`) still widen
— that path has no receiver to hang a getter on; recorded as open.

Round 15 (same day) — CLASS-method event maps, the round-11
follow-up. Detection had to run on the RAW method (the clone rewrites
the listener to a named opaque callback, hiding the `(Literal, Func)`
shape — the same trap the interface path hit); the companion is built
from the raw method (first param dropped, `any`/`unknown` listener
returns normalized to `void`) and THEN cloned through
`clone_class_method_in_scope`, with the same >= 2-distinct-literals
activation, per-clone re-push, and `decl_event_member_specials`
registration. The FFI class-method emitter consults the registry and
injects the literal at both instance js_call sites
(`(self, listener) => self.on("change", listener)`). ws gains 18
typed `on_*` companions (`WebSocket::on_message` etc.; surface +12 —
companions whose payload types still widen); chokidar's FSWatcher
declares no literal overloads of its own (EventEmitter inheritance)
so it is unaffected. Fixture `event-map-entry.d.ts` extended with the
Watcher class + wbtest.

Profiled with `moon bench --target native` + callgrind over the release
`tscheck` binary (`--parse` / full, `--iters N`; use
`--toggle-collect=<mangled check entry>` to isolate the check phase from
the parse). Five landed batches, all behavior-preserving (full suite
2523 green, oracle byte-identical TP 2338 / FP 0 / TN 1750 / MISS 396,
every gate green):

1. Parser whole-source rescans (`20ff7e7`): `from_source_with_jsx`
   lowered the FULL source 3x per parse (`@noImplicitThis` x2,
   `@filename:`); all whole-source markers now come from one
   `scan_source_directive_flags` pass over `@` positions. The ~10
   conformance-header detectors each sliced+lowered their own 1KB head
   -- multiplied by JSX speculation re-entering `from_source_with_jsx`
   on sub-sources (2k+ nested parses on parserharness.ts); the head is
   now computed once per parse and threaded through. `parse_jsdoc_block`
   rewritten single-pass over StringViews (was 3+ owned strings per
   comment line); the lexer passes the comment span without copying.
2. Checker structural scans (`58527b4`): `iface_extends_reaches` was
   O(ifaces^2 x chain) via per-step rescans of every interface decl
   (~7.5% of a dom.generated.d.ts run) -- now a prebuilt name->extends
   adjacency map + hash-set DFS. `is_lib_global_value`/`_type` (generated
   1k/2.2k-arm string matches, probed once per reference; 9.6% of a
   generic-heavy run) now memoize per name via gen_lib_globals.sh.
3. Bench coverage: `moon bench` gains JSDoc-heavy (300 documented
   decls) and old-style-cast-heavy (200 funcs, JSX speculation) parser
   fixtures so both optimized paths regress visibly.

Measured (release tscheck, per iteration):
- es5.d.ts parse 11.7ms -> 6.1ms (~19 -> ~36 MB/s); full check 15 -> 9.7ms
- dom.generated.d.ts parse 115 -> 60ms; full 170 -> ~100ms
- parserharness.ts parse 44 -> 30ms; full 60 -> 49ms
- generic-heavy check phase 26 -> 19ms
- moon bench parser fixtures -17%..-38%

4. Paren-JSX speculation gated on `allow_jsx` (batch 4): tscheck was
   already extension-driven (`.tsx` only), but THREE paren-path JSX
   attempts (`try_parse_parenthesized_jsx_expr` + the two
   `peek_at(1)==Lt` temp parses in `parse_parenthesized_expr` /
   `parse_primary`) ignored the flag, so every `(<any>x)` cast in a
   `.ts` file ran the full JSX source scan + nested embed sub-parses
   and threw the work away. All three now early-out in `.ts` mode --
   tsc-aligned (`(<T>x)` is a parenthesized type assertion there).
   parserharness.ts parse 30 -> 11ms (44ms pre-round; -75% total),
   full check 49 -> 35ms, byte-identical diagnostics and oracle
   results. `moon bench` cast fixture split into `.tsx`-mode (4.96ms,
   speculation still exercised) and `.ts`-mode (3.51ms) variants.

5. Module-pass allocation hoists (batch 5, check-phase Ir on
   dom.generated.d.ts 552M -> 473M, -14%): `check_structural_duplicates`
   and `walk_module_undeclared_tps` interpolated their diagnostic path
   string (`"interface \{name}"` etc.) once per FIELD/PARAM instead of
   per declaration — hoisted; `walk_module_undeclared_tps` also did a
   linear scan of `method_type_params` per field (quadratic on lib.dom
   interfaces) — now grouped once per interface;
   `check_interface_extends_compat` rebuilt the base interface's
   field/overload-count maps once per (derived, base) EDGE — popular DOM
   bases like `Event` are extended by hundreds of interfaces — now
   cached per base name, and the derived counts hoisted out of the
   bases loop.

Remaining known sinks (next round candidates): `.tsx`-mode JSX
speculation still re-lexes substrings per `<` attempt (only matters
for real `.tsx` sources now); refcount+alloc runtime overhead is
~29% of the remaining check-phase profile and ~25-30% of parse (only
fixable by allocating less); String-keyed Map probes are ~8% of the
check phase spread across all passes (an interned-name or ID-keyed
resolver would be a deep refactor); `Parser::peek/check` +
`TokenKind::equal` are ~30% of body-heavy `.ts` parses (each peek
copies a Token and refcounts its payload; a tag-int fast path would
need parser-wide changes).

## TS Checker Conformance (current state, 2026-09-01 — TypeScript 7)

State: whole-corpus **TP 2346 / MISS 388 / FP 0 / PFLEGAL 0 / TN 1750**
(classified 4484, NOTRUN 14) via
`scripts/checker_conformance_oracle.sh --max-fp 0 --max-legal-parsefail 0`.

**The MISSes are ranked now, and the strategy doc was wrong.**
`scripts/checker_miss_buckets.mjs` (`just checker-miss-buckets`) classifies
every single-file case in parallel, caches the per-file verdict, and buckets
the MISSes by the error codes in the submodule's baselines. Its totals are
cross-checked against the oracle — a miner that disagrees with the gate is a
broken miner, and that had to be visible rather than assumed. The verdict
(errors / accepts) comes from the vendored TS7 manifests; only the bucket
LABEL comes from the TS6-era baselines, which is an approximation and is
documented as one. A MISS with no baseline file lands in `NOBASE` rather
than being dropped.

The answer contradicts `docs/checker-priority.md`, whose conclusion —
"増分的な sound recall win は枯渇" — was measured against the **TS6** oracle
in June:

- **128 of the 388 MISS files are flippable by a pure-grammar (TS1xxx)
  rule.** No assignability, no flow narrowing, no generic instantiation.
- **91 of them have baseline codes that are ALL TS1xxx**, i.e. not one type
  judgement is needed anywhere in the file.

Batch BU (2026-09-01): TP 2337 -> 2346, MISS 397 -> 388, FP / PFLEGAL 0.
Nine files, three rules, and the first one was a BUG before it was a recall
item:

- **TS1100** (`eval` / `arguments` as an assignment target, 4 files).
  JavaScript spells that target four ways — `eval = 1`, `eval += 1`,
  `++eval`, `eval++` — and the rule had been written twice, at the two
  assignment spellings, with nothing at either update. `"use strict";
  eval++` parsed clean. Tenth instance in this repo of one rule written in
  several places and applied in some, so the fix is one helper
  (`record_assign_target_strict_misuse`) called from all four rather than a
  third and fourth copy. The strict gate came off as well: tsc reports
  TS1100 for `eval = 1` in a plain script with no prologue and no flag
  (probed), and the oracle errors on both `-negative` files, so the gate was
  silencing half the corpus cases on top of the missing spellings. Ambient
  declarations are the one exemption tsc makes
  (`declare function f(eval: number)` is clean) and are unreachable from an
  assignment position; BINDING positions keep their own gate.
- **TS1101** (`with` statement, 3 files — including
  `arrowFunctionContexts`, which the bucket labels could not name because it
  has no TS6 `.errors.txt`). Unconditional: TypeScript rejects `with` in
  every configuration.
- **TS1114** (duplicate label, 2 files). `self.labels` was already scoped
  exactly the way the rule is — pushed on entering the labelled statement,
  popped on leaving, and saved/cleared/restored at every function-body parse
  site — so the check is one `contains`. The two TS7-ACCEPTED neighbours
  prove it rather than merely not-contradict it: sequential labels
  (`duplicateLabel4`) and a re-use inside a nested function
  (`duplicateLabel3`) both stay clean.

The `with` rule found the one false positive in the round, and it is worth
recording because it is a general constraint on every grammar check added
from here: `topLevelVarHoistingCommonJS.ts` is TS7-ACCEPTED and its
`with (_)` is preceded by `// @ts-ignore`. Our issues carry no line
positions, so file granularity is the only FP-safe reading — the same choice
the TS2465 / TS1166 family already made — and both new statement-level rules
go through `record_suppressible_grammar_misuse`.

Two tooling defects came with the round, both of the "my own harness was
lying to me" kind this file keeps recording. The oracle preferred the
RELEASE binary unconditionally and printed nothing about its choice, while
`just verify-checker-soundness` builds DEBUG — so a release binary left from
an earlier session silently won, and six target files "did not change"
because the harness was running code from before the change. It picks the
newer build now and prints which. CI never saw it: a fresh checkout has
neither binary until the recipe builds one, which is exactly why it
survived. And `moon check --deny-warn` cannot be used as a gate here at all
(451+ pre-existing warnings); plain `moon check` with `0 errors` is the
check.

DEFERRED with the reason, not attempted: **TS1212 / TS1213** (reserved word
as a binding name). All nine strict-reserved words are TS1212 even in a
sloppy script (probed), and the existing gate at
`parse_binding_pattern` covers only three (`interface` / `let` / `yield`);
adding the other six would win 2 files (`parser642331`, `parser642331_1`).
It is NOT worth it yet, for a product reason rather than a corpus one:
`declare function f(static: number)` is clean in tsc and
`function f(static: number)` is TS1212, so the rule needs an ambient
exemption the parser cannot currently express (`in_ambient_module` is a
whole-parse mode; there is no per-declaration flag), and getting it wrong
false-flags npm `.d.ts` files — the bridge's primary input. Two files
against a new FP channel in the product is the wrong trade. The corpus
itself carries no counter-example: the one accepted file matching a
reserved-word binding (`parserSyntaxWalker.generated.ts`) has all its
matches inside comments.

Also deferred: **TS1115** (`continue` to a non-iteration label, 1 file).
Needs iteration-ness per label, which `self.labels` does not carry, and
adding a parallel stack means mirroring the save/clear/restore at 12+ parse
sites — the exact shape of the bug family above. The right implementation is
a post-parse AST walk over `Label(name, body)` / `Continue(Some(name))`,
which is ~40 lines for one file; worth doing after the cheaper buckets.

## TS Checker Conformance (2026-07-17 — TypeScript 7, superseded above)

react joined the real-world gate as the 21st package (2026-07-18):
`package|react|react|` resolves types through @types/react, the bridge
emits a 3,898-line surface (83 types / 58 functions / 117 structs), and
the smoke tests exercise createElement / isValidElement / createRef /
version end-to-end on react@19.2.4 (both the in-package test and the
build-smoke main). Budgets calibrated from measured metrics (JSValue
functions 30, cause split 129|43|8|24|34|14|6, unsupported exports 0);
policy budgeted-fallback alongside preact until a dedicated
JSX/component binding layer exists.

JSX/component layer v1 (2026-07-19): a MoonBit closure IS a React
function component at runtime, and the generated react bridge now ships
the glue to use it typed. When the module spec is exactly `react`, the
ffi emits `element_of_component[Props]((Props) -> JSValue, Props?,
Array[JSValue]) -> JSValue` (React.createElement over a MoonBit
closure) and `use_state_typed[S](S) -> (S, (S) -> Unit)` (useState as a
generically-typed value/setter pair; the setter re-enters React through
the captured dispatch). Proven end-to-end in the gate: a counter
component defined entirely in MoonBit -- `use_state_typed(41)` +
`createElement("div", ...)` -- mounts via `element_of_component` and
`react-dom/server`'s renderToString returns `<div>41</div>`. The
injected layer adds zero JSValue-metric regressions (react budgets
unchanged); react's fallback policy note now records the layer.
Remaining for v2: typed intrinsic-element props (attribute structs),
useEffect/useReducer typed wrappers, preact parity, and a react-dom
corpus entry. Oracle unchanged (TP 2338 / FP 0 / TN 1750).

Flagship-callable round (2026-07-19): three surface gaps closed and ws
joins the gate (42 packages + 10 node builtins = 52 entries). (a) ws
interop: cjs-module-lexer misses CJS alias re-exports, so the glue's
named class bindings now fall back through sibling aliases of the same
runtime entity -- statically-known siblings from the export surface
plus `const Y: typeof X` value aliases (`const Server =
__ts_mbt_module.Server ?? __ts_mbt_module.WebSocketServer`); a
noServer WebSocketServer constructs and closes from MoonBit. (b) Call
signatures on VALUE exports surface as callable module functions: the
richest `<call>` signature of a const's inline object type or Named
interface emits under the export's own name --
`minimatch("bar.foo", "*.foo", None) -> Bool` and chalk's
`default(...) -> String` now work directly. (c) Overload variants that
differ only in RETURN type survive wrapper emission: the base-signature
skip compares against the export's actual base (not `preferred[0]`),
the "wider" disqualifier only applies against same-return picks, and
`undefined`-typed parameter slots get a suffix -- uuid's `v4():
string` emits as `v4_version4_options_optional_undefined_number_optional`
and generates+validates a real v4 at smoke time. The broader
push_preferred collapse stays param-count-keyed (loosening it regressed
the React fixture's namespace-member naturalization). Budgets
recalibrated for uuid / valibot / immer / superstruct / lodash.
Oracle unchanged (TP 2338 / FP 0 / TN 1750); moon test 2523/2523.

Top-download expansion (2026-07-19): eight of npm's most-downloaded
packages verified end-to-end and added to the real-world gate (41
packages + 10 node builtins = 51 entries): axios (getUri asserted
against baseURL+url config), commander (option parse --debug ->
opts.debug), debug (enable/enabled/disable + logger factory), chokidar
(FSWatcher construct + close), pino (logger level from options),
lodash (camelCase / kebabCase / chunk -- 435 declared functions from
the fixed reference-following + value-interface surface), uuid
(validate / version after the glue fix), minimatch (filter matcher
after the segfault fix). ws deferred: cjs-module-lexer does not expose
its `Server` alias as an ESM named export, so the generated static
binding is undefined at runtime -- needs interop-tolerant class
bindings (same family as the node:* tolerance) before it can join.
rxjs / ajv / undici structurally healthy (method-surface heavy),
queued as budgeted-fallback candidates.

Default-export / export= naturalization (2026-07-18): the two
structural gaps behind the probe's weak surfaces are fixed and the
corpus grew to 33 packages. (a) Module resolver: a raw `.js` "main"
no longer shadows tsc's implicit package-root `index.d.ts` lookup in
Types mode (deepmerge ships index.d.ts with `"main": "dist/cjs.js"`
and no `types` field -- the whole declaration surface was erased);
resolution now retries declaration-ish results first, then root
index.d.ts, then the raw script as last resort. (b) Export semantics:
`TsModuleBlock.has_export_equals` records CJS `export =`, and
`resolve_imported_binding_export` forwards a namespace import binding
(`import X = require("./sub")` / `import * as X`) through the target's
`default` export when the target uses `export =` -- X IS the assigned
entity, so `export { X as valid }` re-export chains (@types/semver's 42
per-function files, @types/picomatch) now surface callable typed
functions instead of `get_*() -> JSValue` getters. Results: semver 97
callable externs (valid/clean/major smoke-tested), picomatch callable
`default(glob) -> Matcher` (match/non-match smoke), deepmerge callable
`default` merge (both-keys smoke) -- all three added to the gate with
calibrated budgets (33 packages + 10 builtins = 43 entries green).
Oracle unchanged (TP 2338 / FP 0 / TN 1750), moon test 2523/2523.

Corpus expansion round 2 (2026-07-18): nine more npm packages verified
end-to-end and added to the real-world gate (30 packages + 10 node
builtins now): ms, nanoid, dayjs, qs, yaml, superstruct, eventemitter3,
mitt, marked -- each with a runtime bridge smoke that calls a real API
and asserts the result (ms "1m", nanoid length, dayjs format, qs
parse/stringify, yaml roundtrip, superstruct assert/validate,
eventemitter3 on/listenerCount, mitt on/emit handler count, marked
"# hello" -> <h1>). Two real-package bugs found by the probe and fixed:
(a) parser -- `export default function mitt<T>(...): U;` (bodiless named
default in a .d.ts) crashed the module-block path at the missing `{`;
named defaults now route through the declaration parser like the
checker path already did; (b) bridge -- the .mbti fn-decl line parser
used `rev_find(")")` for the parameter-list close paren, which grabs the
RETURN type's paren when a value getter has a curried function type
(marked's `get_use_` emitted unparseable MoonBit); it now depth-scans to
the paren matching the open. Probe leftovers documented: semver / 
picomatch / deepmerge surface as JSValue-only or empty (default-export
function naturalization gap), tracked as a future bridge target. Oracle
unchanged (TP 2338 / FP 0 / TN 1750); corpus react pin moved to 19.2.7
(react-router peer floor).

Batch BX (2026-07-18): @types/react@19.2.17 audit — 13/13 files parse
clean and the declaration bodies check clean; the only reports were
TS2307 module-resolution complaints for imports that DO resolve on disk
(`csstype` is a declared dependency of @types/react, `./` is the
package-root self-import in jsx-runtime). tscheck now resolves module
specifiers against the filesystem for files living under node_modules
(relative specs probe the usual `.d.ts` / `index.d.ts` candidates; bare
specs walk up to `node_modules/<pkg>` / `node_modules/@types/<pkg>`)
and suppresses TS2307 when the import resolves. Conformance corpora
live outside node_modules, so the oracle is unchanged (TP 2338 / FP 0 /
TN 1750); truly-missing modules inside node_modules are still flagged
(verified by negative control). All three real-world declaration
surfaces are now fully clean: lib.d.ts 108/108, @types/node 88/88,
@types/react 13/13. `ts2mbt decl` emits a 3,135-line MoonBit surface
from @types/react (useState and the hook family included). The
rwcorpus package.json now pins every gate package (plus @types/react
and @types/express) so `npm install` no longer prunes them.

Batch BW (2026-07-17): lib.d.ts / @types/node checker issues driven to
ZERO — 108/108 lib files and 88/88 @types/node files check fully clean.
Fixes: (a) the type-param-arity check learned MINIMUM arity — the parser
records `<generic-min-arity>NAME=K` (leading params without a default)
at every generic declaration site, ambient `declare module` / `declare
global` sub-parses propagate the suppression-only sentinels to the outer
module (they were parsed by a fresh Parser and lost), and `check_arity`
flags under-application only below the minimum (`Iterable<T, TReturn =
any, TNext = any>` legally takes 1..3 args; TokenForOptions likewise) —
this replaced an unsound exact-arity rule that also cost 4 lucky TPs
(conditionalTypes1 / inferTypes1 / recursiveMappedTypes /
varianceAnnotations under-apply LEGALLY and were flagged for the wrong
reason; TP 2342 -> 2338, FP still 0); (b) interface accessor syntax
(TS 5.4 `get x(): T` in interfaces, lib.es2024/lib.dom) parses as a
readonly-property pair; (c) interface-extends member compat exempts
generic methods (CallableFunction.call), covariant Named returns via the
extends chain (getElementById), optional-over-required when the derived
member is `any` (BeforeUnloadEvent.returnValue), optional-method
overload duplicates (Process.send), and tuple members whose elements
narrow covariantly through the extends chain (http2
ClientHttp2SessionEventMap `stream`: ClientHttp2Stream extends
Http2Stream); (d) TS2307 abstains in `declare global` bundles
(fetch/streams/undici-types) and for node builtin subpaths
(`stream/web`); (e) arity check tolerates type-param defaults declared
only via merged declarations (min across duplicates).

Batch BV (2026-07-17): driving the BU-audit residuals down —
lib.d.ts 569 -> 14 issues (103/108 files clean), @types/node 41 -> 14
(80/88 clean); oracle unchanged (TP 2342 / FP 0 / TN 1750). Fixes:
(a) interface-extends member compat now skips OVERLOADED members —
tsc compares the whole overload set, and the pairwise entry comparison
misfired 464 times on lib.dom's `addEventListener` specialization
pattern alone; (b) `check_type_undeclared_tps` skips callable members
of object-literal types (the parser discards signature-level type
params there — Process.finalization's `register<T>`), and accumulates
method type params across ALL same-name overload entries instead of
letting the last overload win (lib.dom `querySelector<K>`/`<E>`);
(c) TS2307 abstains for `node:*` / classic Node builtin specifiers and
inside ambient-module declaration bundles. Remaining residuals (28
total): timers' `RefCounted` cross-scope refs, lib.dom accessor-pair
`get`/`set` duplicate-identifier misparse, type-param DEFAULTS in the
arity check (TokenForOptions), CallableFunction/Function member compat,
undici-types cross-package import.

Batch BU (2026-07-17): full-surface parse audit of `typescript@6.0.3`
`lib*.d.ts` (108 files) and `@types/node@26.1.1` (88 files): 196/196
parse clean (0 parse errors); `@types/node` emits substantive decl
surfaces (fs 459 / crypto 552 / util 106 MoonBit decls), `lib.*` files
are global ambient scripts with an intentionally empty export surface.
Checker false positives found by the audit and fixed (all
`declare module "spec" { ... }` body exemptions — the parser flattens
those bodies into the parent module without ambient flags): TS1046
top-level-modifier (197 hits in fs alone), TS2564 strict-property-init
(util's MIMEType), and the trailing-void overload heuristic (crypto's
randomInt / verify). After the fixes @types/node checks 69/88 files
fully clean (41 residual issues, mostly interface-generic `T` scoping
and cross-file globals); lib.d.ts residuals concentrate in lib.dom
(482 of 569, deep DOM hierarchy modeling limits). Oracle unchanged
(TP 2342 / FP 0).

Batch BT (2026-07-17): TP 2341 -> 2342, MISS 393 -> 392, FP / PFLEGAL
still 0. Class-expression member bodies no longer inherit control-flow
narrowing: the parser lowers `class { ... }` expressions to a `<class>`
IIFE, and `check_funcexpr_with_context` now rebinds captured variables at
their DECLARED types for that marker — class members execute after the
guard region, so tsc does not narrow into them (typeGuardInClass).

Batch BS (2026-07-17): TP 2338 -> 2341, MISS 396 -> 393, FP / PFLEGAL
still 0. Mining the TS2322 cluster (30 files, 17 single-code): (a) a
concrete primitive assigned to an opaque generic indexed access
(`tp: T[P]; tp = s`) is always TS2322 — matches both the raw
`IndexedAccess(Named(T), _)` annotation and the bound-substituted
`IndexedAccess(_, Keyof(...))` shape parameter registration produces
(nonPrimitiveConstraintOfIndexAccessType); (b) `x: T & U` with
union-of-primitive constraints is bounded by the member-set intersection
of the bounds — a target union missing one of the members rejects it
(intersectionWithUnionConstraint, plus one multi-code file). Assessment
of the remaining TS2322 files: functionExpressionContextualTyping2 /
contextuallyTypeCommaOperator02 / typeGuardInClass (class-expression
narrowing reset) / callChain.3 / objectLiteralNormalization /
typeFromPropertyAssignment31 look feasible next; generatorTypeCheck8
(iterator protocol compat), symbolProperty46 (symbol-keyed accessors),
conditionalTypesExcessProperties, templateLiteralTypes7 need deeper
machinery.

Batch BR (2026-07-17): TP 2333 -> 2338, MISS 401 -> 396, FP / PFLEGAL
still 0. Bodiless generator declarations (`declare namespace M {
function *g(): any }`, generator overload signatures, bodiless `*m()`
class methods) are always-error grammar misuses recorded at parse time
(generatorInAmbientContext2/4.d, generatorOverloads1/2/3);
`Constructor(...)` joined `is_definitely_not_callable` (a
construct-signature value called without `new` is TS2348 — inference
doesn't reach it for the remaining corpus cases yet, but the predicate
is sound). Remaining 396 MISS is a long tail (top cluster TS2322 at 30,
71 files with TS7-only baselines).

## TS Checker Conformance (current state, 2026-07-12, superseded above — TypeScript 7)

The oracle now correlates against **TypeScript 7** (typescript-go
v7.0.2). Truth comes from vendored name manifests
(`scripts/ts7_baselines/`, see its README); case files are the
`typescript` submodule at typescript-go's `_submodules/TypeScript` pin
(`4d4f005c`). TS7 removed the ES3/ES5 targets — every `target=es5/es3`
variant is NOTRUN, and the TS6-era deprecated-compiler-option
diagnostics (TS5107/TS5101) were removed from the checker accordingly.

State: whole-corpus **TP 2335 / FP 0 / PFLEGAL 0 / TN 1750 / MISS 399 /
NOTRUN 14** via `scripts/checker_conformance_oracle.sh --max-fp 0
--max-legal-parsefail 0`. Batch BR emptied the legal-parse-failure
budget (decoratorOnClass3, defaultExportWithOverloads01, parser768531)
and the gate now enforces 0.

Batch BE (TS7-only miss mining, +51 TP) worked the misses newly exposed
by the oracle switch:
- TS5102: `downlevelIteration` was REMOVED in TS7 — its presence-based
  recording now surfaces as an error (every ran conformance case
  carrying the directive errors under tsgo; none is accepted).
- TS2378: a class `get` accessor whose body contains NO return, throw,
  or loop must return a value (empty bodies parse as `body: None`;
  ambient / abstract accessors and any explicit `return;` abstain — a
  written `(): any` is indistinguishable from no annotation).
- TS1206: decorators on constructors flag in both modes; on `abstract` /
  `declare` members only under STANDARD decorators (legacy mode accepts
  them — decoratorInAmbientContext); parameter decorators flag only
  without `@experimentaldecorators` and only when the decorator chain's
  last follower is not `class` (a paren'd decorated class expression
  enters the arrow-params trial — esDecorators-classExpression-*).
- TS2373/TS2372: a parameter default (or binding-pattern computed key /
  element default, or class-expression heritage inside one) may not
  reference the parameter itself, a later parameter, or a body-declared
  name (`var` hoisted anywhere, `let`/`const` top-level). Nested
  callables defer evaluation and abstain. Covers module functions,
  class constructors/methods, top-level callable initializers, and
  IIFE arrows.
Sweep round-trip: the first BE sweep surfaced 10 FPs (bare-return
getters, legacy-mode ambient decorators, stacked decorators before
class expressions); all root-caused and fixed before landing.
Batch BF (+19 TP, TP 2222 / MISS 512) continued the mining:
- TS2465/TS1166: `this` in a class member's computed property name
  (direct refs only — nested callables rebind), and computed FIELD keys
  through a declared-`any` call (no literal type — autoAccessor5).
  Whole-file abstention when the source carries `@ts-ignore` /
  `@ts-expect-error` (the parser pushes a `<ts-suppression-present>`
  marker; our issues aren't line-anchored, so file granularity is the
  FP-safe choice — esDecorators-classDeclaration-outerThisReference).
- TS1125/TS1198: `\u{...}` escapes in STRING literals — missing /
  non-hex digits and values past 0x10FFFF (accumulator clamped against
  32-bit wrap). Template literals deliberately NOT counted: tagged
  templates accept invalid escapes (ES2018) and the lexer can't see
  taggedness.
- TS1121: legacy octal integer literals (`01`).
Batch BG (+11 TP, TP 2233 / MISS 501) closed the escape-sequence
remainder:
- Regex `\u{...}` under the `u` / `v` flags: `scan_regex` collects the
  body and `validate_regex_unicode_escapes` requires hex digits and a
  value within 0x0..0x10FFFF (accumulator clamped against 32-bit wrap).
  Without the flag, `\u{2}` is a quantified `u` and stays legal.
- Untagged-template invalid `\u` / `\x` escapes (incl. overflow): the
  lexer records each escape's source position in
  `template_invalid_escape_positions`; the parser counts entries inside
  the Template token's span at the UNTAGGED primary parse site only —
  tagged templates accept invalid escapes (ES2018) and parse through
  the postfix path. Escapes inside `${...}` interpolation sub-parses
  are lost (sub-parser array discarded) — a known miss, not an FP.
- Strings additionally validate `\x` (exactly two hex digits).
Batch BH (+9 TP, TP 2242 / MISS 492) implemented TS2683 —
implicit-any `this` — as a dedicated context-tracking walker
(`check_implicit_any_this` + `ts2683_walk_expr/stmts`):
- IMPLICIT contexts: plain function declarations/expressions without a
  `this` parameter (including ones nested in methods and static-field
  initializer function exprs), namespace top-level statements (a
  namespace body is an IIFE), and class-declaration decorators inside
  namespaces.
- TYPED/EXEMPT contexts: methods/accessors/constructors at their top
  level, arrows (inherit), object-literal FUNCTION values (contextual),
  function exprs in CALL-ARGUMENT position (callee may declare `this` —
  esDecorators-contextualTypes.2), property/index/compound-assignment
  RHS (`Element.prototype.remove ??= function () {…}` —
  thisPrototypeMethodCompoundAssignment), ANNOTATED binding
  initializers, `<class>`-named IIFE lowerings of class expressions,
  true top level (`globalThis`), and `this`-parameter functions.
- Opt-outs: `@noImplicitThis: false` (new `<noimplicitthis-off>`
  marker), `@strict: false`, and the `@ts-ignore` whole-file marker.
Permissive-path only. One stale wbtest pin (`this` in a method-nested
function expr expected 0) was updated to the TS7 verdict.
Batch BI (+24 TP, TP 2266 / MISS 468) took the small syntactic
clusters from the general miss pool:
- TS1049/TS1054: a `set` accessor takes exactly one parameter, a `get`
  accessor none — recorded at the parse sites for both object-literal
  accessors (both parse paths) and class accessors.
- TS1031: `export` / `declare` cannot modify class elements (incl.
  `declare constructor`). The `export` arm consumes the token only in
  MODIFIER position via `can_consume_class_modifier` — `class C {
  export; }` declares a field NAMED export
  (propertyNamesOfReservedWords went PFLEGAL until guarded).
- TS1124: a numeric exponent needs at least one digit (`1e`, `1e+`).
- TS2466: `super` cannot be referenced in a computed property name —
  member chains and `super()` inside comma chains
  (computedPropertyNames24/27). computedPropertyNames30 stays a MISS:
  strada raises TS2466 for `this` in an object-literal computed key
  inside a typed constructor arrow, which our typed-context model
  deliberately treats as legal.
Batch BJ (+12 TP, TP 2278 / MISS 456) took the TS2454/TS2488/TS2403
type clusters:
- ASI vs declaration heads: `namespace` / `module` head a declaration
  only when the NAME sits on the same line (`is_namespace_decl_start`
  rejects a newline-separated follower), and a statement-level `declare`
  with a line break after it is a plain identifier reference (TS's
  modifier ASI rule). `namespace\nn\n{}` is then three statements whose
  reads hit the existing TS2454 unassigned tracking
  (asiPreventsParsingAsNamespace01/02,
  asiPreventsParsingAsAmbientExternalModule01).
- TS2488 beyond class instances (`check_forof_non_iterable`): a for-of
  source that is a non-iterable primitive (`for (const v of 0)`), a
  union with a non-iterable primitive member (`string | number`), or an
  object type whose `[Symbol.iterator]` member is OPTIONAL; plus an
  array-destructuring pattern over a primitive element type
  (`for (var [a = 0] of [2, 3])`, syntactic array-literal sources only).
  The optional-iterator case rides a new parser encoding: STANDARD
  well-known `[Symbol.x]` keys in object-type literals parse as `@@x`
  members instead of degrading the whole literal to `any`
  (user-augmented `Symbol.foo` keys keep the legacy fallback —
  symbolProperty61 FP'd until restricted).
- TS2403 vs lib declarations (`check_lib_global_redeclaration`): a
  script-level initializer-less `var` redeclaring a runtime global
  (`var Symbol: any` / `{ iterator: string }`) must carry the matching
  `*Constructor` interface annotation; module files and `typeof`
  annotations abstain (ES5SymbolProperty3/4/7 vs ES5SymbolProperty1).
Batch BK (+11 TP, TP 2289 / MISS 445) mixed scoping, parser-recovery,
and call-modeling slices:
- Block scoping in the TS2304 hoisting backstop: a `let` / `const`
  for-of/for-in head is LOOP-scoped (only `var` heads hoist —
  for-of7), and an assign-form loop's body contributes only `var`s
  (`for (v of xs) { let v; }` cannot declare the head — for-of6).
  Closures inside the loop still see the head binding via the env walk.
- `new Date<A;`: type arguments are only consumed when a balanced `>`
  exists; otherwise the cursor restores and `<` parses as a comparison,
  so `A` surfaces through the normal undefined-name path
  (parserConstructorAmbiguity1/2/4).
- TS2345: `f.apply(x, arguments)` where `f` is a zero-parameter
  function — `IArguments` is never assignable to the empty tuple `[]`
  (asyncArrowFunctionCapturesArguments_es5/es6/es2017). Functions WITH
  parameters abstain.
- TS1005: reserved-word and literal object-binding shorthands need a
  `: alias` (`var { while } = …`, `var { "while" } = …` —
  objectBindingPatternKeywordIdentifiers01/03), and `void` cannot head
  a qualified type name (`var v: void.x` — parservoidInQualifiedName1).
Batch BL (+7 TP, TP 2296 / MISS 438) worked the TS2339 cluster:
- Object patterns over PRIMITIVE for-of elements flag their props
  (`for (var {x: a = 0} of [2, 3])` — ES5For-of27/29; prototype members
  like `toString` stay legal), mirroring BJ's array-pattern TS2488.
- An object sub-pattern under a REST element draws its keys from the
  array surface: non-numeric keys outside `array_prototype_member` (+ a
  small always-legal extra set) flag on Array/Tuple sources, in both
  declaration and assignment forms (restElementWithBindingPattern2,
  restElementWithAssignmentPattern2/4).
- The pattern-vs-object-literal key check (parser AND checker copies)
  now folds spreads of syntactic object literals recursively instead of
  abstaining (`const { g } = { ...{ ...{ c: 0 } } , f: 0 }` —
  destructuringSpread); getter/setter entries provide their names.
- `new SharedArrayBuffer(...)` keeps its Named type, the instance table
  gained the ES2024 members (`growable` / `maxByteLength` / `grow`, and
  ArrayBuffer's `resizable` / `detached` / `resize`), and the surface
  registers as fully modeled so member misses are definite
  (`sab.length` — useSharedArrayBuffer6).
Batch BM (+9 TP, TP 2305 / MISS 429) took lib-set directives,
decorator signatures, and generator interface returns:
- TS2318 via parser markers: `@noLib: true` removes every required
  global type (parser509698); an explicit `@lib:` list without a
  full-year ES2015+ lib / `es2015.iterable` lacks `IterableIterator`
  for generators (generatorReturnTypeFallback.2, types.forAwait); one
  without `esnext` lacks `Disposable` for `using` declarations
  (usingDeclarations.9 / awaitUsingDeclarations.9 — the block-scoped
  `using` lowering records the marker too).
- TS1238 (`check_class_decorator_signatures`): a CLASS used as a class
  decorator is not callable (constructableDecoratorOnClass01); a
  decorator or factory result whose REQUIRED arity exceeds the runtime
  invocation (1 arg legacy / 2 standard, `<experimental-decorators>`
  marker) can never resolve (decoratorOnClass8, esDecorators-arguments).
  Zero-parameter decorators also error in tsc but are deliberately
  skipped. The parser now captures class decorators BEFORE the body
  parse — member decorators share `pending_decorators` and previously
  either leaked onto the next declaration or (after the first fix)
  masqueraded as class decorators (decoratorOnClassAccessor1 FP'd, and
  the base-less IIFE route plus `parse_class_stub` never attached them
  at all).
- TS2741 (`check_generator_interface_returns`): a generator whose
  declared return type is an interface extending
  Iterator/IterableIterator/Generator with extra REQUIRED members can
  never satisfy it (generatorTypeCheck7); optional extras abstain.
Batch BN (+6 TP, TP 2311 / MISS 423) took index keys and lib-era
signatures:
- TS7053: a string-literal key indexing a fully-literal-keyed object
  shape that provably lacks it, gated on the module's `noImplicitAny`
  (threaded through a new `Resolver.no_implicit_any` flag). Numeric
  keys fold (`0b11010:` provides `26`), and since OUR lexer folds
  OVERFLOWING binary/octal literals through a 32-bit wrap while tsc
  folds to `Infinity`/exponent form, fold-shaped queries abstain when
  any >9-digit folded key exists — `"0b11010"` contains `b` (never a
  fold) and stays decidable (binaryIntegerLiteral/ES6,
  octalIntegerLiteral/ES6).
- TS2464: `Symbol.keyFor` is a FUNCTION on SymbolConstructor, never a
  computed property key (symbolProperty59; `Symbol.for` lexes as a
  keyword and can't reach the match arm).
- TS2554: `Date.UTC(year)` requires the month argument before es2015 —
  fires only under the `<lib-lacks-iterable>` (pre-ES2015 lib) marker
  (es5DateAPIs).
Deferred: genericRestArity/Strict need tuple-arity inference from the
handler parameter (`call<TS extends unknown[]>(handler: (...args: TS)
=> void, ...args: TS)` — expected count = 1 + handler params), which
requires threading callee type-params into the arity checker.
Batch BO (+12 TP, TP 2323 / MISS 411) continued the small clusters:
- TS2491: the left side of `for...in` is never a destructuring pattern,
  declaration or assignment form (for-inStatementsDestructuring/2/3/4,
  parserForInStatement8 — always-error, `record_unfiltered`).
- TS2854: a TOP-LEVEL `await using` requires target >= es2017 — new
  `<top-level-await-using>` and `<target-below-es2017>` parser markers
  (multi-target conformance directives list pre-es2017 variants —
  awaitUsingDeclarations.1; .2/.3 parse through other shapes and stay
  misses).
- TS2550: `Object.values` / `Object.entries` need the es2017 lib
  surface, `Atomics.waitAsync` needs es2024 — `<lib-lacks-es2017>` /
  `<lib-lacks-es2024>` markers (explicit `@lib:` lacking the year, or
  no `@lib:` with an explicit sub-es2017 `@target:`), threaded through
  new `Resolver.lib_lacks_es2017/es2024` flags to the MethodCall carve
  (useObjectValuesAndEntries2/3, es2024SharedMemory).
- TS2503: an entity-reference import alias (`import X = A.B`) whose
  ROOT is provably undeclared — `<import-eq-root>` marker, resolved
  with the same contract as `<export-eq>` (parserImportDeclaration1,
  scannerImportDeclaration1).
- TS1003-adjacent: a primitive-type keyword can never be a qualified
  type-name segment (`var v: x.void` — parservoidInQualifiedName2).
Batch BP (+6 TP, TP 2329 / MISS 405) took TS2322 subclusters and
primitive spreads:
- `SharedArrayBuffer` and `ArrayBuffer` are nominally distinct lib
  types: `var foo: ArrayBuffer = new SharedArrayBuffer(...)` flags when
  neither name has a user declaration
  (assignSharedArrayBufferToArrayBuffer).
- `new Array<T>(n)` keeps the explicit element type (`Array(T)`), so a
  mismatched declared annotation flags (parserObjectCreation1).
- TS2698: an object-literal spread of a provably non-object primitive
  (string / numeric / template-literal-typed operand) — named /
  generic / union operands abstain (spreadNonObject1,
  spreadTypeVariable as a bonus flip).
- A provably NUMERIC computed key in an object literal checks its
  value against the target interface's number index signature
  (`var o: I = { [+"foo"]: "" }` where `[s: number]: boolean` —
  computedPropertyNamesContextualType10_ES5/ES6).
Batch BQ (+6 TP, TP 2335 / MISS 399) took the TS7057 generator cluster
and the deferred genericRestArity tuple arity:
- TS7057: in a generator lacking a return-type annotation (under
  noImplicitAny), a `yield` whose RESULT is consumed with no contextual
  type — three syntactically decidable shapes: unannotated Ident
  binding (`const value = yield`), a generic call argument whose
  matching parameter is a bare type param with no explicit type args
  (`f(yield)`), and `yield yield`. Unused results, annotated bindings,
  destructuring targets, and `f<string>(yield)` abstain
  (generatorImplicitAny, generatorTypeCheck50,
  generatorReturnTypeInference + NonStrict).
- TS2554 generic-rest-tuple arity: `call<TS extends unknown[]>(handler:
  (...args: TS) => void, ...args: TS)` needs exactly 1 + handler-param
  count arguments. The parser substitutes the tuple param with its
  bound, so the carve keys on the substituted single-type-param shape
  (`(...args: unknown[]/any[]) => R` + same-bound rest) with a
  syntactic all-required arrow handler (genericRestArity,
  genericRestArityStrict). A non-generic `unknown[]`-rest signature
  abstains.
Documented dead ends from this round: YieldExpression10_es6 (an
object-literal method's name in the backstop is indistinguishable from
a legal self-referential named function expression property);
symbolProperty3/59 (need the `Symbol` VALUE modeled as
`SymbolConstructor`); computedPropertyNames9 (needs overload+generic
call inference to pick `boolean`); the TS2403 identity cluster
(spreadUnion2 / typeOfThisGeneral etc. need inferred-initializer
identity; unionTypeEquivalence needs non-reducing union identity over
subtype-related classes).
Remaining TS7-only clusters (documented, unattempted): nested
class-expression computed keys (the parser lowers class expressions to
IIFEs, erasing the member structure), TS2339 Corsa behavior changes. (Final TS6 state for reference: TP 2669 /
FP 0 / TN 1414 / MISS 414 — the TS7 renumbering reflects dropped es5
variants and Corsa behavior changes, not checker regressions; the
582 misses include ~170 new TS7-only opportunities.)

The switch surfaced and fixed four latent checker bugs that es5-variant
errors had masked (batch BD): lib-global redeclarations are never
TS2454-unassigned; parameter-property assigns follow a `super()` buried
in the using-lowering's try/finally; spreads provide properties under
getters (`@@get:` names); an EXPLICIT `: any` parameter annotation is
never TS7006 (tracked via the parser's `written_any_params` set —
`TsParam.type_` alone cannot distinguish it).

PFLEGAL budget is 3: parser768531 (fuzz), decoratorOnClass3 and
defaultExportWithOverloads01 (both TS7-accepted forms our parser
rejects — parser follow-ups).

State: whole-corpus **TP 2669 / FP 0 / PFLEGAL 1 / TN 1414** against the
TypeScript conformance baselines (`.errors.txt` = ground truth). Standing CI
gate: `scripts/checker_conformance_oracle.sh --max-fp 0
--max-legal-parsefail 1`. Session arc TP 1761 -> 2631 across PRs #191-#200.
2473 unit tests. Parse failures with an error baseline count as TP ("via
parse rejection", 397); the one budgeted legal parse failure is
parser768531 (regex/division ambiguity needs parser-fed lexer context).

### Design constraints / known dead ends (re-attempt only with design work)

- The parser ERASES constrained type params to their bounds
  (`TS extends unknown[]` -> `Array(Unknown)`) in signature positions,
  making generic and non-generic spellings indistinguishable at check time
  (genericRestArity's variadic-handler shape). Un-erasing would also unlock
  constraint-carrying inference (wrappedAndRecursiveConstraints4).
- `moon check --deny-warn` fails on ~226 PRE-EXISTING deprecated-API
  warnings from toolchain drift; `moon test --target native` is the gate.
- The `do-while` checker arm deliberately leaks body rebinds past the loop;
  back-edge widening is `while`-only for that reason.
- `block_has_value_return` counts `return undefined` as a value return —
  correct for its arrow-void consumer; generator-TReturn checks use the
  separate `generator_body_returns_value`.
- The permissive filter suppresses bare arity messages unless
  `arity_reliable` / `record_unfiltered`; new diagnostics should reuse the
  "expected `X` but got `Y`" family (reliability-classified) where possible.
- Top-level `a = b;` parses as `Expr(AssignExpr(...))`, NOT stmt-level
  `Assign` — assignment rules must be wired into BOTH arms.

### Next tasks (in order)

1. [x] symbolProperty9/10/12 — DONE (batch BC): well-known-symbol
   computed keys (`[Symbol.X]`) now parse as stable `@@X` member names in
   classes AND interfaces (types were already retained; only the name was
   erased), shorthand type members (`{ x; y }`) parse as `any`-typed named
   members instead of collapsing the annotation, and a dedicated
   `symbol_member_shape_blocks` rule compares `@@`-member OBJECT shapes
   (annotation-vs-annotation, so `any`-valued keys stay REQUIRED — the
   general member compare tolerates missing `any` fields as an
   unmodeled-inference guard and can't decide these). symbolProperty46
   (accessor: setter param inferred from paired getter return, then
   symbol-keyed INDEX-assignment lookup) remains — needs accessor pairing
   machinery.
2. [x] Object member hiding — DONE (batch BC): (a) a source member
   hiding an `Object.prototype` member with an incompatible signature
   (checked via the object_prototype_member table) blocks assignment to
   the lib `Object`; (b) bare `Object` never satisfies a callable /
   constructable target. Module-declared `Object` shadows abstain
   (pinned). All three fixtures match tsc's per-line counts.
3. [x] generatorTypeCheck31 — DONE (batch BC): an unannotated
   `function*` expression now infers its return as
   `Generator<any, any, any>` (calling a generator produces the
   generator OBJECT, not its return value), and a new rule (1b) flags a
   `Generator` / `IterableIterator` / `AsyncGenerator` source against a
   function-typed target (no call signatures). Abstains when the fixture
   declares its own `Generator` interface. Pinned legal: `.next()` on
   the synthesized return, generator IIFEs into `Iterable` slots and
   `for..of` heads. TP 2642 -> 2643, FP 0.
4. [x] mapped types with `as` clauses — DONE (batch BC), three slices:
   (a) `resolver_eval_mapped_remap` concretely evaluates a remapped
   mapped type whose source enumerates to literal keys (`keyof M` over
   an interface): per key, the remap conditional decides via
   `extends_decision`, `T[K]` resolves through `lookup_field` (NOT
   `unwrap` — `simplify_indexed_access` degrades a `Named`-based access
   to `any`, which would make every filter trivially true), `never`
   filters, literals rewrite. Wired into `unwrap`'s mapped arm; bails
   for alias-named sources (recursion guard —
   mappedTypeAsClauseRecursiveNoCrash1 stays crash-free). Unlocks
   mappedTypeAsClauses (`KeysExtendedBy<M, number>` -> `"b"`).
   (b) Rule (1c): bare `val: T` into a remapped mapped type over
   `keyof T` — pure filters (`cond ? P : never`, no `-?`) are legal,
   key RENAMES flag even under `+?`, `-?` flags always
   (mappedTypeAsClauseRelationships, all 4 sites).
   (c) Rule (1d): reading `obj[key]` through a RENAMING remap with a
   non-materializable source (type param, possibly bound-erased to
   `string`/template) can't be correlated to a checkable target
   (mappedTypeConstraints2, 4 of 5 sites; the 5th has an `any`-typed
   expected slot and abstains). Filter remaps abstain (f5/f7/validate).
   TP 2643 -> 2646, FP 0.
5. [x] Lib surface models — DONE (batch BC): the `Error` / `Date`
   prototype tables already existed in `lookup_field_core`; the gap was
   that both member-miss flag sites suppress unresolved `Named`
   receivers. Added `lib_member_surface_complete` (bare `Error` / `Date`
   only, abstaining when a module-declared interface/class merges or
   shadows) and carves at the PropAccess and MethodCall miss sites, plus
   `cause` in the Error table (lib.es2022). Unlocks
   narrowFromAnyWithInstanceof (TS2551 typo members via
   `instanceof`-narrowed `any`) and
   propertyAccessOnTypeParameterWithConstraints4. Note: NO current miss
   depends on primitive METHOD-CALL existence (checked the corpus), so
   the String/Number method-call half was dropped — the tables stay
   incomplete (deprecated HTML methods like `"x".anchor()` are legal
   tsc) and flagging there would be FP-prone for zero recall.
   TP 2646 -> 2648, FP 0.
6. [x] TS2411 computed-property cluster — DONE (batch BC):
   (a) parser: constant computed class keys fold to their literal name
   (`["get1"]` -> get1, `[""]` -> "", `[1 << 6]` -> 64 via a small
   const-int evaluator) instead of `<computed>`; TS18006 exempts the
   computed `["constructor"]` form via `computed_field_keys` (tsc-legal).
   (b) checker: `check_index_props` gained a `symbol` index-signature
   arm constraining `@@X` members (symbolProperty17/32);
   `violates_index_value` gained a bivariant Func-vs-Func arm and a
   Named-class arm that flags only a MISSING required value member
   (`any`-typed members count as required; `?`-optional ones don't —
   `is_structurally_assignable_named` can't disprove, it tolerates
   missing `any` members by design). (c) the class TS2411 walk now
   models accessors (getter return inferred from the body, setter param
   type), infers unannotated method returns, and walks base chains both
   ways: inherited sigs constrain own members (43/44), own sigs
   constrain inherited members (45, symbolProperty32); inherited
   members are NOT re-checked against inherited sigs (no duplicates).
   Unlocks computedPropertyNames36/38/39/40/42/43/44/45_ES6 +
   symbolProperty17/32. TP 2648 -> 2658, FP 0.
7. [~] Edge buckets — `using` declarations DONE (batch BC): TS1492
   ('using' declarations may not have binding patterns) recorded as
   grammar misuses at three parse sites — parse_var_like (labelled
   `using_kw` param), the block-level using lowering (later declarators
   of a multi-declarator `using` land inside the init COMMA CHAIN as
   `AssignPattern` operands — scanned recursively), and the for-of head.
   TS2850/2851 (initializer must be disposable) decided only for the
   provable slice: an UNANNOTATED object-literal initializer whose keys
   are all plain (no `@@`-symbol / computed / spread entries), which
   definitely lacks `[Symbol.dispose]()`. Annotated declarations
   (`using d: T = {...}`) abstain — tsc checks the literal against `T`
   instead. Unlocks usingDeclarations.5/.7/.14,
   awaitUsingDeclarations.5/.7/.12, and both InForOf.3 files.
   TP 2658 -> 2666, FP 0.
   Also DONE from the TS1005 bucket: invalid radix digits — the lexer
   counts a binary / octal literal running into an out-of-radix decimal
   digit (`0b1102110`, `0o13334823`) and the parser surfaces one grammar
   misuse per literal (binaryIntegerLiteralError,
   octalIntegerLiteralError, invalidBinaryIntegerLiteralAndOctal-
   IntegerLiteral). TP 2666 -> 2669, FP 0.
   Remaining (documented, not attempted): the rest of the TS1005
   parser-recovery baselines (heterogeneous, require reproducing tsc's
   error-recovery token stream — e.g. `var x = /fo(o/;` regex re-scan),
   the IteratorObject `using` fixtures (need lib-level
   `Iterator.prototype[Symbol.dispose]` type modeling), and NOBASE
   variant-baseline files (oracle artifacts, not checker gaps).
