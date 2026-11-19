// @strict: true
// @target: esnext

// A block-scoped declaration that shadows an outer binding is a binding of
// its own. When the block ends, the outer binding is assigned against ITS
// declaration again, whatever the inner one was declared as: an `if`
// branch, a bare block and a `for` head all shadow this way. Inside the
// block, an assignment is still checked against the inner declaration.

declare const c: boolean;

export function okIfBranchShadow() { let x: string | null = null; if (c) { let x = 5; x = 6; } else { x = "a"; } return x; }
export function okBareBlockShadow() { let x: string | null = null; { let x = 5; x = 6; } x = "a"; return x; }
export function okShadowThenAssign() { let x: string | null = null; if (c) { let x = 5; } x = "a"; return x; }
export function okForHeadShadow() { let x: string | null = null; for (let x = 0; x < 3; x++) { } x = "a"; return x; }

export function badInnerDeclarationDecides() { let x: string | null = null; { let x = 5; x = "a"; } return x; }
export function badOuterDeclarationDecides() { let x: string | null = null; { let x = "a"; } x = 5; return x; }
