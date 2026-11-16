// Namespace objects, function + namespace merges, `export =` modules and
// qualified names written inside a declaration file: the value shapes an
// application reaches through a package's types. Every expected list below
// is what tsc reports on the same files, probed one project per case.

///|
/// `import * as D` of a declaration file types each member as written; a
/// `.ts` source's member stays `any`, since its unannotated exports are the
/// parser's coarse inference.
test "namespace import: a declaration file's members are typed" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/d.d.ts", "export declare const k: string;\nexport declare function f(n: number): string;",
        ),
        (
          "/src/s.ts", "export const k = \"x\";\nexport const lit = \"x\" as const;",
        ),
        (
          "/src/main.ts", "import * as D from \"./d\";\nimport * as T from \"./s\";\nexport const bad1: number = D.k;\nexport const bad2: number = D.f(1);\nexport const ok1: string = D.k;\nexport const t: string = T.k;\nexport const t2: \"x\" = T.lit;",
        ),
      ],
      [
        ("/src/main.ts", "./d", "/src/d.d.ts"),
        ("/src/main.ts", "./s", "/src/s.ts"),
      ],
    ),
    [
      "top-level > binding `bad1` init :: expected `number` but got `string`", "top-level > binding `bad2` init :: expected `number` but got `string`",
    ],
  )
}

///|
/// A NAMED import can be a namespace too: `export * as N` (effect's
/// `index.ts`) and an exported `import * as Z` binding (zod's `z`).
test "namespace import: named bindings of a namespace export" {
  assert_eq(
    graph_messages(
      [
        ("/src/inner.d.ts", "export declare const k: string;"),
        (
          "/src/idx.d.ts", "export * as N from \"./inner\";\nimport * as Z from \"./inner\";\nexport { Z };",
        ),
        (
          "/src/main.ts", "import { N, Z } from \"./idx\";\nexport const bad1: number = N.k;\nexport const bad2: number = Z.k;\nexport const ok: string = N.k + Z.k;",
        ),
      ],
      [
        ("/src/idx.d.ts", "./inner", "/src/inner.d.ts"),
        ("/src/main.ts", "./idx", "/src/idx.d.ts"),
      ],
    ),
    [
      "top-level > binding `bad1` init :: expected `number` but got `string`", "top-level > binding `bad2` init :: expected `number` but got `string`",
    ],
  )
}

///|
/// An overload set and a callable object with only call signatures
/// (effect's `dual` APIs) are each one field per signature, which is the
/// shape the method-call path resolves overloads in: every arity is legal
/// and the selected signature's return is what the call has. Kept whole,
/// the call was judged by nothing and both `bad` lines were silent.
test "namespace import: overloaded and callable-object members" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/g.d.ts", "export declare function g(a: string): string;\nexport declare function g(a: number, b: number): number;\nexport declare const h: { (a: string): string; (a: number, b: number): number };\nexport declare const equals: { <B>(that: B): <A>(self: A) => boolean; <A, B>(self: A, that: B): boolean };",
        ),
        (
          "/src/main.ts", "import * as N from \"./g\";\nexport const ok1: string = N.g(\"x\");\nexport const ok2: number = N.g(1, 2);\nexport const bad1: number = N.g(\"x\");\nexport const ok3: string = N.h(\"x\");\nexport const ok4: number = N.h(1, 2);\nexport const bad2: string = N.h(1, 2);\nexport const ok5: boolean = N.equals(1, 2);\nexport const ok6 = N.equals(1);",
        ),
      ],
      [("/src/main.ts", "./g", "/src/g.d.ts")],
    ),
    [
      "top-level > binding `bad1` init :: expected `number` but got `string`", "top-level > binding `bad2` init :: expected `string` but got `number`",
    ],
  )
}

