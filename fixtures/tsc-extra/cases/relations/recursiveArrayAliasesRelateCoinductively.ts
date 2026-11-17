// @strict: true
// @target: esnext

// Two recursive array aliases are related coinductively: comparing `A[]`
// with `B[]` compares `A` with `B`, which unwrap to `A[]` and `B[]` again,
// and a pair already being compared is assumed related. A relation that
// walks the elements without that assumption never terminates. A pair
// that bottoms out in something else still fails where it does.

type A = A[];
type B = B[];
declare const a: A[];

function okTwinAlias() { const b: B[] = a; }
function okSameAlias() { const x: A = a; }
function badElementMeetsString() { const s: string[] = a; }
function badNestedElementMeetsNumber() { const n: number[][] = a; }
