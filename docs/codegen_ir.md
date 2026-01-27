# Codegen Typed IR (mid-level) - Design Notes

This document records the intended direction for a mid-level Typed IR that is
AssemblyScript-like in spirit, but limited to a statically-typed subset of TS/JS.
Dynamic or ambiguous constructs should fall back to the interpreter.

## Goals

- Provide a typed, structured IR that can be lowered to Wasm without dynamic
  dispatch for most operations.
- Keep the IR simple enough to implement incrementally and debug easily.
- Allow partial compilation: compile what is statically typed; interpret the rest.

## Non-goals

- Full TypeScript type system (union/intersection, conditional types, etc.).
- Implicit JS coercions beyond well-defined, explicit rules.
- Runtime polymorphism (generics at runtime, dynamic dispatch on unknown types).

## IR Type System (proposed)

Value types:
- `i32` (boolean, int, pointer)
- `f64` (number)

Reference types:
- `string` (ptr)
- `array<T>` (ptr)
- `struct<Name>` (ptr)

Type set:
```
Type :=
  Int | Number | Boolean |
  String | Array(Type) |
  Struct(Name) |
  Void
```

Notes:
- `Boolean` maps to `i32` (0/1).
- `String`/`Array`/`Struct` map to `i32` pointers.
- No `any` in IR. If type is unknown, stay in interpreter.

## IR Nodes (sketch)

Expressions:
- Literals: int, number, bool, string, null
- Var, LocalGet/Set
- Unary/Binary ops (typed)
- Conditional (typed)
- Call (only to known typed functions or runtime intrinsics)
- Field access (struct) and index access (array)
- NewArray(size), NewStruct(name)

Statements:
- Let/Const (typed locals)
- Assign / CompoundAssign
- If / While / For / ForOf (arrays only)
- Return

## Lowering Rules

- Only lower when all types are known and supported.
- Disallow implicit JS coercions in IR. Coercion must be explicit before IR.
- Object literals are not lowered; use interpreter or future struct literals.
- Function/arrow expressions are not lowered (no closures in IR for now).
- `throw` / `try` / `catch` / `finally` stay in interpreter.

## Type Inference (minimal)

Required:
- Local variable type from initializer.
- Simple arithmetic propagation (Int vs Number).
- `String + String` is string concatenation.
- Array literal: element type from first element (or default to Number).
- Known builtins: map fixed return types (e.g. `Math.* -> Number`).

Required annotations:
- Function params and return types must be known (by annotation or signature).
- If unresolved, keep the function in interpreter.

## Runtime Intrinsics

Introduce explicit runtime calls for:
- String operations (concat, length, charAt, etc.).
- Array operations (length, push, index bounds, etc.).
- RegExp and other complex builtins (if/when supported).

These are explicit `call_runtime("name", ...)` nodes in IR, not implicit.

## Boundary with Interpreter

- Compiler decides per-function (or per-block) whether it can lower to IR.
- Mixed mode: interpreter can call compiled functions if signatures match.
- If a function uses unsupported constructs, treat it as interpreter-only.

## Hybrid / JIT Notes (memo)

- Scope-level eligibility is practical: decide per-function (or per-block)
  whether it is safe to lower to Typed IR.
- A JIT-style tiering model is possible:
  - Count executions and only JIT hot functions.
  - Cache compiled Wasm by signature to amortize compile cost.
- Performance caveat: Wasm JIT only helps if the runtime is JIT-capable
  (e.g., wasmtime/wasmer). An interpreter-only Wasm runtime will not speed up.
- Boundary costs matter: JSValue <-> typed value conversions can dominate
  small functions. JIT should target hot loops and larger bodies.

## Near-term Plan

1) Define a typed IR data model.
2) Add a small type inference pass for locals and expressions.
3) Lower a limited subset (arithmetic, control flow, array/struct access).
4) Expand runtime intrinsics as needed for strings/arrays.
