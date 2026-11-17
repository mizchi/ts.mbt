// @strict: true
// @target: esnext

// Overload selection on a method reads a tuple-typed rest parameter as that
// many discrete parameters: `m(...xs: [string, number])` needs exactly two
// arguments, so `b.m(1)` takes `m(x: number)`. An optional tuple slot may be
// omitted, a rest element inside the tuple takes any count from its
// position, a nested tuple rest is flattened, and the elements on both sides
// of a rest in the middle of the tuple are required, so a call too short for
// them takes another member. An argument typed by an alias
// (`flag: Flag`, `type Flag = boolean`) fits a parameter of that alias and a
// parameter of what it resolves to, so the first such member is selected
// rather than a later `(x: any)`. A spread of a fixed-length tuple is that
// many arguments, while an array spread fits only a rest parameter. A generic
// member's type parameter is solved from the resolved argument, so
// `m<T>(a: T[], b: T[])` rejects a `number[]` beside a `string[]` even when
// both arrive through aliases, and a tuple spread binds `T` element by
// element, for a lone generic method as for an overload set.

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
declare class SpreadTarget { m(...xs: [string, number]): string; m(...xs: any[]): number; }
declare const pairArgs: [string, number];
declare const manyNumbers: number[];
type Nums = number[];
type Strs = string[];
declare class GenericFirst { m<T>(a: T[], b: T[]): string; m(a: number[], b: string[]): number; }
declare const nums: Nums;
declare const moreNums: Nums;
declare const strs: Strs;
declare class MiddleRestSuffix { m(...xs: [string, ...number[], boolean]): string; m(x: string): number; }
declare class GenericFromSpread { m<T>(value: T, count: number): T; m(...values: any[]): string; }
declare class LoneGeneric { m<T>(value: T, count: number): T; }

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
export function okTupleSpreadSelectsFirst(t: SpreadTarget) { const s: string = t.m(...pairArgs); return s; }
export function okArgumentThenTupleSpread(t: SpreadTarget) { const s: string = t.m("a", ...([1] as [number])); return s; }
export function okArraySpreadSelectsRest(t: SpreadTarget) { const n: number = t.m(...manyNumbers); return n; }
export function okAliasPairRejectsGeneric(g: GenericFirst) { const n: number = g.m(nums, strs); return n; }
export function okAliasPairSelectsGeneric(g: GenericFirst) { const s: string = g.m(nums, moreNums); return s; }
export function okMiddleRestSuffixMissing(b: MiddleRestSuffix) { const n: number = b.m("a"); return n; }
export function okMiddleRestSuffixGiven(b: MiddleRestSuffix) { const s: string = b.m("a", true); return s; }
export function okMiddleRestFilled(b: MiddleRestSuffix) { const s: string = b.m("a", 1, 2, true); return s; }
export function okGenericFromTupleSpread(c: GenericFromSpread, xs: [string, number]): string { return c.m(...xs); }
export function okLoneGenericFromTupleSpread(c: LoneGeneric, xs: [string, number]): string { return c.m(...xs); }

export function badTupleRestSelectsFirst(b: TupleRest) { const n: number = b.m("a", 2); return n; }
export function badOptionalSlotOmitted(o: OptionalSlot) { const n: number = o.m("a"); return n; }
export function badArrayRestInTupleSecond(a: ArrayRestInTuple) { const s: string = a.m(1); return s; }
export function badNestedTupleRestSecond(t: NestedTupleRest) { const s: string = t.m("a"); return s; }
export function badMiddleRestPrefixRejects(c: MiddleRest) { const s: string = c.m(1); return s; }
export function badAliasArgument(f: AliasParam, flag: Flag) { const n: number = f.m(flag); return n; }
export function badAliasArgumentResolvedParam(g: ResolvedParam, flag: Flag) { const n: number = g.m(flag); return n; }
export function badObjectAliasArgument(p: ObjectAliasParam, pair: Pair) { const n: number = p.m(pair); return n; }
export function badTupleSpreadSelectsFirst(t: SpreadTarget) { const n: number = t.m(...pairArgs); return n; }
export function badAliasPairRejectsGeneric(g: GenericFirst) { const s: string = g.m(nums, strs); return s; }
export function badAliasPairSelectsGeneric(g: GenericFirst) { const n: number = g.m(nums, moreNums); return n; }
export function badMiddleRestSuffixMissing(b: MiddleRestSuffix) { const s: string = b.m("a"); return s; }
export function badGenericFromTupleSpread(c: GenericFromSpread, xs: [string, number]): number { return c.m(...xs); }
export function badLoneGenericFromTupleSpread(c: LoneGeneric, xs: [string, number]): number { return c.m(...xs); }
// A lone generic method whose rest parameter is a tuple: the formal is
// expanded like the spread argument, positionally too.
interface TupleRestGeneric { first<T>(...args: [T, number]): T }
export function okTupleRestFromSpread(a: TupleRestGeneric, xs: [string, number]) { const s: string = a.first(...xs); return s; }
export function okTupleRestPositional(a: TupleRestGeneric) { const s: string = a.first("a", 1); return s; }
export function badTupleRestFromSpread(a: TupleRestGeneric, xs: [string, number]) { const n: number = a.first(...xs); return n; }
export function badTupleRestPositional(a: TupleRestGeneric) { const n: number = a.first("a", 1); return n; }
