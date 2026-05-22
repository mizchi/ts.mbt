# typescript.mbt

A bridge-generation toolchain between TypeScript and MoonBit, written in MoonBit.

## Current Goals

This project focuses on three goals:

1. Parse a usable subset of TypeScript declaration files in MoonBit.
2. Make TypeScript -> MoonBit bridge types safe and ergonomic, primarily for `vite-plugin-moonbit`.
3. Improve the TypeScript declarations emitted for MoonBit-generated code.

The wasm interpreter / codegen / AOT path that originally lived in this repo
has been removed. Bridge generation and `.d.ts` normalization are the only
product surfaces now.

## Purpose Notes

- `src/parser` is the foundation for parsing TypeScript / JavaScript and
  resolving module structure (npm `exports`, `typesVersions`, `node:*`,
  `@types/*`, etc.).
- `src/checker` is the TypeScript type-system layer: structural classification
  (`classify_optional_like_union`, `classify_transparent_intersection`),
  assignability (`is_assignable_to` and resolver / generic / bivariant /
  diagnostic variants), three-valued `extends_decision`, infer pattern matching,
  distributive conditional reduction, generic substitution, alias-name
  predicates, `simplify_type` / `simplify_union`, the standard TS utility-type
  table (`Exclude` / `Extract` / `NonNullable` / `Awaited` / `ReturnType` /
  `Parameters`), and module-level validation
  (`unresolved_type_references`, `check_module`).
- `src/bridge` consumes `src/checker` for every type-shape decision and runs
  `@checker.check_module` on the synthesized output as a sanity gate. It also
  keeps domain-specific specialization for Node FS / React / Hono / crypto /
  class-shape generation, plus `.mbti` -> `.d.ts` emission for MoonBit-generated
  packages.

## Project Structure

```
typescript.mbt/
├── moon.mod.json
└── src/
    ├── ast/                 # Shared AST types
    ├── parser/              # TypeScript / JavaScript parser + module resolver
    ├── checker/             # Declaration-level TS type system
    ├── bridge/              # Bridge code generation (both directions)
    ├── main.mbt             # `mizchi/ts` library: bridge entry helpers
    ├── unified_cli.mbt      # `--input ... --out ...` unified driver
    └── cmd/
        ├── ts2mbt/main.mbt  # CLI binary: TypeScript -> MoonBit
        └── mbt2ts/main.mbt  # CLI binary: MoonBit -> TypeScript
```

## Dependencies

- `moonbitlang/async` - async file I/O for the CLI.

## Commands

```bash
# Check for errors
moon check --deny-warn

# Run tests
moon test --target native

# Run parser microbenchmarks
moon bench --target native

# Format code
moon fmt

# Generate type definitions
moon info
```

## Notes

- Target: `native`.
- The repo no longer ships a JS interpreter or wasm codegen; entry-point
  parsing is read-only and produces declarations / bridge code only.
