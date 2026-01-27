# typescript.mbt

Experimental TypeScript/JavaScript subset parser, interpreter, and Wasm codegen.
The goal is to run as much of TypeScript (and test262) as possible, with a
fallback to the interpreter when codegen is too limited.

## Parser scope (current)

The parser accepts a JS/TS subset and produces a lowered AST.

- Declarations: `function`, `class` (lowered), `let`/`const`/`var` (with types).
- Statements: block, `if`, `while`, `do/while` (lowered to `while`), `for`,
  `for-of` (and `for-in` is parsed as `for-of`), `break`/`continue`,
  `return`, `throw`, `try`/`catch`/`finally`.
- Expressions: literals, variables, unary/binary/ternary, `new`, calls,
  property/index access, assignments (including compound assignments),
  arrow functions, function expressions, arrays/objects, `yield`.
- Types: `number`, `int`, `boolean`, `string`, `void`, `any`, `array`, named
  types, function types, and interface field lists.
- Class declarations are lowered into constructor/prototype assignments.
  Class expressions are currently parsed as a stub object literal.

Not supported (parse errors or explicit skips):

- ES module syntax (`import`/`export`), `with`, private fields.

## Interpreter scope (current)

The interpreter executes the AST directly and is the main path for test262.

- Control flow: `if`, `while`, `for`, `for-of` (arrays/strings only),
  `break`/`continue`, `return`, `throw`, `try`/`catch`/`finally`.
- Functions: declarations, expressions, arrows, closures, basic generators.
- Objects/arrays/strings: property/index access, assignment, deletion.
- `eval` (direct eval), `new`, `super` (limited), `__proto__`.

Built-ins (partial/minimal):

- `Object`, `Function`, `Boolean`, `Number`, `String`, `Array`, `Math`,
  `Date` (minimal), `RegExp` (minimal), `Reflect` (partial), `console.log`.
- test262 harness: `assert.*`, `$262.*`, `$DONE`, `$ERROR`, `$DONOTEVALUATE`.

## Wasm codegen scope (current)

The Wasm codegen intentionally supports a strict subset and errors on
dynamic JS features.

- Statements: `let`/`const`, assignments, `if`, `while`, `for`, `for-of`
  (arrays only), `break`/`continue`, `return`, block/expr statements.
- Expressions: literals, variables, basic arithmetic/comparison, string `+`,
  array access/length, struct-like field access (interfaces), `new Array(size)`
  and `new <interface>` struct allocation.

Explicitly unsupported in codegen:

- `throw`, `try`/`catch`/`finally`, `typeof`, `void`, `delete`, `yield`,
  comma operator, object literals, function/arrow expressions, dynamic call
  expressions, most bitwise/shift/pow on non-integers, and many JS runtime
  semantics that require dynamic dispatch.
