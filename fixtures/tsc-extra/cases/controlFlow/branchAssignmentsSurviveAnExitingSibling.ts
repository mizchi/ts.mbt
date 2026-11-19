// @strict: true
// @target: esnext

// When one branch of an `if` always exits, the code after the `if` sees
// what the OTHER branch assigned, not only the condition's narrowing. A
// name the branch declares itself is its own binding. A binding declared
// with a tuple alias keeps the alias when an array literal is assigned.

declare function takeS(s: string): void;
type Bounds = [number, number, number, number];

export function okThenAssigns(a: number) { let s: string | null = null; if (a < 0) { s = "x"; } else { return; } takeS(s); }
export function okElseAssigns(a: number) { let s: string | null = null; if (a < 0) { return; } else { s = "y"; } takeS(s); }
export function okElseIfChain(a: number) { let s: string | null = null; if (a < 0) { s = "x"; } else if (a > 0) { s = "y"; } else { return; } takeS(s); }
export function okThrowingSibling(a: number) { let s: string | null = null; if (a < 0) { s = "x"; } else { throw new Error("e"); } takeS(s); }
export function badAssignsNull(a: number) { let s: string | null = "z"; if (a < 0) { s = null; } else { return; } takeS(s); }
export function badNestedMaybe(a: number, b: boolean) { let s: string | null = null; if (a < 0) { if (b) { s = "x"; } } else { return; } takeS(s); }
export function badShadowInBranch(a: number) { let s: string | null = null; if (a < 0) { let s = "inner"; takeS(s); } else { return; } takeS(s); }

export function okTupleAliasBothBranches(c: boolean): Bounds { let b: Bounds; if (c) { b = [1, 2, 3, 4]; } else { b = [5, 6, 7, 8]; } return b; }
export function okTupleAliasAfterExit(c: number): Bounds { let b: Bounds; if (c < 0) { return [0, 0, 0, 0]; } else if (c > 0) { b = [1, 2, 3, 4]; } else { b = [5, 6, 7, 8]; } return b; }
export function badTupleAliasWrongLength(c: boolean): Bounds { let b: Bounds; if (c) { b = [1, 2, 3]; } else { b = [5, 6, 7, 8]; } return b; }
