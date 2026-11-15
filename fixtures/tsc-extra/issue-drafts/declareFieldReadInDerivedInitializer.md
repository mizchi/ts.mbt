<!--
Draft for microsoft/TypeScript, "Bug report" template.
Fixture: ../cases/feedback/declareFieldReadInDerivedInitializer.ts
Duplicate search (2026-11-15): no existing report. The closest are #42319
(whose own "Expected behavior" lists this case as allowed) and its fix
#43194, which introduced the behaviour below.
-->

# Title

A `declare` field that narrows an inherited property gets TS2729 when a field initializer reads it (since #43194)

## 🔎 Search Terms

TS2729, used before its initialization, declare field, declare modifier, useDefineForClassFields, redeclare base class property, field initializer

## 🕗 Version & Regression Information

- This changed between versions 4.2.3 and 4.3.5.
- This changed in commit or PR #43194 ("Consider class field properties to redeclare parent definitions", the fix for #42319).
- It still reproduces in 5.9.3, 6.0.3 and `7.1.0-dev.20261114.1`.

## ⏯ Playground Link

https://www.typescriptlang.org/play/?target=99#code/MYGwhgzhAEBCkFNoG8BQ0PQEYC5oDsBXAWywQCdoBeaARgG5UBfVVUSGABXAEt9oEADwAuCfABMY8CEjSZo46tGEALHhAB0WetAD0u6AHkA0s1bso0AHJhy5APYB3BIqGiJUxCnSZxCduRIuHTQAD7QAEyM8oo0qupaOvoCdvaUACoAyhEA7BEAnHicDgAOFMIAntAA5FjV0OrQhDKKZABmaUg8wjB83TxgIDwAXmDCPPb4GmZskxD2IAgaIPYA5gAU+AiO1rYOzuLrAJQa4kdJBrSoQA

## 💻 Code

```ts
// @target: esnext  (so useDefineForClassFields is true)
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

`this.b` in `Narrowed`'s field initializer reports TS2729: "Property 'b' is used before its initialization."

## 🙂 Expected behavior

No error, the same as in `Plain`.

`declare b` emits nothing, so `b` is still the base class's property. `super()` runs `Base`'s initializer (`b = 1`) before `Narrowed`'s own field initializers, so `this.b` is already initialized when `d` reads it. The emitted program prints `1`.

#42319, the issue this check was added for, lists exactly this case under its "Expected behavior": "`c` is allowed because of the `declare` modifier".

## Additional information about the issue

- #43194 changed the condition in the property-access check to `(compilerOptions.useDefineForClassFields || !isPropertyDeclaredInAncestorClass(prop))`. Under `useDefineForClassFields`, this drops the ancestor exemption for every redeclaration, including `declare` ones. The test it added (`redeclaredProperty.ts`) covers only the non-`declare` case `b;`, which really is `undefined` at that point.
- TS2612 tells the user to do exactly this. Without the modifier, `b: 1 | 2;` reports "Property 'b' will overwrite the base property in 'Base'. … Otherwise, add a 'declare' modifier". Adding `declare` then produces TS2729.
- There is no error with `useDefineForClassFields: false`.
- #42319 also listed two more expected-OK reads that are reported today: a field whose initializer reads its own base value (`d: number = this.d`), and a field read before it is redeclared without an initializer (`e`). This report is only about the `declare` case, the one where the derived class declares nothing at runtime.
