# typescript.mbt

Status: Experimental

A bridge-generation toolchain between TypeScript and MoonBit, written in
MoonBit. It reads TypeScript declaration files and MoonBit `pkg.generated.mbti`
interfaces, then emits the corresponding bridge package for the other side so
that MoonBit code can call typed JavaScript libraries and JavaScript / TypeScript
code can call build-backed MoonBit packages.

The earlier JS interpreter / wasm codegen / AOT compiler lived in this repo
during exploration but has been removed. The supported surface is now the
bridge generator only.

## Supported directions

- **TypeScript -> MoonBit**: read a `.d.ts` (or `.ts`) entry plus a runtime
  module specifier and emit a MoonBit bridge package (`bridge.mbti`,
  `bridge.mbt`, `bridge.js`, `moon.pkg.json`, plus split source files for
  larger packages).
- **MoonBit -> TypeScript**: read a `pkg.generated.mbti` interface (and its
  recursively discovered child packages) and emit a TypeScript declaration
  package backed by `moon build --target js`.

Generated packages are deterministic and diff-friendly. Each side writes a
diagnostics file (`SCAFFOLD_DIAGNOSTICS.md` or `AUTOLINK_DIAGNOSTICS.md`) so
widened, omitted, or wrapped surfaces stay inspectable.

## Prerequisites

