// @strict: true
// @target: esnext

// A lib generic written with its type arguments is compared by them: a
// `Set<string>` is not a `Set<number>`, nor a `ReadonlySet<number>`, and an
// `Array<string>` is not a `number[]`. The matching arguments are legal, and
// a mutable collection is its readonly view.

declare const s: Set<string>;
declare const m: Map<string, number>;
declare const a: Array<string>;
declare const p: Promise<string>;

export const okSet: ReadonlySet<string> = s;
export const okMap: ReadonlyMap<string, number> = m;
export const okArray: string[] = a;
export const okPromise: Promise<string> = p;

export const badSet: Set<number> = s;
export const badReadonlySet: ReadonlySet<number> = s;
export const badMap: Map<string, string> = m;
export const badReadonlyMap: ReadonlyMap<string, string> = m;
export const badArray: number[] = a;
export const badPromise: Promise<number> = p;
