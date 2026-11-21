// @strict: true
// @target: esnext

// A homomorphic mapped alias (`{ [P in keyof T]: … }` over its own type
// parameter) maps a primitive, `null`, `undefined` or `void` member of a
// union argument to itself, so `DeepReadonly<Nullable<Cell>>` admits the
// nullish members and a string. A value that fits no member is an error.

type DeepReadonly<T> = { readonly [P in keyof T]: T[P] };
type Opt<T> = { [P in keyof T]?: T[P] };
type Nullable<T> = T | null | undefined | void;
interface Cell { r: number; c: number }
declare function get(): Nullable<Cell>;
export function okReturn(): DeepReadonly<Nullable<Cell>> { return get(); }
export function okNull(): DeepReadonly<Cell | null> { return null; }
export function okString(): Opt<string | Cell> { return "s"; }
export function okLiteral(): DeepReadonly<"a" | Cell> { return "a"; }
export function badNumber(): DeepReadonly<Cell | null> { return 1; }
export function badMember(x: DeepReadonly<Cell | null>) { if (x) { const s: string = x.r; return s; } return ""; }
export function badString(): Opt<number | Cell> { return "s"; }