///|
/// A function merged with a namespace is both callable and has the
/// namespace's members (preact's `h`, drizzle's `sql`). A type-only
/// namespace beside a `const` contributes no value, so the `const` keeps
/// its type.
test "namespace merge: function and namespace, const and type-only namespace" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/h.d.ts", "export declare function h(tag: string): number;\nexport declare namespace h { const x: string; }",
        ),
        (
          "/src/f.d.ts", "export declare const Foo: { a: number };\nexport declare namespace Foo { type T = string; }",
        ),
        (
          "/src/main.ts", "import { h } from \"./h\";\nimport { Foo } from \"./f\";\nexport const bad1: string = h;\nexport const ok1: number = h(\"div\");\nexport const ok2: string = h.x;\nexport const bad2: number = h.x;\nexport const ok3: number = Foo.a;\nexport const bad3: string = Foo.a;",
        ),
      ],
      [
        ("/src/main.ts", "./h", "/src/h.d.ts"),
        ("/src/main.ts", "./f", "/src/f.d.ts"),
      ],
    ),
    [
      "top-level > binding `bad1` init :: expected `string` but got `{ <call>: (string) => number; x: string }`",
      "top-level > binding `bad2` init :: expected `number` but got `string`", "top-level > binding `bad3` init :: expected `string` but got `number`",
    ],
  )
}

///|
/// `export = R` over a `declare namespace R`: `import * as R` and a named
/// import of a member both read the assigned value (`esModuleInterop`).
test "export assignment: namespace and named imports read the assigned value" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/r.d.ts", "declare namespace R { const version: string; function make(n: number): string; }\nexport = R;",
        ),
        (
          "/src/main.ts", "import * as R from \"./r\";\nimport { version } from \"./r\";\nexport const bad1: number = R.version;\nexport const bad2: number = version;\nexport const ok: string = R.make(1);",
        ),
      ],
      [("/src/main.ts", "./r", "/src/r.d.ts")],
    ),
    [
      "top-level > binding `bad1` init :: expected `number` but got `string`", "top-level > binding `bad2` init :: expected `number` but got `string`",
    ],
  )
}

///|
/// A qualified name written inside a declaration file (`core.P`, zod's
/// spelling throughout) resolves in that file's own terms, so the
/// importer can judge the value. It abstained unless the importer bound
/// the same `core` itself.
test "declaration file: its own qualified names resolve for an importer" {
  assert_eq(
    graph_messages(
      [
        ("/src/core.d.ts", "export interface P { x: number }"),
        (
          "/src/lib.d.ts", "import * as core from \"./core\";\nexport declare function mk(p: core.P): core.P;",
        ),
        (
          "/src/main.ts", "import { mk } from \"./lib\";\nexport const ok: number = mk({ x: 1 }).x;\nexport const bad1: string = mk({ x: 1 }).x;\nexport const bad2: number = mk;",
        ),
      ],
      [
        ("/src/lib.d.ts", "./core", "/src/core.d.ts"),
        ("/src/main.ts", "./lib", "/src/lib.d.ts"),
      ],
    ),
    [
      "top-level > binding `bad1` init :: expected `string` but got `number`", "top-level > binding `bad2` init :: expected `number` but got `(P) => P`",
    ],
  )
}

///|
/// An instance of a generic interface is an object, so no instantiation
/// is assignable to a primitive. A THENABLE is excluded: `await q` of a
/// custom thenable is legal, and it is inferred as the thenable here.
test "a generic interface instance is not a primitive" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/main.ts", "interface Box<A> { v: A }\ndeclare const b: Box<number>;\nexport const bad1: number = b;\nexport const bad2: string | undefined = b;\nexport const ok1: Box<number> = b;\nexport const ok2: { v: number } = b;\ndeclare function useNum(n: number): void;\nuseNum(b);\ninterface Q<A> { then(f: (a: A) => void): void; where(x: string): Q<A> }\ndeclare const q: Q<number>;\nexport async function g() {\n  const n: number = await q;\n  const m: number = await q.where(\"x\");\n  return n + m;\n}",
        ),
      ],
      [],
    ),
    [
      "top-level > binding `bad1` init :: type `Box<number>` is not assignable to type `number`",
      "top-level > binding `bad2` init :: type `Box<number>` is not assignable to type `string | undefined`",
      "top-level > call `useNum` arg[0] :: type `Box<number>` is not assignable to type `number`",
    ],
  )
}

