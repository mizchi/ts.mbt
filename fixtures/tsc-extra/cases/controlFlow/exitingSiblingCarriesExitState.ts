// @strict: true
// @target: esnext

// After an `if` whose other branch exits, the code after it sees the
// continuing branch's exit state: a binding reassigned there has the
// assigned type even when the condition had narrowed it, and a property
// path narrowed there stays narrowed.

declare function takeS(s: string): void;

export function badReassignedAfterGuard(x: string | null, y: string | null) { if (x !== null) { x = y; } else { return; } takeS(x); }
export function badReassignedAfterTruthiness(x: string | null, y: string | null) { if (x) { x = y; } else { return; } takeS(x); }
export function okPathNarrowedInBranch(flag: boolean) { const o: { p: string | null } = { p: null }; if (flag) { o.p = ""; } else { return; } takeS(o.p); }
export function okReassignedNonNull(x: string | null, y: string) { if (x !== null) { x = y; } else { return; } takeS(x); }
interface O2 { p: string | null }
export function badPathForgottenByReassignment(o: O2, replacement: O2) { if (o.p !== null) { o = replacement; } else { return; } takeS(o.p); }
export function okPathOnlyRead(o: O2) { if (o.p !== null) { const q = o.p; } else { return; } takeS(o.p); }
