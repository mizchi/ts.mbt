// @strict: true
// @target: esnext

// An unannotated function contextually typed by `() => void` infers its own
// return type, and `() => boolean` is assignable to `() => void`, so its
// `return` statements may carry a value. Only the function's own annotation
// makes a returned value an error, and a contextual `() => Promise<void>`
// still requires an async body to return nothing.

declare const xs: number[];

function okForEachReturnsFalse() { xs.forEach((x) => { if (x > 1) { return false; } }); }
function okFunctionExpressionReturns() { xs.forEach(function (x) { return x; }); }
function okOwnAnnotationWins() { xs.forEach((x): boolean => { return x > 0; }); }
function okVoidTypedBinding() { const k: () => void = () => { return true; }; }
function okAsyncIntoVoid() { const k: () => void = async () => { return 1; }; }
function okCallSignatureObject() { const k: { (): void } = () => { return 1; }; }
function okOptionalVoidCallback() { const k: (() => void) | undefined = () => { return 1; }; }
function badOwnVoidAnnotation() { xs.forEach((x): void => { return x > 0; }); }
function badPromiseVoidContext() { const k: () => Promise<void> = async () => { return 1; }; }
function badAnnotatedVoidReturn(): void { return false; }