///|
/// A generic guard over a generic ALIAS union (`Result<A, E> = Success<A>
/// | Failure<E>`, the Option / Result / Either shape) narrows both
/// branches, called by name or through a namespace. The else branch
/// narrowed nothing before: the alias reached the narrowing as one opaque
/// member, and through a namespace the target was the qualified
/// `R.Failure<any>` against a source that expands to `Failure<string>`.
/// Both `r.success` reads were reported on code tsc accepts.
test "a generic guard narrows a generic alias union in both branches" {
  let res = (
    "/src/res.d.ts", "export interface Success<A> { readonly _tag: \"Success\"; readonly success: A }\nexport interface Failure<E> { readonly _tag: \"Failure\"; readonly failure: E }\nexport type Result<A, E> = Success<A> | Failure<E>;\nexport declare const isFailure: <A, E>(self: Result<A, E>) => self is Failure<E>;\nexport declare const isSuccess: <A, E>(self: Result<A, E>) => self is Success<A>;",
  )
  assert_eq(
    graph_messages(
      [
        res,
        (
          "/src/main.ts", "import * as R from \"./res\";\nexport function f(r: R.Result<number, string>): number {\n  if (R.isFailure(r)) {\n    return r.failure.length;\n  }\n  return r.success;\n}\nexport function g(r: R.Result<number, string>): number {\n  return R.isSuccess(r) ? r.success : r.failure.length;\n}",
        ),
      ],
      [("/src/main.ts", "./res", "/src/res.d.ts")],
    ),
    [],
  )
  assert_eq(
    graph_messages(
      [
        res,
        (
          "/src/main.ts", "import { isFailure, type Result } from \"./res\";\nexport function f(r: Result<number, string>): number {\n  if (isFailure(r)) {\n    return r.failure.length;\n  }\n  return r.success;\n}",
        ),
      ],
      [("/src/main.ts", "./res", "/src/res.d.ts")],
    ),
    [],
  )
}

///|
/// `export default function (): T;` — an anonymous default with no body,
/// which a declaration file may write (zod's ESM locale files) — failed to
/// parse, and the parse error took every importer of the file with it.
/// Its value is not modelled yet; the named spelling is.
test "declaration file: a bodiless default function parses" {
  assert_eq(
    graph_messages(
      [
        ("/src/anon.d.ts", "export default function (): { n: number };"),
        ("/src/named.d.ts", "export default function f(): { n: number };"),
        (
          "/src/main.ts", "import a from \"./anon\";\nimport f from \"./named\";\nexport const ok = a;\nexport const bad: string = f().n;",
        ),
      ],
      [
        ("/src/main.ts", "./anon", "/src/anon.d.ts"),
        ("/src/main.ts", "./named", "/src/named.d.ts"),
      ],
    ),
    ["top-level > binding `bad` init :: expected `string` but got `number`"],
  )
}

///|
/// An alias to a union of CONDITIONAL types (effect's `WrapKey<A> = (A
/// extends AesKw ? Key<A> : never) | …`) is not expanded for a guard: its
/// members are undecided, and narrowing them made the guarded branch the
/// conditionals themselves, so `wrapKey.algorithm` read as missing there.
test "a guard does not expand an alias to undecided conditionals" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/main.ts", "type AesKw = \"A-KW\";\ntype RsaOaep = \"RSA-OAEP\";\ntype Algorithm = AesKw | RsaOaep;\ninterface Key<out A extends AesKw = AesKw> { readonly k: 1; readonly algorithm: A }\ninterface PublicKey<out A extends RsaOaep = RsaOaep> { readonly p: 1; readonly algorithm: A }\ntype WrapKey<A extends Algorithm = Algorithm> =\n  | (A extends AesKw ? Key<A> : never)\n  | (A extends RsaOaep ? PublicKey<A> : never)\ndeclare const isKey: (u: unknown) => u is Key;\nexport function f(wrapKey: WrapKey): string {\n  if (isKey(wrapKey)) {\n    return wrapKey.algorithm;\n  }\n  return \"rsa\";\n}",
        ),
      ],
      [],
    ),
    [],
  )
}

