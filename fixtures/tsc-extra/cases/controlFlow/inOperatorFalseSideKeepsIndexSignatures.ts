// @strict: true
// @target: esnext

// `"k" in x` narrows a union on both sides. The false side removes only a
// member that DECLARES `k`: one that answers for it through an index
// signature may still lack it at runtime, so it stays in the else branch.
// A member that declares `k` beside an index signature is removed. The
// true side keeps the index-signature member too, so a read there is the
// union of both members.

type A = { x: number } | { y: string };
interface Dict { [k: string]: string }

export function okRemovesDeclarer(v: A) { if (!("x" in v)) { return v.y; } return 0; }
export function badElseOfDeclarer(v: A) { if ("x" in v) { return 0; } return v.x; }
export function okRecordKept(c: readonly string[] | Record<string, number>, v: string) { return "includes" in c ? 1 : c.hasOwnProperty(v); }
export function badRecordKeptOnTrueSideToo(c: readonly string[] | Record<string, number>, v: string) { return "includes" in c ? c.includes(v) : 1; }
export function okGenericRecordKept<T extends string>(c: readonly T[] | Record<T, any>, v: string) { return "includes" in c ? c.includes(v as T) : c.hasOwnProperty(v); }
export function okInterfaceIndexKept(c: string[] | Dict) { return "map" in c ? 1 : c.anything.length; }
export function badDeclaredBesideIndex(c: readonly string[] | { [k: string]: number; includes: number }) { return "includes" in c ? 1 : c.foo; }
