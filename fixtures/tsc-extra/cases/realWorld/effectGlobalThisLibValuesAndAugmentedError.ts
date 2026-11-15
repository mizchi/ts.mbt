// @strict: true
// @target: esnext

// effect: a lib value read off `globalThis`, a `declare global` augmentation
// of `Error`, and a parameter named like a module-level class.

export const Arr = globalThis.Array;
declare global { interface Error { readonly code?: number } }
abstract class Class {}
interface Box { v: number }
function ok1(e: Error): unknown { return [e.message, e.stack, e.code]; }
function ok2(C: new (v: number) => Box): number { return new C(1).v; }
function ok3(a: unknown, b: unknown): boolean { return a === b; }
