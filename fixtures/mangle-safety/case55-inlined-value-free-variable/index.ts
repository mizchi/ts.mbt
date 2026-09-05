// The names an INLINED VALUE reads, re-resolved in the scope it lands in.
//
// `case43` covers the first half of this question: the table is keyed by
// NAME, so a scope that re-binds that name must drop the entry or the
// call resolves to the wrong callee. This is the second half, and for a
// long time nothing asked it — dropping the entry whose KEY is shadowed
// says nothing about the names the substituted VALUE reads, and those
// get re-resolved wherever the value is spliced.
//
//   const base = Number(process.argv.length);   // 2
//   const f = () => base;
//   function g() { const other = 99; return f() + other * 0 }
//
// The mangler runs BEFORE the inline phase and gave `base` and `other`
// the same short name `a` — legitimately, since at mangle time `g`'s
// body does not mention `base`, so shadowing it is free. Then the
// inliner spliced `f`'s body, whose `a` is the OUTER one, into a scope
// where `a` is 99. mtsc answered 99 where the answer is 2, under plain
// `--bundle --treeshake --fold --minify --mangle`, with no crash and no
// free variable — so `--verify` cannot see it. The better the mangler
// does its job, the more often the collision happens.
//
// Four tables substitute a value that can carry free variables and none
// of them checked: `call_inline`, `as_const_inline` (both halves),
// `predicate_inline` and `switch_fold`. `const_enum_inline` and
// `type_fold` substitute literals and are safe by construction.
//
// Each group pairs a read that MUST NOT be captured with one that must
// still be optimized, so the fix cannot be "switch the pass off".
//
// The values below are all derived from `process.argv.length`, which is
// 2 for a bare `node file.mjs`. A literal would be folded away before
// any of these passes ran, and the collision needs a binding that
// survives to the mangler.

// `process` is not in the default `lib` set (it comes from
// `@types/node`), and mtsc reports TS2591 for an undeclared use of
// it. Declaring the one member this fixture reads is what the
// diagnostic asks for; `declare` emits nothing, so `process.argv`
// is still Node's at runtime and still opaque to every fold.
declare const process: { argv: string[] };

const argc: number = Number(process.argv.length);

// ---- call_inline -----------------------------------------------------
// `viaCall`'s body reads `base`. `callShadowed` re-binds that name to
// something else; `callPlain` does not.
const base: number = argc;
const viaCall = (): number => base;

function callShadowed(): number {
  const base = 99;
  return viaCall() + base * 0;
}
function callPlain(): number {
  return viaCall() + 0;
}

// ---- call_inline, through a parameter --------------------------------
// A parameter binds a name no block declares, which is the spelling that
// defeated a block-level check in `case43`.
const seed2: number = argc + 10;
const viaParam = (): number => seed2;

function paramShadowed(seed2: number): number {
  return viaParam() + seed2 * 0;
}

// ---- as_const_inline -------------------------------------------------
// `TABLE[0]` substitutes the element, which reads `elem`.
const elem: number = argc + 20;
const TABLE = [elem, 7] as const;

function tableShadowed(): number {
  const elem = 99;
  return TABLE[0] + elem * 0;
}
function tablePlain(): number {
  return TABLE[1];
}

// ---- predicate_inline ------------------------------------------------
// The guard's body reads `limit`; the caller re-binds it.
const limit: number = argc;
function isSmall(v: unknown): v is number {
  return limit < 100;
}

function guardShadowed(v: unknown): string {
  const limit = 999;
  return (isSmall(v) ? "small" : "big") + String(limit * 0);
}

// ---- switch_fold -----------------------------------------------------
// The matched arm reads `arm`; the caller re-binds it.
const arm: number = argc + 30;
type Which = "a" | "b";
function dispatch(k: Which): number {
  switch (k) {
    case "a":
      return arm;
    default:
      return 0;
  }
}

function switchShadowed(): number {
  const arm = 99;
  return dispatch("a") + arm * 0;
}

export const report = {
  // 2 each: the inlined body must keep reading the OUTER binding.
  callShadowed: callShadowed(),
  callPlain: callPlain(),
  paramShadowed: paramShadowed(500),
  // 22
  tableShadowed: tableShadowed(),
  tablePlain: tablePlain(),
  guardShadowed: guardShadowed(1),
  // 32
  switchShadowed: switchShadowed(),
};
