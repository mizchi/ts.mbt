// @strict: true
// @target: esnext

// An overload set passed where a single signature is expected is checked
// against the matching overload; `Promise<string>` where `string` is
// expected (a forgotten `await`) is TS2322 / TS2345.

interface P<T> { then<U>(cb: (x: T) => P<U>): P<U> }
declare function tf2(n: number): P<number>;
declare function tf2(s: string): P<string>;
declare function tf3(n: number): number;
declare function tf3(s: string): number;
declare function single(n: number): P<number>;
function badOverloadArg(np: P<number>) { np.then(tf2); }
function okSingleArg(np: P<number>) { np.then(single); }
function badOverloadValue() { const cb: (x: boolean) => number = tf3; }
function okOverloadValue() { const cb: (x: number) => number = tf3; }
declare function fetchName(): Promise<string>;
function takesString(s: string) {}
function badMissingAwait() { const s: string = fetchName(); }
function badMissingAwaitArg() { takesString(fetchName()); }
async function okAwaited() { const s: string = await fetchName(); }
async function okAsyncReturn(): Promise<string> { return fetchName(); }
function okUnionTarget() { const s: string | Promise<string> = fetchName(); }
function okRegexArg() { "abc".replace(/b/g, ""); }
