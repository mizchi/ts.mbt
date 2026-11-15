// @strict: true
// @target: esnext

// An optional method-typed property contextually types an object-literal
// method; a generic interface method's arguments are checked against its
// instantiated parameters; an overload taking `Object` accepts a number.

interface Opts { map?: (i: { num: number }) => void }
declare function use(o: Opts): void;
function badOptionalCallback() { use({ map(i) { i.nonexistent; } }); }
function okOptionalCallback() { use({ map: (i) => { i.num.toFixed(); } }); }
interface Store<T> { get<K extends keyof T>(k: K): T[K]; put<K extends string>(k: K): void }
function okStoreGet(st: Store<{ a: 1 }>) { st.get("a"); st.put("x"); }
function badStoreGet(st: Store<{ a: 1 }>) { st.get("b"); }
function badStorePut(st: Store<{ a: 1 }>) { st.put(1); }
interface P<T> { then<U>(cb: (x: T) => P<U>): P<U> }
declare function tfn(n: number): P<number>;
declare function tstr(s: string): P<string>;
function okThen(np: P<number>) { np.then(tfn); }
function badThen(np: P<number>) { np.then(tstr); }
declare function takesObject(x: Object): string;
declare function takesObject(x: number): number;
function badObjectOverload() { const r: number = takesObject(1); }
function okObjectOverload() { const r: string = takesObject(1); }
