// @strict: true
// @target: esnext

// effect: the then-branch of `||`, a conditional expression's branches under
// the condition's narrowing, an index signature keyed by `PropertyKey`, and
// bigint arithmetic.

interface O { readonly a?: string | undefined; readonly b?: string | undefined }
function okOr(o?: O) { if (o?.a !== undefined || o?.b !== undefined) { return o.a ?? o.b } return "" }
function badOr(o: O | undefined, n: string | number) { if (typeof n === "string" || o === undefined) { return o.a } return "" }
function okCond(capacity: number | { readonly capacity: number; readonly replay?: number | undefined }) {
  const options = typeof capacity === "number" ? { capacity } : capacity
  return options.capacity
}
function okIndex(x: { [k: PropertyKey]: unknown }) { return x.anything }
function okBig(num: bigint, b: boolean) { num = b ? -num : num; const q: bigint = num / num; return q }
function okBigCtor() { const d = BigInt(1024); const q: bigint = d ** BigInt(2); return q }
function badBig() { const s: string = BigInt(1); return s }
