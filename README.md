# typescript.mbt

Status: Experimental

A TypeScript/JavaScript subset parser, interpreter, and Wasm codegen written in MoonBit.
The goal is to run as much of ECMAScript (via test262) as possible, with a
fallback to the interpreter when codegen is too limited.

## Parser Scope

The parser accepts a JS/TS subset and produces a lowered AST.

- **Declarations**: `function`, `class` (lowered), `let`/`const`/`var` (with types)
- **Statements**: block, `if`, `while`, `do/while` (lowered), `for`, `for-of`,
  `for-in` (parsed as `for-of`), `break`/`continue`, `return`, `throw`,
  `try`/`catch`/`finally`, `switch`
- **Expressions**: literals, variables, unary/binary/ternary, `new`, calls,
  property/index access, assignments, arrow functions, function expressions,
  arrays/objects, `yield`, `await`
- **Types**: `number`, `int`, `boolean`, `string`, `void`, `any`, `array`,
  named types, function types, interface field lists
- **Class**: lowered into constructor/prototype assignments

**Not supported** (parse errors or explicit skips):
- ES modules (`import`/`export`) - parsed but not fully executed
- `with` statement (deprecated)
- Private fields (`#field`)

## Interpreter Scope

The interpreter executes the AST directly and is the main path for test262.

- **Control flow**: `if`, `while`, `for`, `for-of` (arrays/strings/iterables),
  `break`/`continue`, `return`, `throw`, `try`/`catch`/`finally`, `switch`
- **Functions**: declarations, expressions, arrows, closures, generators,
  async functions, async generators
- **Objects/Arrays**: property access, assignment, deletion, spread
- **Special**: `eval` (direct), `new`, `super` (limited), `__proto__`

### Built-in Objects

| Object | Support Level |
|--------|---------------|
| Object | Good - keys, values, entries, assign, defineProperty, etc. |
| Array | Good - most methods including iteration |
| String | Good - most methods |
| Number | Good |
| Math | Good |
| Function | Partial - no dynamic Function() |
| Date | Minimal - basic operations |
| RegExp | Minimal - literal parsing incomplete |
| Promise | Partial - async/await works |
| Proxy | Partial - basic traps |
| Reflect | Partial |
| JSON | Good - parse, stringify |
| console | Good - log |

**test262 harness**: `assert.*`, `$262.*`, `$DONE`, `$ERROR`, `$DONOTEVALUATE`

## test262 Compatibility

See [TODO.md](./TODO.md) for detailed status.

### Pass Rate by Category (2026-02-01)

Pass Rate = Passed / (Passed + Failed), excluding skipped tests.
Tests related to `eval`, `Function` constructor, and `with` statement are excluded.

| Category | Passed | Failed | Skipped | Total | Pass Rate |
|----------|--------|--------|---------|-------|-----------|
| **Math** | 291 | 35 | 1 | 327 | **89.3%** |
| **language/statements** | 6,532 | 1,230 | 763 | 8,525 | **84.1%** |
| **language/expressions** | 5,983 | 1,701 | 2,653 | 10,337 | **77.8%** |
| **Boolean** | 38 | 13 | 0 | 51 | **74.5%** |
| **Number** | 249 | 84 | 2 | 335 | **74.8%** |
| **Promise** | 459 | 180 | 0 | 639 | **71.8%** |
| **String** | 796 | 412 | 7 | 1215 | **65.9%** |
| **Function** | 285 | 154 | 70 | 509 | **64.9%** |
| **Object** | 1671 | 1712 | 28 | 3411 | **49.4%** |
| **Date** | 269 | 310 | 15 | 594 | **46.5%** |

### Not Tested / Not Supported

- **Intl402** - Internationalization API
- **Temporal** - Temporal API
- **with statement** - Deprecated feature
- **Dynamic eval** - Advanced eval features
- **ES Modules** - Parser accepts but not executed

### Partial Support

- **TypedArray** - Int8Array, Uint8Array, Int16Array, Uint16Array, Int32Array, Uint32Array, Float32Array, Float64Array, BigInt64Array, BigUint64Array
- **BigInt** - Basic operations

## Experimental Wasm Codegen Scope

The experimental Wasm codegen intentionally supports a strict subset and errors on
dynamic JS features. It currently uses wasm-gc for arrays and structs.

- **Statements**: `let`/`const`, assignments, `if`, `while`, `do-while`, `for`, `for-of`
  (arrays), `switch`, `break`/`continue`, `return`, block/expr statements
