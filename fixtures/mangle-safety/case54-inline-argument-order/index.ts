// `call_inline` substituting an IMPURE argument.
//
// The pass required every argument to be pure. That requirement exists
// to stop three things — duplicating an argument's effects, dropping
// them, and reordering them — and all three are questions about where
// the BODY reads its parameters, not about the arguments. When the body
// reads every parameter exactly once, in argument order, and
// unconditionally, substitution reproduces the call's evaluation exactly.
//
// It matters in practice because `is_pure_value` calls a property read
// impure (correctly — a getter can do anything), so a one-line helper
// was never inlined at any call site whose argument read a property.
// typebox calls one such helper 160 times, and it is what stood between
// `IsEqual(proto.constructor.name, "Object")` and being recognised as a
// literal comparison. See `case53-ctor-name-compared-to-literal`.
//
// Every observation below is an ORDER, because that is what the rule
// claims. A case that only checked the RESULT would pass with the gate
// removed: `l || r` computes the same boolean whether or not the right
// operand's side effect ran.

const trace: string[] = [];

function tap(s: string): string {
  trace.push(s);
  return s;
}

function tapNum(s: string, n: number): number {
  trace.push(s);
  return n;
}

// ---------------------------------------------------------------------
// Exact: read once, in order, unconditionally. Inlining these is safe
// even though every argument has an effect.
// ---------------------------------------------------------------------

const isEq = (l: string, r: string): boolean => l === r;
const sum = (a: number, b: number): number => a + b;
const pick = (o: { v: number }, k: number): number => o.v + k;

export const eq: string = String(isEq(tap("a1"), tap("a2"))) + "/" +
  trace.join(",");
export const added: string = sum(tapNum("b1", 1), tapNum("b2", 2)) + "/" +
  trace.join(",");
export const picked: string = pick({ v: tapNum("c1", 10) }, tapNum("c2", 5)) +
  "/" +
  trace.join(",");

// ---------------------------------------------------------------------
// NOT exact. Each of these must be left as a call.
// ---------------------------------------------------------------------

// Short-circuit: the CALL always evaluates both arguments; the
// substituted `l || r` would skip the right one. With the gate removed
// the trace loses `d2`.
const orFn = (l: boolean, r: boolean): boolean => l || r;
export const shortCircuited: string = String(
  orFn(tap("d1") === "d1", tap("d2") === "d2"),
) +
  "/" +
  trace.join(",");

// Nullish coalescing, same hazard with a different operator.
const orElse = (l: string | null, r: string): string => l ?? r;
export const coalesced: string = orElse(tap("e1"), tap("e2")) + "/" +
  trace.join(",");

// Conditional: both branches are guarded, so substituting moves two
// argument evaluations behind a test. With the gate removed the trace
// loses one of `f2` / `f3`.
const choose = (c: boolean, t: string, f: string): string => (c ? t : f);
export const chosen: string = choose(
  tap("f1") === "f1",
  tap("f2"),
  tap("f3"),
) +
  "/" +
  trace.join(",");

// Out of order: the body reads its second parameter first, so
// substitution would swap two argument evaluations. With the gate
// removed the trace reads `g2,g1`.
const swapped = (l: string, r: string): string => r + l;
export const swappedOrder: string = swapped(tap("g1"), tap("g2")) + "/" +
  trace.join(",");

// A parameter the body never reads: its argument's effect would vanish
// entirely. With the gate removed the trace loses `h2`.
const dropSecond = (l: string, r: string): string => l;
export const dropped: string = dropSecond(tap("h1"), tap("h2")) + "/" +
  trace.join(",");
