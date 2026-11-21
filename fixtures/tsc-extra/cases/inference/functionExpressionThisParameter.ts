// @strict: true
// @target: esnext

// A function expression's leading `this` parameter types the receiver and
// takes no argument, through a generic identity-shaped wrapper and through
// a binding alike, and as a callback against a signature that supplies
// only the other parameters. One argument too many is still an error, and
// so is a callback that requires more than the signature supplies.

declare function throttle<T extends (...args: any[]) => any>(fn: T, wait?: number): T;
const ctx = {
    base: 1,
    throttled: throttle(function (this: { base: number }, step: number) { return this.base + step; }),
};
const f = function (this: { base: number }, step: number) { return this.base + step; };
const holder = { base: 2, f };
export const okWrapped = ctx.throttled(1);
export const okBound = holder.f(3);
export function badTooMany() {
    const plain = function (this: { base: number }, step: number) { return step; };
    return plain(1, 2);
}
declare function on(cb: (e: number) => void): void;
declare function on0(cb: () => void): void;
export function okCallback() { on(function (this: { id: number }, e: number) { return; }); }
export function okNoArgs() { on0(function (this: { id: number }) {}); }
export function badCallbackArity() { on(function (this: { id: number }, e: number, extra: string) {}); }