- **Expressions**: literals, variables, arithmetic/comparison/bitwise, string `+`,
  array access/length, struct field access, `new Array(size)`,
  `new <interface>` struct allocation, ternary, nullish coalescing (`??`)
- **experimental wasm-gc**: GC arrays, GC structs, generator state machines

**Explicitly unsupported in codegen**:
- `throw`, `try`/`catch`/`finally`
- `typeof`, `void`, `delete`
- Object literals and function values that escape or require full closure conversion
- Arbitrary dynamic call expressions

## Package Bridge Scaffolds

This repo now supports both directions of package scaffold generation.
See [`examples/`](./examples/) for runnable demos of both directions.

### Unified CLI

For the common "generate everything for this package" path, use the unified
CLI. It accepts either a MoonBit package name / `pkg.generated.mbti` path or a
TypeScript entrypoint / installed package specifier.

```bash
# MoonBit -> TypeScript. Run `moon info` first so pkg.generated.mbti exists.
# This creates temporary MoonBit glue code, runs `moon build --target js`,
# and emits a TypeScript package backed by the built JS output.
tsmbt --input mizchi/foo --out dist

# TypeScript -> MoonBit. For bare npm-style inputs, the runtime module spec
# defaults to the input specifier.
tsmbt --input neverthrow --out dist --direction ts-to-mbt

# File input also works; pass the runtime module when it differs from the
# declaration entry path.
tsmbt --input path/to/entry.d.ts --module-spec /runtime/module.js --out dist --direction ts-to-mbt

# Diagnostics can be redirected. Strict mode fails when unsupported exports,
# omitted MoonBit autolink members, or unbudgeted TS JSValue fallbacks are found.
tsmbt --input neverthrow --out dist --direction ts-to-mbt --diagnostics dist/diagnostics.md --strict
```

`--direction auto` is the default. It resolves MoonBit package names by scanning
for matching `pkg.generated.mbti` files under the current project, and resolves
bare TypeScript inputs through the TypeScript package resolver. The MoonBit ->
TypeScript unified path emits facade glue by default, builds it with
`moon build --target js`, and copies the built JS to `index.js`; pass
`--no-facade` to emit only top-level free-function glue.

Unified CLI contract:

- `--input <pkg-or-entry>` accepts a MoonBit package name, `pkg.generated.mbti`
  path, TypeScript declaration/source entrypoint, or installed package specifier.
- `--out <dir>` writes a complete scaffold package.
- `--direction auto|mbt-to-ts|ts-to-mbt` defaults to `auto`.
- `--module-spec <specifier>` overrides the runtime import used by generated
  TypeScript -> MoonBit bridge code.
- `--diagnostics <path>` redirects the generated diagnostics report. Without it,
  TS -> MoonBit writes `SCAFFOLD_DIAGNOSTICS.md` and MoonBit -> TypeScript writes
  `AUTOLINK_DIAGNOSTICS.md` in the output directory.
- `--strict` fails the command when diagnostics contain unsupported exports,
  omitted autolink members, or unbudgeted `JSValue` fallbacks. The default
  non-strict mode still emits a buildable scaffold with diagnostics when
  possible.

### MoonBit -> TypeScript

Start from a root `pkg.generated.mbti` for a real MoonBit source package and
emit:

- `index.js` copied from the temporary glue package's `moon build --target js` output
- child package `index.js` files that re-export their runtime surface from the built root JS
- `package.json` with `types` / `exports` metadata for the emitted declaration package
- `AUTOLINK_DIAGNOSTICS.md` listing public methods/constructors omitted from `link.js.exports`
- recursive `.d.ts` files with local MoonBit package imports rewritten to sibling relative imports

The temporary glue package contains generated wrapper functions and
`link.js.exports`, is built with `moon build --target js`, and is removed after
the built JS is copied to `index.js`.

```bash
moon run src -- emit-typescript-scaffold-from-mbti src/pkg.generated.mbti out/ts-pkg

# optional: rewrite external MoonBit package imports to publishable TS specifiers
moon run src -- emit-typescript-scaffold-from-mbti src/pkg.generated.mbti out/ts-pkg import-rewrites.json

# opt-in: also emit top-level MoonBit wrappers for omitted local methods/constructors
moon run src -- emit-typescript-facade-scaffold-from-mbti src/pkg.generated.mbti out/ts-pkg
```

Lower-level commands are also available:

