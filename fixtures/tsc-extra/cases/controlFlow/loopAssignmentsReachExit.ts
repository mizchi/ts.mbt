// @strict: true
// @target: esnext

// The code after a loop sees what the body assigned, joined with the type
// the binding had on entry: a `string`-narrowed union binding reassigned in
// the body is the union again after the loop, for every loop form. A binding
// the loop head declares does not leak past it. An assignment inside a
// callback is not seen by the narrowing at all, in tsc too.

export class EV { e = 1; }
interface N { v: number }
declare function handle(): number | string | EV;
declare function maybe(): N | undefined;
declare function iterate(cb: () => void): void;
declare const flag: boolean;
declare const xs: number[];
export function okWhile() {
  let result: number | string | EV = '';
  while (flag) { result = handle(); }
  return result instanceof EV;
}
export function okFor() {
  let result: number | string | EV = '';
  for (let i = 0; i < xs.length; i++) { if (flag) { } else { result = handle(); } }
  return result instanceof EV;
}
export function okForOf() {
  let result: number | string | EV = '';
  for (const x of xs) { result = handle(); }
  return result instanceof EV;
}
export function okLoopVarScoped() {
  for (let i = 0; i < 3; i++) { }
  let i = "s";
  return i.length;
}
export function badStringNotReassigned() {
  let s: number | string = '';
  return s instanceof EV;
}
export function badAfterCallback() {
  let result: number | string | EV = '';
  iterate(() => { result = handle(); });
  return result instanceof EV;
}
export function badNullableAfterWhile(n: N) {
  let x: N | undefined = n;
  while (flag) { x = maybe(); }
  return x.v;
}
