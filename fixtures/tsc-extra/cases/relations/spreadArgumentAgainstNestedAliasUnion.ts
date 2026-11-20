// @strict: true
// @target: esnext

// A spread argument's element is related to the rest parameter's element the
// way a plain argument is, through every alias the target's union members
// name. univer's `new Charset(...next)` spreads `[number, number]` tuples
// into `...inputs: CharsetInput[]`, where `CharsetInput = Charset |
// CharsetRawInput` and the tuple sits one alias further in.

type Unit = [number, number];
type Raw = string | number | [string, string] | [number, number];
class Charset { data: Unit[] = []; constructor(...inputs: Input[]) {} }
type Input = Charset | Raw;
declare function take(...inputs: Input[]): void;

export function okSpreadCall(next: Unit[]) { take(...next); }
export function okSpreadNew(next: Unit[]) { return new Charset(...next); }
export function okDirect(u: Unit) { take(u); }
export function badSpreadElement(next: boolean[]) { take(...next); }
export function badSpreadTuple(next: [boolean, boolean][]) { take(...next); }
