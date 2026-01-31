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

## Wasm Codegen Scope

The Wasm codegen intentionally supports a strict subset and errors on
dynamic JS features. Uses wasm-gc for arrays and structs.

- **Statements**: `let`/`const`, assignments, `if`, `while`, `do-while`, `for`, `for-of`
  (arrays), `switch`, `break`/`continue`, `return`, block/expr statements
- **Expressions**: literals, variables, arithmetic/comparison/bitwise, string `+`,
  array access/length, struct field access, `new Array(size)`,
  `new <interface>` struct allocation, ternary, nullish coalescing (`??`)
- **wasm-gc**: GC arrays, GC structs, generator state machines

**Explicitly unsupported in codegen**:
- `throw`, `try`/`catch`/`finally`
- `typeof`, `void`, `delete`
- Object literals, closures (arrow/function expressions)
- Dynamic call expressions

## Development

```bash
# Check for errors
moon check --deny-warn

# Run tests
moon test --target native

# Format code
moon fmt

# Run test262 (requires test262 repo in ./test262)
moon run src -- test262 test262.allowlist.txt

# AOT compilation (wasm-gc)
just aot-check      # Check AOT compilability
just aot-compile    # Compile fixtures to wasm
just aot-test       # Run with wasmtime
```

## License

Apache-2.0
