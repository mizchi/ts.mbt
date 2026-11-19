// @strict: true
// @target: esnext

// Which assignments a `catch` or `finally` block, and the code after the
// statement, can see. A `catch` is entered with every write the `try` block
// may have made before it threw, and a `finally` with every write before a
// `return` too. The code after a `finally` sees its writes only along paths
// that complete the block: a write followed by a `throw`, or by an `if` that
// throws on both sides, does not reach it. A declaration in a nested scope
// shields only the writes inside the statement that holds it, and an
// assignment-form loop head writes the outer binding.

declare const flag: boolean;
declare const other: boolean;

export function badCatchSeesWriteBeforeThrow() { let x: string | null = "ok"; try { x = null; throw 0; } catch { return x.length; } }
export function badFinallySeesWriteBeforeReturn() { let x: string | null = "ok"; try { x = null; return; } finally { x.length; } }
export function okFinallyWriteReachesContinuation() { let x: string | null = "ok"; try { x = null; } finally { x = "ok"; } return x.length; }
export function badFinallyNullWriteReachesContinuation() { let x: string | null = "ok"; try { x = "a"; } finally { x = null; } return x.length; }
export function okFinallyWriteBeforeThrow() { let x: string | null = "ok"; try { } finally { if (flag) { x = null; throw 0; } } return x.length; }
export function okFinallyWriteBeforeExitingIfElse() { let x: string | null = "ok"; try { } finally { if (flag) { x = null; if (other) throw 0; else throw 1; } } return x.length; }
export function badFinallyWriteBeforeConditionalThrow() { let x: string | null = "ok"; try { } finally { if (flag) { x = null; if (other) throw 0; } } return x.length; }
export function okNestedDeclarationShieldsItsWrite() { let x: string | null = "ok"; try { { let x: string | null = "a"; x = null; } throw 0; } catch { return x.length; } }
export function badNestedDeclarationThenOuterWrite() { let x: string | null = "ok"; try { { let x = 0; x = 1; } x = null; throw 0; } catch { return x.length; } }
export function badAssignmentLoopHeadWritesOuter() { let x: string | null = "ok"; try { for (x of [null]) { throw 0; } } catch { return x.length; } return 0; }
export function okLetLoopHeadIsItsOwn() { let x: string | null = "ok"; try { for (let x of [null]) { throw 0; } } catch { return x.length; } return 0; }