```bash
# only link.js.exports JSON
moon run src -- emit-js-link-config-from-mbti src/pkg.generated.mbti

# only recursive .d.ts package
moon run src -- emit-typescript-package-from-mbti src/pkg.generated.mbti out/ts-pkg

# single .d.ts from one .mbti file without recursive rewrite
moon run src -- emit-typescript-from-mbti src/pkg.generated.mbti
```

Current export model:

- JS autolink is generated from top-level public free functions across the root package and recursively discovered local child packages.
- Runtime-inaccessible method / namespace declarations are stripped from scaffold `.d.ts` output unless wrapper glue is generated for them.
- Scaffold output includes `AUTOLINK_DIAGNOSTICS.md` so omitted public members are explicit.
- `emit-typescript-facade-scaffold-from-mbti` is an opt-in variant that adds generated top-level wrappers for local non-generic methods and constructors to the temporary glue package, then exposes those wrappers from the built JS and the matching package `.d.ts`. Async wrappers are exposed as Promise-returning JavaScript functions.
- Public MoonBit traits are declaration-only structural TypeScript interfaces. `pub impl Trait for Type` is represented by `extends Trait` / type intersections in `.d.ts` output, but trait methods are not generated as runtime bridge exports.
- Generated glue declarations, runtime export lists, package `exports`, and child-package re-export files are sorted deterministically to keep scaffold diffs reviewable.
- The temporary `moon.pkg.json` and wrapper `.mbt` files are build inputs only; they are not written to the final TypeScript package.
- Recursive `.mbti` resolution only rewrites imports that stay under the same root package prefix. External imports remain bare specifiers.
- `emit-typescript-package-from-mbti` and `emit-typescript-scaffold-from-mbti` accept an optional JSON object for external import rewrites, for example `{ "moonbitlang/core/debug": "demo-debug" }`.
- Generated `package.json` names are derived from the MoonBit package path, for example `demo/pkg` -> `@demo/pkg` and `mizchi/ts/analysis` -> `@mizchi/ts-analysis`.

Supported surface:

- Top-level public free functions whose parameter and return types can cross the MoonBit JS backend boundary.
- Root and nested local child-package exports, with generated `package.json` subpath exports.
- `raise` effects in `.mbti`, represented in TypeScript declarations as `Result<Return, ErrorType>`.
- Opaque MoonBit-defined types in TypeScript declarations.
- Declaration-only structural interfaces for public MoonBit traits and local trait impl relationships.
- Opt-in facade wrappers for local non-generic methods and constructors via `emit-typescript-facade-scaffold-from-mbti`, including async constructors and methods.

Unsupported or limited surface:

- Generic methods, generic constructors, trait methods, and generic functions are not exported directly by JS autolink.
- Public members omitted from the runtime export surface are listed in `AUTOLINK_DIAGNOSTICS.md`.
- External MoonBit imports are left as bare TypeScript imports unless an import rewrite map is provided.
- The final package should not contain temporary glue files such as `moon.pkg.json` or generated facade `.mbt`; those are build inputs only.

### TypeScript -> MoonBit

Start from a TypeScript entrypoint and emit a MoonBit bridge scaffold:

```bash
moon run src -- emit-moonbit-scaffold-from-ts path/to/entry.d.ts /runtime/module.js out/moonbit-pkg
```

Lower-level commands are also available:

```bash
# full bridge package
moon run src -- emit-moonbit-bridge-package path/to/entry.d.ts /runtime/module.js out/moonbit-pkg

# inspect generated decl/ffi/bridge snippets without writing a package
moon run src -- emit-moonbit-bridge path/to/entry.d.ts /runtime/module.js
moon run src -- emit-moonbit-js-ffi path/to/entry.d.ts /runtime/module.js
moon run src -- emit-moonbit-decl path/to/entry.d.ts
```

The TS -> MoonBit path resolves exported surface recursively through local package structure and package exports, but the generated MoonBit package still targets the exported top-level surface rather than arbitrary internal module state.

- Namespace exports are emitted as opaque getter-style bindings such as `get_shapes() -> Shapes`.
- Ambiguous re-exports no longer block scaffold generation. They are widened/omitted the same way as the lower-level emitters, and the scaffold writes `SCAFFOLD_DIAGNOSTICS.md` so the dropped surface is explicit.
- Literal unions such as `"solid" | "ghost"` and `true | false` are narrowed to `String` / `Bool` instead of being widened to `JSValue`.
- Generated bridge packages preserve camelCase top-level export names in their public MoonBit API, even when the internal JS extern binding is lowered to snake_case.

