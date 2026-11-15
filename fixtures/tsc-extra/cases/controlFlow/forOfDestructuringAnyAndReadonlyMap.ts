// @strict: true
// @target: esnext

// `for (const [k, v] of x)` over `any` and over a `ReadonlyMap`.

declare const m: ReadonlyMap<string, any>
function okAny(x: any): void { for (const [key, value] of x) { m.has(key) } }
function okMap(r: ReadonlyMap<string, number>) { for (const [k, v] of r) { const s: string = k; const n: number = v } }
function badMap(r: ReadonlyMap<string, number>) { for (const [k, v] of r) { const s: number = k } }
