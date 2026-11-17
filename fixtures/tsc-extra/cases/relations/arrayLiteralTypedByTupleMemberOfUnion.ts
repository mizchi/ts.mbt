// @strict: true
// @target: esnext

// An array literal against a union with one tuple member and a class member
// is typed by the tuple, as `@flatten-js/interval-tree` declares every key
// (`Interval | NumericTuple`): `[a, b]` fits. A literal of the wrong length
// or element type fits neither member and is still an error, at a method
// argument, a function argument and an annotated binding alike.

type NumericTuple = [number, number];
declare class Interval { low: number; high: number; }
declare class Tree<T> { insert(key: Interval | NumericTuple, value?: T): void; }
declare function f(key: Interval | NumericTuple): void;

export function okMethodArgument(t: Tree<string>, a: number, b: number) { t.insert([a, b]); }
export function okFunctionArgument(a: number) { f([a, a]); }
export function okInlineTupleMember(t: { m(k: Interval | [number, number]): void }, a: number) { t.m([a, a]); }
export function okAnnotatedBinding(a: number) { const k: Interval | NumericTuple = [a, 1]; return k; }

export function badTooManyElements(t: Tree<string>, a: number) { t.insert([a, a, a]); }
export function badElementType(a: number) { f([a, "x"]); }
export function badAnnotatedBinding(a: number) { const k: Interval | NumericTuple = [a]; return k; }
