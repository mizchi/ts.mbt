// @strict: true
// @target: esnext

// `keyof` a tuple, `infer N extends number` inside a template literal (`"01"`
// is not a canonical spelling and infers `number`), and that inference used
// as a method type parameter's bound over the receiver's tuple.

type K1 = keyof [string, number];
function okTupleKey() { const k: K1 = "0"; const m: K1 = "length"; }
function badTupleKey() { const k: K1 = "5"; }
type IndexFor<S extends string> = S extends `${infer N extends number}` ? N : never;
type I1 = IndexFor<"0" | "1" | "length">;
type I2 = IndexFor<"01">;
function okIndexFor() { const i: I1 = 1; const j: I2 = 7; }
function badIndexFor() { const i: I1 = 2; }
type IndicesOf<T> = IndexFor<Extract<keyof T, string>>;
interface Def { readonly name: string }
interface M<TDef extends readonly Def[]> { gi<I extends IndicesOf<TDef>>(index: I): void; }
function okMethodBound(p: M<[{ name: "x" }, { name: "y" }]>) { p.gi(0); p.gi(1); }
function badMethodBound(p: M<[{ name: "x" }, { name: "y" }]>) { p.gi(2); }
