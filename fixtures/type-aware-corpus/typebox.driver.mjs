// TypeBox: schema construction across the type constructors, and the
// derived-pattern paths in particular.
//
// This driver exists because of two bugs that each made the bundle
// unloadable, and the second is the reason the checks below look at
// VALUES rather than just at absence of a throw.
//
//   * `Array.from({ length: 256 }).map(…)` in `system/hashing/hash.ts`
//     was compiled to `[...{ length: 256 }].map(…)`. `Array.from` takes
//     an array-LIKE; a spread needs an ITERABLE.
//   * `types/record.ts` was initialized AFTER `indexed/from_object.ts`,
//     whose top level does `new RegExp(IntegerKey)` — a TDZ error from a
//     module order that did not match ESM's.
//
// `IntegerKey` is a string pattern, so a wrong initialization order that
// somehow produced `undefined` instead of throwing would still build a
// schema; what it would not do is put the right regex in
// `patternProperties`. So `Record(Integer(), …)` is checked for its
// actual pattern, and the rest of the surface is checked for the JSON
// Schema it emits.
import * as TB from "./target.mjs";

const out = [];
const {
  Type,
  Object: TObject,
  Array: TArray,
  Record,
  Union,
  Intersect,
  Literal,
  Optional,
  Integer,
  Number: TNumber,
  String: TString,
  Boolean: TBoolean,
  Tuple,
  Index,
  Partial,
  Required,
  Pick,
  Omit,
  KeyOf,
  Ref,
  Cyclic,
  Module,
  TemplateLiteral,
} = TB;

// The pattern `IntegerKey` produces, read back out of a Record. This is
// the exact binding the TDZ bug was about.
out.push(JSON.stringify(Record(Integer(), TNumber())));
out.push(JSON.stringify(Record(TNumber(), TString())));
out.push(JSON.stringify(Record(TString(), TBoolean())));

const T = TObject({
  id: Integer(),
  name: TString({ minLength: 1, maxLength: 32 }),
  score: TNumber({ minimum: 0 }),
  tags: TArray(TString(), { minItems: 1 }),
  meta: Optional(Record(Integer(), TNumber())),
  pair: Tuple([TString(), Integer()]),
});
out.push(JSON.stringify(T));

// The mapping / indexing combinators, which read the object's key set.
out.push(JSON.stringify(KeyOf(T)));
out.push(JSON.stringify(Index(T, ["name"])));
out.push(JSON.stringify(Pick(T, ["id", "name"])));
out.push(JSON.stringify(Omit(T, ["meta", "pair", "tags", "score"])));
out.push(JSON.stringify(Partial(TObject({ a: Integer() }))));
out.push(JSON.stringify(Required(TObject({ a: Optional(Integer()) }))));

// Unions, intersections and literals — the discriminated-union shape the
// tag-driven passes are built for.
const Shape = Union([
  TObject({ kind: Literal("circle"), r: TNumber() }),
  TObject({ kind: Literal("rect"), w: TNumber(), h: TNumber() }),
]);
out.push(JSON.stringify(Shape));
out.push(JSON.stringify(Intersect([TObject({ a: Integer() }), TObject({ b: TString() })])));
out.push(JSON.stringify(TemplateLiteral("prefix${string}")));

// Recursion and references, which build their own `$defs` tables.
const nodeDefs = {
  Node: TObject({ value: Integer(), next: Optional(Ref("Node")) }),
};
out.push(JSON.stringify(Cyclic(nodeDefs, "Node")));
out.push(JSON.stringify(Module(nodeDefs)));
out.push(JSON.stringify(Ref("Node")));

// The `Type` namespace object is assembled separately from the direct
// exports, so exercise the same constructors through it — a namespace
// built from the wrong table would diverge here and nowhere else.
out.push(JSON.stringify(Type.Record(Type.Integer(), Type.Number())));
out.push(JSON.stringify(Type.Object({ a: Type.Integer(), b: Type.Optional(Type.String()) })));
out.push(Object.keys(Type).length > 50);

console.log(JSON.stringify(out, null, 1));
