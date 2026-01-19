# typescript.mbt

TypeScript/JavaScript interpreter and compiler to WebAssembly, written in MoonBit.

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

- `moonbitlang/wasm5` - WebAssembly runtime (local path: `../wasm5`)
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
