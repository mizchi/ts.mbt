// @strict: true

// `void <expr>` always evaluates to `undefined`, so the right operand of `??`
// is ALWAYS reached. The literal spelling gets TS2871 ("This expression is
// always nullish"); every `void` spelling gets TS2869 ("Right operand of ?? is
// unreachable because the left operand is never nullish"), which is the
// opposite claim. Expected: TS2871 (or no diagnostic) on the `void` lines.
declare let y: number;
declare function sideEffect(): void;

const viaUndefined = undefined ?? y;
const viaVoidZero = void 0 ?? y;
const viaVoidParenthesized = (void 0) ?? y;
const viaVoidCall = void sideEffect() ?? y;