Supported surface:

- Exported functions, classes, interfaces, constants, default exports, package `exports`, `types` / `typings`, common subpath exports, `@types/*` fallbacks, and configured Node built-in declaration files.
- Primitive values, arrays, optionals, literal string / boolean unions, object option bags, and representable readonly fields.
- Common utility types including concrete `Pick` / `Omit` projections, `NonNullable`, direct-union `Exclude` / `Extract`, direct function `ReturnType` / `Parameters`, and `Record<K, V>` as named opaque JS object boundary types such as `StringRecordOfFoo`.
- Non-empty homogeneous rest tuples such as `[T, ...T[]]` are lowered to `Array[T]` for class properties, constructors, functions, and imports.
- Common real-world package shapes covered by the probe corpus, including function libraries, schema libraries, web libraries, callback-heavy Node APIs, Promise-heavy APIs, CJS-style packages, and Node built-ins.
- Generated packages are expected to pass `moon check --target js`, `moon test --target js`, `moon build --target js`, and a Node smoke run without editing generated glue.

Fallback and unsupported surface:

- Complex `any` / `unknown`, overloads, conditional / mapped types, function-valued callbacks, heterogeneous tuple edge cases, and namespace/value merge surfaces may be widened to `JSValue`.
- Ambiguous re-exports are intentionally not bound unsafely. The generated package remains buildable and reports the candidate source files.
- Unsupported exports are either absent or explicitly budgeted in verification; new unsupported surfaces should be minimized into fixtures before broadening the generator.

Package-specific practical coverage:

- Small Node built-ins (`node:path`, `node:os`, `node:url`, `node:querystring`,
  `node:buffer`) and the focused `node:crypto` surface are expected to generate
  with zero public `JSValue` fallback in the real-world probe corpus.
- Hono supports the basic application route shape directly from MoonBit:
  `app.hono_get("/", fn(c) { c.text("ok", None, None) })`, with route paths as
  `String`, handlers as `(Context) -> Response`, and common `Context` response
  helpers returning `Response`.
- Zod, Valibot, and Preact are currently treated as buildable interop probes
  rather than fully ergonomic API surfaces. Their high-order schema, parser, JSX,
  and component generic APIs still rely on explicit `JSValue` budgets; this is a
  documented fallback policy, not a claim that those APIs are naturally typed in
  MoonBit yet.

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

Keep unsupported surfaces inspectable. Callback-heavy TypeScript parameters and
generic MoonBit methods can remain in source packages, but the bridge may widen
or omit them and report the decision in diagnostics.

Diagnostics and quality reports:

- `SCAFFOLD_DIAGNOSTICS.md` explains each widened, omitted, or bridge-wrapped TypeScript export, including whether the generated decision is runtime-safe.
- `AUTOLINK_DIAGNOSTICS.md` explains MoonBit public members omitted from JS autolink output.
- `just bridge-quality` writes `_build/bridge-quality/REPORT.md` with fixture-backed metrics, unsupported export budgets, and `JSValue` cause breakdowns.
- `just verify-realworld-typescript` writes `_build/realworld-typescript/METRICS.md` with per-package `JSValue` budgets and generated-glue immutability checks.
- `just verify-realworld-moonbit` writes `_build/realworld-moonbit/REPORT.md` with per-package status and generated-package immutability checks.
- The project does not claim arbitrary npm or MoonBit package conversion. Treat a clean report plus diagnostics review as the supported workflow.

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

# Run test262 (requires test262 repo in ./test262)
moon run src -- test262 test262.allowlist.txt

# Experimental AOT compilation (wasm-gc)
just experimental-aot-check      # Check AOT compilability
just experimental-aot-compile    # Compile fixtures to wasm
just experimental-aot-test       # Run with wasmtime
```

Release checklist:

- Run `moon fmt`, `moon info`, `just check`, and `just test`.
- Run `just verify-scaffolds`, `just verify-mbti-dts`, `just verify-generated-fixtures`, and `just verify-examples`.
- Run or review `just bridge-quality`, `just verify-realworld-typescript`, and `just verify-realworld-moonbit` before claiming broader package coverage.
- Refresh generated docs/reports and confirm `TODO.md` reflects the current quality gate.
- Add a changelog entry covering CLI contract, bridge behavior changes, fallback budgets, and known unsupported surfaces.

## License

Apache-2.0