///|
/// A guard whose subject is not its first parameter narrows the argument
/// in the subject's position, through a namespace, an object method and a
/// named import alike. A callable type has no parameter names, and every
/// one of those routes narrowed the FIRST argument: `options` became
/// `string`, so `options.enabled` was reported, and `value` kept
/// `unknown`, so `value.length` was too.
test "a guard narrows the argument in its subject's position" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/g.d.ts", "export declare function isText(options: { enabled: boolean }, value: unknown): value is string;",
        ),
        (
          "/src/main.ts", "import * as G from \"./g\";\nimport { isText } from \"./g\";\ndeclare const guards: { isText(options: { enabled: boolean }, value: unknown): value is string };\nexport function f(options: { enabled: boolean }, value: unknown): boolean {\n  if (G.isText(options, value)) {\n    return options.enabled && value.length > 0;\n  }\n  if (guards.isText(options, value)) {\n    return options.enabled && value.length > 0;\n  }\n  if (isText(options, value)) {\n    return options.enabled && value.length > 0;\n  }\n  return false;\n}",
        ),
      ],
      [("/src/main.ts", "./g", "/src/g.d.ts")],
    ),
    [],
  )
}

///|
/// A union-typed VALUE of an `export =` namespace is an ordinary member. It
/// was read as absent, which the library API reports as "no value export".
/// An explicit re-export also wins over `export *`, as for types: `N` here
/// is `b`'s, and `a`'s was answering first.
test "export assignment union members and re-export precedence" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/c.d.ts", "declare namespace Config { const mode: \"dev\" | \"prod\"; }\nexport = Config;",
        ),
        ("/src/a.d.ts", "export declare const k: string;"),
        ("/src/b.d.ts", "export declare const k: number;"),
        ("/src/hasN.d.ts", "export * as N from \"./a\";"),
        (
          "/src/idx.d.ts", "export * from \"./hasN\";\nexport * as N from \"./b\";",
        ),
        (
          "/src/main.ts", "import { mode } from \"./c\";\nimport { N } from \"./idx\";\nexport const m: \"dev\" | \"prod\" = mode;\nexport const bad1: number = mode;\nexport const s: number = N.k;\nexport const bad2: string = N.k;",
        ),
      ],
      [
        ("/src/main.ts", "./c", "/src/c.d.ts"),
        ("/src/main.ts", "./idx", "/src/idx.d.ts"),
        ("/src/idx.d.ts", "./hasN", "/src/hasN.d.ts"),
        ("/src/idx.d.ts", "./b", "/src/b.d.ts"),
        ("/src/hasN.d.ts", "./a", "/src/a.d.ts"),
      ],
    ),
    [
      "top-level > binding `bad1` init :: expected `number` but got `\"dev\" (string) | \"prod\" (string)`",
      "top-level > binding `bad2` init :: expected `string` but got `number`",
    ],
  )
}

///|
/// The first parameter stays the subject whenever it can be one: an
/// unannotated `allowZero = true` reads as `any` and also accepts the
/// target, and abstaining there lost univer's narrowing of `ah`.
test "a guard's first parameter stays its subject when it can be" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/dim.ts", "export function isValidSheetDimension(value: unknown, allowZero = true): value is number {\n  return typeof value === \"number\" && (allowZero || value !== 0);\n}",
        ),
        (
          "/src/main.ts", "import { isValidSheetDimension } from \"./dim\";\nexport function h(ah: number | undefined): number {\n  let height: number = 0;\n  if (isValidSheetDimension(ah, false)) {\n    height += ah;\n  }\n  return height;\n}",
        ),
      ],
      [("/src/main.ts", "./dim", "/src/dim.ts")],
    ),
    [],
  )
}

