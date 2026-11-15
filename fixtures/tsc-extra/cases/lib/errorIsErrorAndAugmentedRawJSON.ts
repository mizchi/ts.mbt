// @strict: true
// @target: esnext

// ES2026 lib: `Error.isError` narrows its argument; a `declare global`
// augmentation of `RawJSON` merges with the lib declaration.

export {};
declare const v: unknown;
function okIsError() { if (Error.isError(v)) { const m: string = v.message; return m } return "" }
function badIsError() { if (Error.isError(v)) { const n: number = v.message; return n } return 0 }
declare global { interface RawJSON { f?(): string } }
function okRaw(x: RawJSON): string { return x.rawJSON }
interface Mine { a: number }
function badMine(m: Mine) { return m.nope }
