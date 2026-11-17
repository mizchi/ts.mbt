// @strict: true
// @target: esnext

// The false branch of a type guard removes the members that fit its target.
// `any` and `unknown` have no members to remove, so they stay what they
// were: an `any` is still `any` (not `never`), and an `unknown` is still
// `unknown`, so reading a member of it is an error. A union loses exactly
// the members the target covers.

declare const isFiniteNumber: (value: any) => value is number;
declare const a: any;
declare const u: unknown;
declare const x: number | { value: number };
interface S { zoom?: any }
declare const s: S;

function okAnyElseIsAny() { const v = isFiniteNumber(a) ? a : a.value; }
function okAnyPathElseIsAny() { const v = isFiniteNumber(s.zoom) ? s.zoom : s.zoom.value; }
function okUnionElseIsTheRest() { const n: number = isFiniteNumber(x) ? x : x.value; }
function badUnknownElseIsUnknown() { const v = isFiniteNumber(u) ? u : u.value; }
function badUnionElseWrongMember() { const v = isFiniteNumber(x) ? x : x.nope; }
