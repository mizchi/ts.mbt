// @strict: true
// @target: esnext

// A function with no return annotation takes its return type from its
// body; one that writes `: any` returns `any`, whatever its body returns.

function written(): any { return 1; }
function inferred() { return 1; }
function inferredLet(flag: boolean) { let w = 1; if (flag) { w = 2; } return w; }

export const okWrittenAny: string = written();
export const okInferredLet: number = inferredLet(true);
export const badInferred: string = inferred();
export const badInferredLet: string = inferredLet(false);
