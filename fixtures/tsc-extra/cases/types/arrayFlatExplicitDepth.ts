// @strict: true
// @target: esnext

// `flat()` and `flat(1)` remove one level of nesting, `flat(0)` removes
// none, and a larger depth removes as many as the array has.

declare const rows: number[][];
declare const deep: number[][][];

function okDefaultDepth() { const r: number[] = rows.flat(); }
function okDepthOne() { const r: number[] = rows.flat(1); }
function okDepthZero() { const r: number[][] = rows.flat(0); }
function okDepthTwo() { const r: number[] = deep.flat(2); }
function badDepthZeroFlattened() { const r: number[] = rows.flat(0); }
function badDefaultDepthOnDeep() { const r: number[] = deep.flat(); }
