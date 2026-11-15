<!--
Draft for microsoft/TypeScript, "Bug report" template.
Fixture: ../cases/feedback/expandoElementAccessAssignmentInBranch.ts
Duplicate search (2026-11-15): no existing report. microsoft/typescript-go#4134
fixed the dotted-write spelling for tsgo. It does not cover an element-access
write, and that behaves the same in 4.9.5 through 7.1.
-->

# Title

An expando property assigned with element access (`fn["q"] = 1`) in one branch does not get TS2565 when read later

## 🔎 Search Terms

TS2565, used before being assigned, expando, element access, bracket notation, function property assignment, conditional assignment

## 🕗 Version & Regression Information

- This is the behavior in every version I tried: 4.9.5, 5.9.3, 6.0.3 and `7.1.0-dev.20261114.1`.

## ⏯ Playground Link

https://www.typescriptlang.org/play/?target=99#code/CYUwxgNghgTiAEYD2A7AzgF0a4AueARkkhCFCgNwBQVAZgK4pgYCWq8Abi1ACJIYAKAJTwA3gF8qLWvAHIUwEaM7c+GAHQBHeAF54ARgrxJXXvy1H4V6-AD0t+CBgwkMeABUAygCYArADZffAAFFwAHJwwAT3gAck1Y+BY0eHo0EGBCEFpXBAIQFhQAc3goNDQWIpQM9SpTNQBtACJNJoBdS2t7R2dXDx8AoPhQpAiYaLiEpJS0jKycuCzCkrKKqpqaBiZWdlMAUVIAWxAUQSVJaVl5RTEVKAOQY9Pm1rbdAyMTbgenjU1OuwOFBIHouGB1b5HE4YF7tIzdYGg1xUIA

## 💻 Code

```ts
// @strict: true
declare const cond: boolean;

function viaDot() {}
if (cond) { viaDot.q = 1; }
viaDot.q;        // error TS2565: Property 'q' is used before being assigned.
viaDot["q"];     // error TS2565: Property 'q' is used before being assigned.

function viaElement() {}
if (cond) { viaElement["q"] = 1; }
viaElement.q;    // no error
viaElement["q"]; // no error
```

## 🙁 Actual behavior

TS2565 is reported for both reads of `viaDot.q`, and for neither read of `viaElement.q`.

## 🙂 Expected behavior

TS2565 on both reads of `viaElement.q` as well.

`viaElement["q"] = 1` declares the same expando property that `viaElement.q = 1` would (see `typeFromPropertyAssignment38`). It runs only when `cond` is true, so the property may be unassigned at the reads, exactly as with `viaDot`.

## Additional information about the issue

- The READ side already treats the two spellings the same: `viaDot["q"]` gets TS2565 just like `viaDot.q`. Only the spelling of the WRITE changes the result.
- `typeFromPropertyAssignment36` pins this check, and it writes only the dotted form.
- microsoft/typescript-go#4134 restored TS2565 for the dotted-write case in tsgo. The element-access write behaves as above in 6.0.3 as well, so this is not a 6.0 → 7.0 difference.