///|
/// When both parameters accept the target, their types cannot tell the
/// subject apart, so the callable type records its POSITION where it is
/// built from named parameters (`@ast.index_predicate_subject`): an object
/// type's method, a function type, and a declaration's value reached by
/// name or through a namespace. `value.toUpperCase()` was reported in all
/// four, with `first` narrowed instead.
test "a guard's recorded subject position decides an ambiguous call" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/g.d.ts", "export declare function isText2(first: unknown, value: unknown): value is string;",
        ),
        (
          "/src/main.ts", "import * as G from \"./g\";\nimport { isText2 } from \"./g\";\ndeclare const guards: { isText(first: unknown, value: unknown): value is string };\ndeclare const fnType: (first: unknown, value: unknown) => value is string;\nexport function check(first: unknown, value: unknown): string {\n  if (guards.isText(first, value)) {\n    return value.toUpperCase();\n  }\n  if (fnType(first, value)) {\n    return value.toUpperCase();\n  }\n  if (isText2(first, value)) {\n    return value.toUpperCase();\n  }\n  if (G.isText2(first, value)) {\n    return value.toUpperCase();\n  }\n  return \"\";\n}",
        ),
      ],
      [("/src/main.ts", "./g", "/src/g.d.ts")],
    ),
    [],
  )
}

///|
/// A first parameter typed through an alias of `unknown` is still the
/// subject: read raw, `Input` accepted nothing, the second parameter
/// accepted nothing either, and narrowing was skipped.
test "a guard's aliased first parameter stays its subject" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/main.ts", "type Input = unknown;\ndeclare const guards: { isText(value: Input, flag: boolean): value is string; isText2(value: Input, other: unknown): value is string };\nexport function f(value: Input, other: unknown): string {\n  if (guards.isText(value, true)) {\n    return value.toUpperCase();\n  }\n  if (guards.isText2(value, other)) {\n    return value.toUpperCase();\n  }\n  return \"\";\n}\ninterface Wrapper<T> { w: T }\ninterface Box<T> extends Wrapper<T> { b: T }\ndeclare const g: { isBox<T>(x: Wrapper<T>, flag: boolean): x is Box<T> };\nexport function f3(x: Wrapper<number>): number {\n  if (g.isBox(x, true)) {\n    return x.b;\n  }\n  return 0;\n}",
        ),
      ],
      [],
    ),
    [],
  )
}

///|
/// When the relation proves no parameter accepts the target, the FIRST
/// parameter stays the subject. `{}` against `string` and an alias `P`
/// against `P & { q: string }` are both legal predicates in tsc, and
/// neither is provable here, so narrowing nothing would report the
/// then-branch reads.
test "a guard whose subject the relation cannot prove keeps the first parameter" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/main.ts", "declare const g: { isS(x: {}, flag: boolean): x is string };\nexport function f(x: {}): number {\n  if (g.isS(x, true)) {\n    return x.length;\n  }\n  return 0;\n}\ntype P = { a: number };\ntype Q = P & { q: string };\ndeclare const h: { isQ(x: P, flag: boolean): x is Q };\nexport function f2(x: P): string {\n  if (h.isQ(x, true)) {\n    return x.q;\n  }\n  return \"\";\n}",
        ),
      ],
      [],
    ),
    [],
  )
}

///|
/// A member of the narrowed alias union that is ITSELF an alias is
/// expanded before the keep / remove tests. `Text<string>` read as a name
/// the relation could not see was `string`, so the else branch of
/// `isS(value)` kept it and `const n: number = value` was reported. A
/// plain `string | number` narrows as it always did.
test "a guard over an alias union whose member is an alias narrows both branches" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/main.ts", "type Text<T> = T;\ntype Choice<T> = Text<T> | number;\ndeclare function isS(v: unknown): v is string;\nexport function f(value: Choice<string>): number {\n  if (!isS(value)) {\n    const n: number = value;\n    return n;\n  }\n  const s: string = value;\n  return s.length;\n}\nexport function g(value: string | number): number {\n  if (!isS(value)) {\n    const n: number = value;\n    return n;\n  }\n  const s: string = value;\n  return s.length;\n}",
        ),
      ],
      [],
    ),
    [],
  )
}

