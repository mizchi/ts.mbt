<!--
Draft for microsoft/TypeScript, "Bug report" template.
Fixture: ../cases/feedback/declareFieldReadInDerivedInitializer.ts
Duplicate search (2026-11-15): no existing report. The closest are #42319
(whose own "Expected behavior" lists this case as allowed) and its fix
#43194, which introduced the behaviour below.
-->

# Title

TS2729 when a field initializer reads an inherited property redeclared with `declare`

## 🔎 Search Terms

TS2729, used before its initialization, declare, useDefineForClassFields

## 🕗 Version & Regression Information

- This changed between versions 4.2.3 and 4.3.5 (#43194).
- It still reproduces in 6.0.3 and `7.1.0-dev.20261114.1`. From 6.0 the default target enables `useDefineForClassFields`, so it reproduces with no options set.

## ⏯ Playground Link

https://www.typescriptlang.org/play/?useDefineForClassFields=true&target=99&ts=6.0.3#code/MYGwhgzhAEBCkFNoG8BQ0PQEYC5oDsBXAWywQCdoBeaARgG5UBfVVUSGABXAEt9oEADwAuCfABMY8CEjSZo46tGEALHhAB0WetAD0u6AHkA0s1bso0AHJhy5APYB3BIqGiJUxCnSZxCduRIuHTQAD7QAEyM8oo0qupaOvoCdvaUACoAyhEA7BEAnHicDgAOFMIAntAA5FjV0OrQhDKKZABmaUg8wjB83TxgIDwAXmDCPPb4GmZskxD2IAgaIPYA5gAU+AiO1rYOzuLrAJQa4kdJBrSoQA

(The Playground does not derive `useDefineForClassFields` from the target, so the link enables it explicitly.)

## 💻 Code

```ts
class Base {
    b: number = 1;
}

class Plain extends Base {
    d = this.b; // OK
}

class Narrowed extends Base {
    declare b: 1 | 2;
    d = this.b; // error TS2729: Property 'b' is used before its initialization.
}

console.log(new Narrowed().d); // 1
```

## 🙁 Actual behavior

`this.b` in `Narrowed` reports TS2729.

## 🙂 Expected behavior

No error, as in `Plain`. Per the spec, the base class's fields are initialized inside `super()`, and the derived class's fields right after `super()` returns ([SuperCall evaluation](https://tc39.es/ecma262/#sec-super-keyword-runtime-semantics-evaluation)). `declare` emits nothing, so `b` is already initialized (`1`) when `d` is initialized. #42319 also lists this as expected: "`c` is allowed because of the `declare` modifier".

## Additional information about the issue

- #43194 removed the ancestor-class exemption under `useDefineForClassFields`, for the case where a redeclaration without an initializer (`b;`) overwrites the property with `undefined` ([DefineField](https://tc39.es/ecma262/#sec-definefield)). It also catches `declare` redeclarations, which emit nothing. The test it added covers only the case without `declare`.
- TS2612 suggests adding `declare` to such a redeclaration, and doing so produces this error.
- The same error occurs with `declare context: React.ContextType<…>`, as recommended by `@types/react`, when a field initializer reads `this.context`.
- Found while testing my own TypeScript compiler (https://github.com/mizchi/ts.mbt).
