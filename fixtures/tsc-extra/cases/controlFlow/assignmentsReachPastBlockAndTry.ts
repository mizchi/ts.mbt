// @strict: true
// @target: esnext

// What a bare block or a `try` statement assigns to an outer binding reaches
// the code after it. After `try`/`catch` the binding is the union of the two
// exits: a catch that leaves the old value keeps it possible, a catch that
// returns does not, and a `try` that always returns leaves only the catch's
// state. An auto-typed `let x = null` assigned `any` is `any` afterwards, so
// a truthiness guard on it does not empty it to `never`.

declare const raw: string;
declare function risky(): void;

export function okBareBlockAssignment() { let x: string | null = null; { x = "a"; } return x.length; }
export function okTryAssignsAny() { let x = null; try { x = JSON.parse(raw); } catch {} if (!x) { return; } return x.info; }
export function okBlockAssignsAny() { let x = null; { x = JSON.parse(raw); } if (!x) { return; } return x.info; }
export function okCatchReturns() { let x: { info: number } | null = null; try { x = { info: 1 }; } catch { return 0; } return x.info; }
export function okTryReturnsCatchAssigns() { let x: string | null = null; try { return 0; } catch { x = "a"; } return x.length; }
export function okTryFinally() { let x: string | null = null; try { x = "a"; } finally { risky(); } return x.length; }

export function badCatchKeepsOldValue() { let x: { info: number } | null = null; try { x = { info: 1 }; } catch {} return x.info; }
export function badShadowInBlock() { let x: string | null = null; { let x = "a"; x.length; } return x.length; }
export function badOnlyCatchAssigns() { let x: string | null = null; try { risky(); } catch { x = "a"; } return x.length; }
