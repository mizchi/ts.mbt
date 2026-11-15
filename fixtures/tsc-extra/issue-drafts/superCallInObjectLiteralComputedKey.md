<!--
Draft for microsoft/TypeScript, "Bug report" template.
Fixture: ../cases/feedback/superCallInObjectLiteralComputedKey.ts
Duplicate search (2026-11-15): no existing report. #56754 concerns hoisting of
computed keys that contain `super()` in emit, a different problem.
Lower impact than the other drafts: both spellings are errors either way, and
only the diagnostic differs.
-->

# Title

`super()` in an object literal's computed key inside an arrow in a constructor reports TS2466 rather than TS2337

## 🔎 Search Terms

TS2466, TS2337, super cannot be referenced in a computed property name, super call, arrow function, constructor, computed property name, object literal

## 🕗 Version & Regression Information

- This is the behavior in every version I tried: 4.2.3, 4.9.5, 5.9.3, 6.0.3 and `7.1.0-dev.20261114.1`.

## ⏯ Playground Link

https://www.typescriptlang.org/play/?target=99#code/MYGwhgzhAEBCkFNoG8C+AodpIwNIIE8BJAOwGEB7EiAFwCcBXYGiu6BADxoRIBMZ4EJMnTQx0YFVqNmrABQBKFKPGq5yaAG05EBgAcEdRQBpoAIjBmFAXQBc0AIzRUCgNzQA9B+gB5XCrEMDCxwKGh8YhIAQTo6CgB3di4efjhEZVVJanomFiMlEVVVXQN81wCirNpoADNoAF5oRQaAPiaNbRLDE3NLG3snF3cvdljWaAAVAGUAJgAWADYFiqDMbDCyMBAQUhi4xM5uPgF0wvEqnNl8jKKxLrKKzKkaWoampXq2+8Vh70M4tjTGYAZmBAHYVugMEA

## 💻 Code

```ts
// @target: esnext
class Base {}

class KeyInConstructor extends Base {
    constructor() {
        ({ [(super(), "a")]: 1 }); // OK
    }
}

class KeyInArrow extends Base {
    constructor() {
        super();
        const f = () => ({ [(super(), "a")]: 1 }); // error TS2466
    }
}

class CallInArrow extends Base {
    constructor() {
        super();
        const f = () => super(); // error TS2337
    }
}
```

## 🙁 Actual behavior

- `KeyInConstructor`: no error. `super()` in a computed property name is accepted.
- `KeyInArrow`: TS2466, "'super' cannot be referenced in a computed property name."
- `CallInArrow`: TS2337, "Super calls are not permitted outside constructors or in nested functions inside constructors."

## 🙂 Expected behavior

`KeyInArrow` should report TS2337, as `CallInArrow` does.

`KeyInConstructor` shows that a `super()` call in a computed key is allowed. What `KeyInArrow` adds is the arrow function, and that is TS2337's rule. The TS2466 message points the user at the computed key, which is not the problem.

The alternative is equally consistent: if a computed key is not meant to hold `super()`, then `KeyInConstructor` should report TS2466 too. Either way, the two classes should not disagree.

## Additional information about the issue

The conformance tests pin both halves today. `computedPropertyNames28_ES6` is the constructor form, accepted. `computedPropertyNames30_ES6` is the arrow form, TS2466. The comment in `computedPropertyNames30_ES6` says the reference is illegal because of the arrow: "Ideally, we would capture this. But the reference is illegal, and not capturing this is consistent with treatment of other similar violations".
