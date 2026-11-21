// @strict: true
// @target: esnext

// Comparing equal to a numeric literal rules out `null` and `undefined`, so
// the false branch of `!r && r !== 0` (truthy, or zero) is `number`. The
// not-equal side of `r !== 0` keeps `undefined`.

declare const cols: { [k: number]: { w?: number } | undefined };
function takeN(n: number): number { return n; }
export function okTruthyOrZero(c: number, dflt: number) {
    let result = cols[c]?.w;
    if (!result && result !== 0) {
        result = dflt;
    }
    return takeN(result);
}
export function okEqual(r: number | undefined) {
    if (r === 0) return takeN(r);
    if (r == -1) return takeN(r);
    return 0;
}
export function badNotEqual(r: number | undefined) {
    if (r !== 0) return takeN(r);
    return 0;
}
