// @strict: true
// @target: esnext

// The rest element of an array pattern over a variadic tuple takes the
// tuple's slice. From a position at or before the tuple's rest element it
// is the tail as written (`[h, ...t]: [number, ...string[]]` binds `t` as
// `[...string[]]`). From a position past it, it is an array of every
// element type from the rest on, so `[h, f, ...t]` binds `string[]` and a
// fixed tail element joins the union. The same holds for a rest parameter
// whose pattern takes its type from a contextual rest tuple.

export function okTwoHead([h, f, ...t]: [number, ...string[]]) { const x: string[] = t; const [n] = t; const v: string = n; return [h, f, x, v]; }
export function badTwoHead([h, f, ...t]: [number, ...string[]]) { const x: number[] = t; return [h, f, x]; }
export function badElementOfRemainder([h, f, ...t]: [number, ...string[]]) { const [n] = t; const v: number = n; return [h, f, v]; }
export function okOneHead([h, ...t]: [number, ...string[]]) { const x: string[] = t; return [h, x]; }
export function okWhole([...t]: [number, ...string[]]) { const x: [number, ...string[]] = t; return x; }
export function okPastTail([a, b, c, ...t]: [number, ...string[], boolean]) { const x: (string | boolean)[] = t; return [a, b, c, x]; }
export function badPastTail([a, b, c, ...t]: [number, ...string[], boolean]) { const x: string[] = t; return [a, b, c, x]; }
export function okBeforeTail([a, ...t]: [number, ...string[], boolean]) { const x: [...string[], boolean] = t; return [a, x]; }
export function okCallback() { const cb: (...xs: [number, ...string[]]) => void = (...[head, first, ...tail]) => { const [next] = tail; const v: string = next; void [head, first, v]; }; return cb; }
export function badCallback() { const cb: (...xs: [number, ...string[]]) => void = (...[head, first, ...tail]) => { const x: number[] = tail; void [head, first, x]; }; return cb; }
export function okCallbackParams() { const cb: (...xs: [number, ...string[]]) => void = (h, f, ...tail) => { const v: string[] = tail; void [h, f, v]; }; return cb; }