- [MoonBit toolchain](https://www.moonbitlang.com/) (`moon` on `$PATH`).
- Node.js 20+ (the verification harness imports built JS through Node).
- `pnpm` (used by `just verify-mbti-dts` to run `tsc`).
- Optional: [`just`](https://github.com/casey/just) for the `just verify-*`
  recipes; otherwise invoke the corresponding `bash scripts/*.sh` directly.

Quick start after `git clone`:

```bash
moon update                            # fetch deps
moon check --deny-warn                 # build the library + cmd binaries
moon run src/cmd/ts2mbt -- --help      # TS -> MoonBit
moon run src/cmd/mbt2ts -- --help      # MoonBit -> TS
```

## Two CLIs

Bridge generation is split into two binaries, one per direction:

- `mbt2ts` — MoonBit `pkg.generated.mbti` → TypeScript declaration package
  (build-backed by `moon build --target js`).
- `ts2mbt` — TypeScript `.d.ts` / `.ts` entrypoint → MoonBit bridge package
  (`bridge.mbti`, `bridge.mbt`, `bridge.js`, `moon.pkg.json`).

Each CLI exposes a high-level `--input ... --out ...` "do everything" flow
plus low-level subcommands.

```bash
# MoonBit -> TypeScript. Run `moon info` first so pkg.generated.mbti exists.
# This creates temporary MoonBit glue code, runs `moon build --target js`,
# and emits a TypeScript package backed by the built JS output.
moon run src/cmd/mbt2ts -- --input mizchi/foo --out dist

# TypeScript -> MoonBit. For bare npm-style inputs, the runtime module spec
# defaults to the input specifier.
moon run src/cmd/ts2mbt -- --input neverthrow --out dist

# File input also works; pass the runtime module when it differs from the
# declaration entry path.
moon run src/cmd/ts2mbt -- --input path/to/entry.d.ts --module-spec /runtime/module.js --out dist

# Diagnostics can be redirected. Strict mode fails when unsupported exports,
# omitted MoonBit autolink members, or unbudgeted TS JSValue fallbacks are found.
moon run src/cmd/ts2mbt -- --input neverthrow --out dist --diagnostics dist/diagnostics.md --strict
```

The MoonBit -> TypeScript unified path emits facade glue by default, builds
it with `moon build --target js`, and copies the built JS to `index.js`;
pass `--no-facade` to emit only top-level free-function glue.

Shared `--input` flow flags:

- `--input <pkg-or-entry>` — for `mbt2ts` accepts a MoonBit package name or
  `pkg.generated.mbti` path; for `ts2mbt` accepts a TypeScript declaration /
  source entrypoint or an installed package specifier.
- `--out <dir>` — writes a complete scaffold package.
- `--module-spec <specifier>` (`ts2mbt` only) — overrides the runtime import
  used by generated bridge code.
- `--import-rewrites <json>` (`mbt2ts` only) — JSON map of MoonBit-package
  imports to publishable TypeScript specifiers.
- `--diagnostics <path>` — redirects the generated diagnostics report.
  Without it, `ts2mbt` writes `SCAFFOLD_DIAGNOSTICS.md` and `mbt2ts` writes
  `AUTOLINK_DIAGNOSTICS.md` in the output directory.
- `--strict` — fails when diagnostics contain unsupported exports, omitted
  autolink members, or unbudgeted `JSValue` fallbacks. The default
  non-strict mode still emits a buildable scaffold with diagnostics when
  possible.
- `--no-facade` (`mbt2ts` only) — skip facade-wrapper generation and emit
  only top-level free-function glue.

## Vendor & sync (TypeScript -> MoonBit)

When you're consuming a MoonBit package and want bridges for the
TypeScript libraries listed in your `package.json`, run `ts2mbt vendor`
or `ts2mbt sync` from inside your moon module.

```bash
# Vendor one npm package: resolve its types via node_modules and write a
# bridge sub-package under <moon-source>/internal/generated/<safe>/.
moon run src/cmd/ts2mbt -- vendor hono

# Vendor everything in dependencies + devDependencies of ./package.json.
moon run src/cmd/ts2mbt -- sync
```

Output layout (with `moon.mod.json`'s `source` set to `src`):

```
src/
└── internal/
    └── generated/
        ├── hono/
        │   ├── bridge.mbti
        │   ├── bridge.mbt
        │   ├── bridge.js
        │   ├── moon.pkg.json
        │   └── SCAFFOLD_DIAGNOSTICS.md
        └── types__react/
            └── ... (same shape, runtime spec defaults to `react`)
```

Naming: the directory slug strips the leading `@`, replaces `/` with
`__`, and replaces other non-`[A-Za-z0-9]` characters with `_`.
`@types/<name>` packages default the runtime module spec to the unscoped
name (`react`, `express`, ...), since the runtime code lives in the
non-types package.

Flags:

- `--module-spec <spec>` (`vendor`) — override the runtime import used by
  the generated `bridge.js`. Useful when the package ships its types
  separately from its runtime entry.
- `--out <dir>` — override the vendor root. Defaults to
  `<moon source>/internal/generated`.
- `--package-json <path>` (`sync`) — read deps from a non-default
  `package.json`.

## MoonBit -> TypeScript

Start from a root `pkg.generated.mbti` for a real MoonBit source package and
emit:

- `index.js` copied from the temporary glue package's `moon build --target js`
  output
- child package `index.js` files that re-export their runtime surface from the
  built root JS
- `package.json` with `types` / `exports` metadata for the emitted
  declaration package
- `AUTOLINK_DIAGNOSTICS.md` listing public methods / constructors omitted from
  `link.js.exports`
- recursive `.d.ts` files with local MoonBit package imports rewritten to
  sibling relative imports

The temporary glue package contains generated wrapper functions and
`link.js.exports`, is built with `moon build --target js`, and is removed
after the built JS is copied to `index.js`.

```bash
moon run src/cmd/mbt2ts -- scaffold src/pkg.generated.mbti out/ts-pkg

# optional: rewrite external MoonBit package imports to publishable TS specifiers
moon run src/cmd/mbt2ts -- scaffold src/pkg.generated.mbti out/ts-pkg import-rewrites.json

# opt-in: also emit top-level MoonBit wrappers for omitted local methods/constructors
moon run src/cmd/mbt2ts -- facade-scaffold src/pkg.generated.mbti out/ts-pkg
```

Lower-level commands are also available:

```bash
# only link.js.exports JSON
moon run src/cmd/mbt2ts -- link-config src/pkg.generated.mbti

# only recursive .d.ts package
moon run src/cmd/mbt2ts -- package src/pkg.generated.mbti out/ts-pkg

# single .d.ts from one .mbti file without recursive rewrite
moon run src/cmd/mbt2ts -- decl src/pkg.generated.mbti
```

Current export model:

- JS autolink is generated from top-level public free functions across the
  root package and recursively discovered local child packages.
- Runtime-inaccessible method / namespace declarations are stripped from
  scaffold `.d.ts` output unless wrapper glue is generated for them.
- Scaffold output includes `AUTOLINK_DIAGNOSTICS.md` so omitted public members
  are explicit.
- `mbt2ts facade-scaffold` is an opt-in variant that adds
  generated top-level wrappers for local non-generic methods and constructors
  to the temporary glue package, then exposes those wrappers from the built
  JS and the matching package `.d.ts`. Async wrappers are exposed as
  Promise-returning JavaScript functions.
- Public MoonBit traits are declaration-only structural TypeScript interfaces.
  `pub impl Trait for Type` is represented by `extends Trait` / type
  intersections in `.d.ts` output, but trait methods are not generated as
  runtime bridge exports.
- Generated glue declarations, runtime export lists, package `exports`, and
  child-package re-export files are sorted deterministically to keep scaffold
  diffs reviewable.
- The temporary `moon.pkg.json` and wrapper `.mbt` files are build inputs
  only; they are not written to the final TypeScript package.
- Recursive `.mbti` resolution only rewrites imports that stay under the same
  root package prefix. External imports remain bare specifiers.
- `mbt2ts package` and `mbt2ts scaffold`
  accept an optional JSON object for external import rewrites, for example
  `{ "moonbitlang/core/debug": "demo-debug" }`.
- Generated `package.json` names are derived from the MoonBit package path,
  for example `demo/pkg` -> `@demo/pkg` and `mizchi/ts/analysis` ->
  `@mizchi/ts-analysis`.

Supported surface:

- Top-level public free functions whose parameter and return types can cross
  the MoonBit JS backend boundary.
- Root and nested local child-package exports, with generated `package.json`
  subpath exports.
- `raise` effects in `.mbti`, represented in TypeScript declarations as
  `Result<Return, ErrorType>`.
- Opaque MoonBit-defined types in TypeScript declarations.
- Declaration-only structural interfaces for public MoonBit traits and local
  trait impl relationships.
- Opt-in facade wrappers for local non-generic methods and constructors via
  `mbt2ts facade-scaffold`, including async constructors and methods.

Unsupported or limited surface:

- Generic methods, generic constructors, trait methods, and generic functions
  are not exported directly by JS autolink.
- Public members omitted from the runtime export surface are listed in
  `AUTOLINK_DIAGNOSTICS.md`.
- External MoonBit imports are left as bare TypeScript imports unless an
  import rewrite map is provided.
- The final package should not contain temporary glue files such as
  `moon.pkg.json` or generated facade `.mbt`; those are build inputs only.

## TypeScript -> MoonBit

Start from a TypeScript entrypoint and emit a MoonBit bridge scaffold:

```bash
moon run src/cmd/ts2mbt -- scaffold path/to/entry.d.ts /runtime/module.js out/moonbit-pkg
```

Lower-level commands are also available:

```bash
# full bridge package
moon run src/cmd/ts2mbt -- package path/to/entry.d.ts /runtime/module.js out/moonbit-pkg

# inspect generated decl/ffi/bridge snippets without writing a package
moon run src/cmd/ts2mbt -- bridge path/to/entry.d.ts /runtime/module.js
moon run src/cmd/ts2mbt -- ffi path/to/entry.d.ts /runtime/module.js
moon run src/cmd/ts2mbt -- decl path/to/entry.d.ts
```

The TS -> MoonBit path resolves exported surface recursively through local
package structure and package exports, but the generated MoonBit package
still targets the exported top-level surface rather than arbitrary internal
module state.

- Namespace exports are emitted as opaque getter-style bindings such as
  `get_shapes() -> Shapes`.
- Ambiguous re-exports no longer block scaffold generation. They are
  widened / omitted the same way as the lower-level emitters, and the scaffold
  writes `SCAFFOLD_DIAGNOSTICS.md` so the dropped surface is explicit.
- Literal unions such as `"solid" | "ghost"` and `true | false` are narrowed
  to `String` / `Bool` instead of being widened to `JSValue`.
- Generated bridge packages preserve camelCase top-level export names in
  their public MoonBit API, even when the internal JS extern binding is
  lowered to snake_case.

Supported surface:

- Exported functions, classes, interfaces, constants, default exports,
  package `exports`, `types` / `typings`, common subpath exports, `@types/*`
  fallbacks, and configured Node built-in declaration files.
- Primitive values, arrays, optionals, literal string / boolean unions,
  object option bags, and representable readonly fields.
- Common utility types including concrete `Pick` / `Omit` projections,
  `NonNullable`, direct-union `Exclude` / `Extract`, direct function
  `ReturnType` / `Parameters`, and `Record<K, V>` as named opaque JS object
  boundary types such as `StringRecordOfFoo`.
- Non-empty homogeneous rest tuples such as `[T, ...T[]]` are lowered to
  `Array[T]` for class properties, constructors, functions, and imports.
- Common real-world package shapes covered by the probe corpus, including
  function libraries, schema libraries, web libraries, callback-heavy Node
  APIs, Promise-heavy APIs, CJS-style packages, and Node built-ins.
- Generated packages are expected to pass `moon check --target js`,
  `moon test --target js`, `moon build --target js`, and a Node smoke run
  without editing generated glue.

Fallback and unsupported surface:

- Complex `any` / `unknown`, overloads, conditional / mapped types,
  function-valued callbacks, heterogeneous tuple edge cases, and
  namespace / value merge surfaces may be widened to `JSValue`.
- Ambiguous re-exports are intentionally not bound unsafely. The generated
  package remains buildable and reports the candidate source files.
- Unsupported exports are either absent or explicitly budgeted in
  verification; new unsupported surfaces should be minimized into fixtures
  before broadening the generator.

Package-specific practical coverage:

- Small Node built-ins (`node:path`, `node:os`, `node:url`,
  `node:querystring`, `node:buffer`) and the focused `node:crypto` surface
  are expected to generate with zero public `JSValue` fallback in the
  real-world probe corpus.
- Naturalization targets are packages where remaining fallback should keep
  shrinking because the useful API shape is finite or common: Hono,
  React Router, JOSE, Glob, `date-fns`, `magic-string`, `source-map`,
  `node:sqlite`, `node:fs`, `node:assert`, and `node:util`.
- Hono is the current example of that policy: the basic application route
  shape works directly from MoonBit as
  `app.hono_get("/", fn(c) { c.text("ok", None, None) })`, with route paths
  as `String`, handlers as `(Context) -> Response`, and common `Context`
  response helpers returning `Response`.
- Glob now exercises the same policy for function-valued constant exports.
  Natural function signatures such as `escape(pattern, options)` /
  `unescape` are emitted as direct MoonBit calls, and
  `hasMagic(pattern: string | string[], options: GlobOptions)` also gets a
  string-subset wrapper as
  `has_magic(pattern : String, options : GlobOptions) -> Bool`. The common
  single-pattern path no longer needs a manual `JSValue` argument or a
  getter-returned function call.
- Zod, Valibot, Preact, and broad Playwright event / callback surfaces are
  currently treated as buildable interop probes rather than fully ergonomic
  API surfaces. Their high-order schema, parser, JSX / component, and event
  callback APIs still rely on explicit `JSValue` budgets; this is a
  documented fallback policy, not a claim that those APIs are naturally
  typed in MoonBit yet.
- `just verify-realworld-typescript` appends a fallback policy table to
  `_build/realworld-typescript/METRICS.md`, and new corpus entries must be
  classified before their `JSValue` budget is accepted.

Supported subset examples:

```ts
// TypeScript -> MoonBit: supported declaration shapes
export interface User {
  readonly id: string;
  name?: string;
}

export type UserPatch = Partial<Pick<User, "name">>;
export declare function parseUser(input: string): User;
export declare function listUsers(): Promise<User[]>;
```

```moonbit
// MoonBit -> TypeScript: supported JS-exportable public surface
pub struct User {
  id : String
  name : String?
}

pub fn parse_user(input : String) -> User {
  { id: input, name: None }
}

pub async fn list_users() -> Array[User] {
  []
}
```

Keep unsupported surfaces inspectable. Callback-heavy TypeScript parameters
and generic MoonBit methods can remain in source packages, but the bridge
may widen or omit them and report the decision in diagnostics.

## Diagnostics and quality reports

- `SCAFFOLD_DIAGNOSTICS.md` explains each widened, omitted, or
  bridge-wrapped TypeScript export, including whether the generated decision
  is runtime-safe.
- `AUTOLINK_DIAGNOSTICS.md` explains MoonBit public members omitted from JS
  autolink output.
- `just bridge-quality` writes `_build/bridge-quality/REPORT.md` with
  fixture-backed metrics, unsupported export budgets, and `JSValue` cause
  breakdowns.
- `just verify-realworld-typescript` writes
  `_build/realworld-typescript/METRICS.md` with per-package `JSValue` budgets
  and generated-glue immutability checks.
- `just verify-realworld-moonbit` writes
  `_build/realworld-moonbit/REPORT.md` with per-package status and
  generated-package immutability checks.
- The project does not claim arbitrary npm or MoonBit package conversion.
  Treat a clean report plus diagnostics review as the supported workflow.

## Examples

See [`examples/`](./examples/) for runnable demos of both directions.

## Development

```bash
# Check for errors
moon check --deny-warn

# Run tests
moon test --target native

# Verify high-level scaffold commands end-to-end
just verify-scaffolds

# Fixture-backed bridge quality report
just bridge-quality

# Optional local real-world probes
just verify-realworld-typescript
just verify-realworld-moonbit

# Format code
moon fmt
```

Release checklist:

- Run `moon fmt`, `moon info`, `just check`, and `just test`.
- Run `just verify-scaffolds`, `just verify-mbti-dts`,
  `just verify-generated-fixtures`, and `just verify-examples`.
- Run or review `just bridge-quality`, `just verify-realworld-typescript`,
  and `just verify-realworld-moonbit` before claiming broader package
  coverage.
- Refresh generated docs / reports and confirm `TODO.md` reflects the current
  quality gate.
- Add a changelog entry covering CLI contract, bridge behavior changes,
  fallback budgets, and known unsupported surfaces.

## License

Apache-2.0
