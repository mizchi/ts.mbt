# typescript.mbt

TypeScript/JavaScript interpreter and compiler to WebAssembly, written in MoonBit.

## Current Goals

This project currently focuses on these three goals:

1. Implement a TypeScript parser in MoonBit.
2. Make TypeScript-to-MoonBit bridge types safe, mainly for `vite-plugin-moonbit`.
3. Improve the TypeScript types emitted for MoonBit-generated code.

These are the primary goals right now.

- The parser / resolver / semantics / declaration tooling are first-class project areas.
- Bridge generation and `.d.ts` normalization are part of the main product surface.
- WebAssembly/codegen work still exists, but it is not the main goal unless explicitly stated.

## Purpose Notes

- `src/parser` is the foundation for parsing TypeScript/JavaScript and resolving module structure.
- `src/analysis` contains the bridge-generation, declaration normalization, and shape-checking logic used to make TS-facing output safer and easier to consume.
- `src/checker` is currently a narrow checker for declaration normalization support, not a full TypeScript checker.

## Project Structure

```
typescript.mbt/
├── moon.mod.json      # Module configuration
└── src/
    ├── moon.pkg.json  # Package configuration
    ├── lexer.mbt      # Tokenizer
    ├── parser.mbt     # Parser
    ├── types.mbt      # AST type definitions
    ├── interpreter.mbt # JS interpreter
    ├── jsvalue.mbt    # JSValue runtime types
    ├── codegen.mbt    # Wasm code generation
    ├── main.mbt       # CLI entry point
    ├── test262_assert.mbt  # test262 harness (assert)
    ├── test262_sta.mbt     # test262 harness (sta.js)
    └── *_wbtest.mbt   # Tests
```

## Dependencies

- `mizchi/wasmx` - WebAssembly runtime
- `moonbitlang/async` - Async file I/O

## Commands

```bash
# Check for errors
moon check --deny-warn

# Run tests
moon test --target native

# Format code
moon fmt

# Generate type definitions
moon info
```

## Test262 Support

This project includes test262 harness implementation:
- `assert.sameValue(actual, expected, message?)` - SameValue comparison
- `assert.notSameValue(actual, unexpected, message?)` - Not SameValue
- `assert(condition, message?)` - Basic assertion
- `print(...)` - Console output
- `$DONOTEVALUATE()` - Test marker

## Notes

- Target: `native` (not wasm-gc)
- The interpreter supports a subset of JavaScript/TypeScript
- `typeof` operator is not yet implemented in the parser
