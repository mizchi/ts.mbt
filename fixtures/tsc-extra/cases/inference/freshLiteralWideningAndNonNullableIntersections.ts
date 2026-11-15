// @strict: true
// @target: esnext

// A FRESH literal candidate widens (`useState("")` binds `string`) unless
// it is the bare return type; `NonNullable<T>` vs `T & {}`; excess and
// missing properties against an intersection; nested `Extract`.

declare function useState<S>(init: S): [S, (s: S) => void];
declare function box<T>(x: T): { get(): T; set(v: T): void };
declare function id<T>(x: T): T;
declare function nest<T>(x: T[]): { v: T };
function okUseState() { const [v, setV] = useState(""); setV("a"); }
function okUseStateVar() { const initial = ""; const [v, setV] = useState(initial); setV("b"); }
function okBox() { const b = box("a"); b.set("b"); }
function okLetFromConst() { const a = "x"; let b = a; b = "y"; }
function badIdKeepsLiteral() { const s: "q" = id("r"); }
function okIdKeepsLiteral() { const s: "q" = id("q"); }
function okNestNotFresh(arr: "z"[]) { const n: "z" = nest(arr).v; }
function badNonNullable<T>(x: T, y: NonNullable<T>) { x = y; y = x; }
function badEmptyIntersection<T>(x: T, y: T & {}) { y = x; }
function okNonNullableBack<T>(x: T, y: NonNullable<T>) { x = y; }
function okBothNonNullable<T>(x: NonNullable<T>, y: NonNullable<T>) { y = x; }
type A = { a: number };
type B = { b: string };
function badExcess() { let ab: A & B = { a: 1, b: "x", c: 2 }; }
function badMissing() { let ab: A & B = { a: 1 }; }
function okExact() { let ab: A & B = { a: 1, b: "x" }; }
function okOptional() { let ab: A & { b?: string } = { a: 1 }; }
function okIndexPart() { let ab: A & { [k: string]: number } = { a: 1, zz: 2 }; }
type Foo = { foo: string };
type Bar = { bar: string };
declare function fooBar(x: { foo: string, bar: string }): void;
declare function fooBat(x: { foo: string, bat: string }): void;
type Extract2<T, U, V> = T extends U ? T extends V ? T : never : never;
function okExtract<T>(x: Extract<Extract<T, Foo>, Bar>, y: Extract<T, Foo & Bar>, z: Extract2<T, Foo, Bar>) { fooBar(x); fooBar(y); fooBar(z); }
function badExtractNested<T>(x: Extract<Extract<T, Foo>, Bar>) { fooBat(x); }
function badExtractIntersection<T>(y: Extract<T, Foo & Bar>) { fooBat(y); }
function badExtractAlias<T>(z: Extract2<T, Foo, Bar>) { fooBat(z); }
