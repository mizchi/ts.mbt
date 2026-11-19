// @strict: true
// @target: esnext

// `0n` is falsy (`Boolean(0n) === false`), so `0n && x` always yields `0n`
// and `0n || x` always yields `x`. TypeScript reports both as TS2872 "This
// kind of expression is always truthy", the opposite claim. Every other
// falsy literal gets TS2873 "always falsy", and a zero NUMBER is exempt.
// Expected: TS2873 (or no diagnostic) on the `0n` lines.
declare const x: string;

const viaZeroBigintAnd = 0n && x;
const viaZeroBigintOr = 0n || x;
const viaEmptyString = "" || x;
const viaZeroNumber = 0 && x;
const viaOneBigint = 1n && x;