///|
/// `call` infers its result, so a predicate does not survive it: tsc
/// narrows NEITHER argument of `g.call(null, first, value)`. The predicate
/// used to stay on the signature `call` builds, and its recorded subject
/// position, 1, then named `first` once `thisArg` was prepended.
test "a guard called through `call` narrows nothing" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/main.ts", "declare const g: (first: unknown, value: unknown) => value is string;\nexport function f(first: unknown, value: unknown): string {\n  if (g.call(null, first, value)) {\n    const a: string = value;\n    const b: string = first;\n    return a + b;\n  }\n  return \"\";\n}",
        ),
      ],
      [],
    ),
    [
      "function f > binding `a` init :: expected `string` but got `unknown`", "function f > binding `b` init :: expected `string` but got `unknown`",
    ],
  )
}

///|
/// The `var` a namespace block is lowered to and a written `declare const
/// N: any` are the same `values` entry, so the lowering is dropped by
/// COUNT, one per block, and a real `any` value beside a type-only
/// namespace survives. Read by shape, the written value was dropped too.
test "a namespace's lowered var is told from a written any value by count" {
  fn names(source : String) -> Array[String] {
    let parser = @parser.Parser::from_source_with_jsx(source, false)
    parser.mark_declaration_file()
    let m = parser.parse_module() catch { e => abort("\{e}") }
    declared_values(m).map(fn(v) { v.name })
  }

  assert_eq(names("export declare namespace Foo { interface T {} }"), [])
  assert_eq(
    names(
      "export declare const Foo: any;\nexport declare namespace Foo { interface T {} }",
    ),
    ["Foo"],
  )
  assert_eq(
    names(
      "export declare const Foo: any;\nexport declare namespace Foo { interface T {} }\nexport declare namespace Foo { interface U {} }",
    ),
    ["Foo"],
  )
  assert_eq(
    names(
      "export declare const Foo: number;\nexport declare namespace Foo { interface T {} }",
    ),
    ["Foo"],
  )
}

///|
/// A namespace holding only a nested TYPE namespace has no value, so a
/// `declare const` of the same name keeps its type. The nested
/// namespace's lowered `var` counted as a value, and the namespace's
/// empty object shadowed `N: number`.
test "a namespace of nested type namespaces does not shadow a const" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/n.d.ts", "export declare const N: number;\nexport declare namespace N { namespace Types { interface I {} } }",
        ),
        (
          "/src/main.ts", "import { N } from \"./n\";\nexport const ok: number = N;\nexport const bad: string = N;",
        ),
      ],
      [("/src/main.ts", "./n", "/src/n.d.ts")],
    ),
    ["top-level > binding `bad` init :: expected `string` but got `number`"],
  )
}

///|
/// A declaration file's NAMED import of a namespace export (`import {
/// Models } from "./barrel"` of `export * as Models`) resolves its
/// `Models.I` for an importer too.
test "declaration file: a named namespace import's qualified names resolve" {
  assert_eq(
    graph_messages(
      [
        ("/src/models.d.ts", "export interface I { x: number }"),
        ("/src/barrel.d.ts", "export * as Models from \"./models\";"),
        (
          "/src/lib.d.ts", "import { Models } from \"./barrel\";\nexport declare function mk(): Models.I;",
        ),
        (
          "/src/main.ts", "import { mk } from \"./lib\";\nexport const ok: number = mk().x;\nexport const bad: string = mk().x;",
        ),
      ],
      [
        ("/src/barrel.d.ts", "./models", "/src/models.d.ts"),
        ("/src/lib.d.ts", "./barrel", "/src/barrel.d.ts"),
        ("/src/main.ts", "./lib", "/src/lib.d.ts"),
      ],
    ),
    ["top-level > binding `bad` init :: expected `string` but got `number`"],
  )
}
