// @strict: true
// @target: esnext

// A function type's return is compared structurally: `() => { a: number }`
// is a `() => A` for `interface A { a: number }`. A mutable `Map` or `Set`
// is its readonly view, there and anywhere else.

interface A { a: number }
interface RO { readonly r: ReadonlyMap<string, number> }

declare const g: () => { a: number };
export const okPlain: () => A = g;
declare const g2: () => { r: Map<string, number> };
export const okMapReturn: () => RO = g2;
declare const g3: () => Map<string, number>;
export const okMapToReadonly: () => ReadonlyMap<string, number> = g3;
declare const g4: () => Set<string>;
export const okSetToReadonly: () => ReadonlySet<string> = g4;
declare const g5: () => { a: string };
export const badPlain: () => A = g5;

interface Hooks<In, Out> { get: () => Out; update: (i: In) => void }
declare function makeHooks<In, Out>(get: () => Out, update: (i: In) => void): Hooks<In, Out>;
interface FS { readonly occurrences: ReadonlyMap<string, number> }
export function okHooks(): Hooks<string, FS> {
  const occurrences = new Map<string, number>();
  return makeHooks(() => ({ occurrences }), (w: string) => { occurrences.set(w, 1); });
}

// A class target's methods count: a source class without `required()` is
// not a `Target`, and one with every member and more is a `Source`.
class Source { tag = 1; }
class Target { tag = 1; required(): number { return 1; } }
declare const gs: () => Source;
export const badClassMethod: () => Target = gs;
declare const gt: () => Target;
export const okClassSubtype: () => Source = gt;
