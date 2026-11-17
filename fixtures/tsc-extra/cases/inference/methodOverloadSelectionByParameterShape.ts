// @strict: true
// @target: esnext

// Overload selection on a method reads a tuple-typed rest parameter as that
// many discrete parameters: `m(...xs: [string, number])` needs exactly two
// arguments, so `b.m(1)` takes `m(x: number)`. An optional tuple slot may be
// omitted, a rest element inside the tuple takes any count from its
// position, a nested tuple rest is flattened, and the positions before a rest
// in the middle of the tuple are fixed. An argument typed by an alias
// (`flag: Flag`, `type Flag = boolean`) fits a parameter of that alias and a
// parameter of what it resolves to, so the first such member is selected
// rather than a later `(x: any)`.

declare class TupleRest { m(...xs: [string, number]): string; m(x: number): number; }
declare class OptionalSlot { m(...xs: [string, number?]): string; m(x: number): number; }
declare class ArrayRestInTuple { m(...xs: [string, ...number[]]): string; m(x: number): number; }
declare class NestedTupleRest { m(...xs: [string, ...[number, boolean]]): string; m(x: string): number; }
declare class MiddleRest { m(...xs: [string, ...number[], boolean]): string; m(x: number): number; }
type Flag = boolean;
declare class AliasParam { m(x: Flag): string; m(x: any): number; }
declare class ResolvedParam { m(x: boolean): string; m(x: any): number; }
type Pair = { k: string };
declare class ObjectAliasParam { m(x: Pair): string; m(x: any): number; }

export function okTupleRestSelectsSecond(b: TupleRest) { const n: number = b.m(1); return n; }
export function okTupleRestSelectsFirst(b: TupleRest) { const s: string = b.m("a", 2); return s; }
export function okOptionalSlotOmitted(o: OptionalSlot) { const s: string = o.m("a"); return s; }
export function okOptionalSlotGiven(o: OptionalSlot) { const s: string = o.m("a", 1); return s; }
export function okArrayRestInTupleEmpty(a: ArrayRestInTuple) { const s: string = a.m("a"); return s; }
export function okArrayRestInTupleMany(a: ArrayRestInTuple) { const s: string = a.m("a", 1, 2); return s; }
export function okArrayRestInTupleSecond(a: ArrayRestInTuple) { const n: number = a.m(1); return n; }
export function okNestedTupleRestFirst(t: NestedTupleRest) { const s: string = t.m("a", 1, true); return s; }
export function okNestedTupleRestSecond(t: NestedTupleRest) { const n: number = t.m("a"); return n; }
export function okMiddleRestPrefixRejects(c: MiddleRest) { const n: number = c.m(1); return n; }
export function okAliasArgument(f: AliasParam, flag: Flag) { const s: string = f.m(flag); return s; }
export function okAliasArgumentResolvedParam(g: ResolvedParam, flag: Flag) { const s: string = g.m(flag); return s; }
export function okObjectAliasArgument(p: ObjectAliasParam, pair: Pair) { const s: string = p.m(pair); return s; }

export function badTupleRestSelectsFirst(b: TupleRest) { const n: number = b.m("a", 2); return n; }
export function badOptionalSlotOmitted(o: OptionalSlot) { const n: number = o.m("a"); return n; }
export function badArrayRestInTupleSecond(a: ArrayRestInTuple) { const s: string = a.m(1); return s; }
export function badNestedTupleRestSecond(t: NestedTupleRest) { const s: string = t.m("a"); return s; }
export function badMiddleRestPrefixRejects(c: MiddleRest) { const s: string = c.m(1); return s; }
export function badAliasArgument(f: AliasParam, flag: Flag) { const n: number = f.m(flag); return n; }
export function badAliasArgumentResolvedParam(g: ResolvedParam, flag: Flag) { const n: number = g.m(flag); return n; }
export function badObjectAliasArgument(p: ObjectAliasParam, pair: Pair) { const n: number = p.m(pair); return n; }
