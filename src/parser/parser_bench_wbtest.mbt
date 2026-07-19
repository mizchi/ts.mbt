// Parser throughput benchmarks. Run with `moon bench --target native`.
//
// Each `test` here uses the `(it : @bench.T)` signature so the moonbit
// benchmarking harness times only the body of `it.bench(fn() { ... })`,
// not the setup code that builds the fixture source.

///|
let small_source : String =
  #|interface User {
  #|  id: number;
  #|  name: string;
  #|  email?: string;
  #|  readonly createdAt: Date;
  #|}
  #|type UserId = User["id"];
  #|type PartialUser = Partial<User>;
  #|function createUser(name: string, email?: string): User;
  #|const MAX_USERS: number;

///|
let medium_source : String =
  #|export interface RequestInit {
  #|  body?: BodyInit | null;
  #|  cache?: RequestCache;
  #|  credentials?: RequestCredentials;
  #|  headers?: HeadersInit;
  #|  integrity?: string;
  #|  keepalive?: boolean;
  #|  method?: string;
  #|  mode?: RequestMode;
  #|  redirect?: RequestRedirect;
  #|  referrer?: string;
  #|  referrerPolicy?: ReferrerPolicy;
  #|  signal?: AbortSignal | null;
  #|  window?: null;
  #|}
  #|export interface Response {
  #|  readonly body: ReadableStream<Uint8Array> | null;
  #|  readonly bodyUsed: boolean;
  #|  readonly headers: Headers;
  #|  readonly ok: boolean;
  #|  readonly redirected: boolean;
  #|  readonly status: number;
  #|  readonly statusText: string;
  #|  readonly type: ResponseType;
  #|  readonly url: string;
  #|  arrayBuffer(): Promise<ArrayBuffer>;
  #|  blob(): Promise<Blob>;
  #|  clone(): Response;
  #|  formData(): Promise<FormData>;
  #|  json(): Promise<unknown>;
  #|  text(): Promise<string>;
  #|}
  #|export class Request {
  #|  constructor(input: RequestInfo | URL, init?: RequestInit);
  #|  readonly body: ReadableStream<Uint8Array> | null;
  #|  readonly bodyUsed: boolean;
  #|  readonly cache: RequestCache;
  #|  readonly credentials: RequestCredentials;
  #|  readonly destination: RequestDestination;
  #|  readonly headers: Headers;
  #|  readonly integrity: string;
  #|  readonly keepalive: boolean;
  #|  readonly method: string;
  #|  readonly mode: RequestMode;
  #|  readonly redirect: RequestRedirect;
  #|  readonly referrer: string;
  #|  readonly referrerPolicy: ReferrerPolicy;
  #|  readonly signal: AbortSignal;
  #|  readonly url: string;
  #|  clone(): Request;
  #|}

///|
let advanced_types_source : String =
  #|type Awaited<T> = T extends null | undefined
  #|  ? T
  #|  : T extends object & { then(onfulfilled: infer F, ...args: infer _): any }
  #|    ? F extends (value: infer V, ...args: infer _) => any
  #|      ? Awaited<V>
  #|      : never
  #|    : T;
  #|type ReturnType<T extends (...args: any) => any> =
  #|  T extends (...args: any) => infer R ? R : any;
  #|type Parameters<T extends (...args: any) => any> =
  #|  T extends (...args: infer P) => any ? P : never;
  #|type Getters<T> = {
  #|  [K in keyof T as `get${Capitalize<K & string>}`]: () => T[K];
  #|};
  #|type DeepReadonly<T> = {
  #|  readonly [K in keyof T]: T[K] extends object ? DeepReadonly<T[K]> : T[K];
  #|};
  #|type Concat<A extends string, B extends string> = `${A}${B}`;
  #|type ConcatN<T extends string[]> = T extends [infer Head extends string, ...infer Tail extends string[]]
  #|  ? `${Head}${ConcatN<Tail>}`
  #|  : "";
  #|type IsArray<T> = T extends readonly unknown[] ? true : false;
  #|type UnionToIntersection<U> =
  #|  (U extends any ? (k: U) => void : never) extends ((k: infer I) => void) ? I : never;
  #|type Tuple<T, N extends number, R extends T[] = []> =
  #|  R['length'] extends N ? R : Tuple<T, N, [...R, T]>;

///|
/// Programmatically build a wide interface declaration with `field_count`
/// readonly/optional properties so that benchmarks can scale to inputs
/// larger than what is convenient to hand-write inline.
fn build_wide_interface(field_count : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("export interface Wide {\n")
  for i in 0..<field_count {
    let n = i.to_string()
    // Cycle through a few field shapes so the lexer/parser exercise more
    // paths than a single repeated form would.
    match i % 4 {
      0 => buf.write_string("  field" + n + ": string;\n")
      1 => buf.write_string("  field" + n + "?: number | null;\n")
      2 =>
        buf.write_string(
          "  readonly field" + n + ": Array<{ id: number; label: string }>;\n",
        )
      _ =>
        buf.write_string(
          "  method" +
          n +
          "(arg: Map<string, number>, opts?: { strict?: boolean }): Promise<boolean>;\n",
        )
    }
  }
  buf.write_string("}\n")
  buf.to_string()
}

///|
let wide_500 : String = build_wide_interface(500)

///|
let wide_2000 : String = build_wide_interface(2000)

///|
/// JSDoc-heavy fixture: every declaration carries a multi-line doc
/// comment with tags, mirroring real `.d.ts` inputs (es5.d.ts is ~60%
/// comments by volume). Tracks the lexer's comment scan +
/// `parse_jsdoc_block` path, which dominated whole-file profiles before
/// the view-based rewrite.
fn build_jsdoc_heavy(decl_count : Int) -> String {
  let buf = StringBuilder::new()
  for i in 0..<decl_count {
    let n = i.to_string()
    buf.write_string("/**\n")
    buf.write_string(
      " * Reads the value of entry " + n + " from the backing store.\n",
    )
    buf.write_string(" * Second description line with more prose text.\n")
    buf.write_string(" * @param key" + n + " - the lookup key\n")
    buf.write_string(" * @param options optional retrieval options\n")
    buf.write_string(" * @returns {Entry" + n + "} the resolved entry\n")
    buf.write_string(" * @deprecated use readEntryV2 instead\n")
    buf.write_string(" */\n")
    buf.write_string(
      "declare function readEntry" +
      n +
      "(key" +
      n +
      ": string, options?: object): Entry" +
      n +
      ";\n",
    )
    buf.write_string("interface Entry" + n + " { value: string }\n")
  }
  buf.to_string()
}

///|
let jsdoc_heavy_300 : String = build_jsdoc_heavy(300)

///|
/// Old-style-cast-heavy fixture: `<Type>expr` casts in expression
/// position trigger the JSX speculation path (scan + nested sub-parse)
/// when `allow_jsx` is on, the dominant cost on legacy TS sources like
/// parserharness.ts. Tracks the speculative re-parse overhead.
fn build_cast_heavy(func_count : Int) -> String {
  let buf = StringBuilder::new()
  for i in 0..<func_count {
    let n = i.to_string()
    buf.write_string("function conv" + n + "(x: unknown): number {\n")
    buf.write_string("  const a = <any>x;\n")
    buf.write_string("  const b = <number>(<any>a);\n")
    buf.write_string("  return <number>b + " + n + ";\n")
    buf.write_string("}\n")
  }
  buf.to_string()
}

///|
let cast_heavy_200 : String = build_cast_heavy(200)

///|
test "bench parser: small mixed declarations (~9 decls)" (it : @bench.T) {
  it.bench(fn() {
    let module_ = Parser::from_source(small_source).parse_module() catch {
      _ => return
    }
    it.keep(module_.interfaces.length())
  })
}

///|
test "bench parser: medium .d.ts (3 interfaces + class, ~70 members)" (
  it : @bench.T,
) {
  it.bench(fn() {
    let module_ = Parser::from_source(medium_source).parse_module() catch {
      _ => return
    }
    it.keep(module_.interfaces.length())
  })
}

///|
test "bench parser: advanced types (conditional/mapped/template-literal)" (
  it : @bench.T,
) {
  it.bench(fn() {
    let module_ = Parser::from_source(advanced_types_source).parse_module() catch {
      _ => return
    }
    it.keep(module_.type_aliases.length())
  })
}

///|
test "bench parser: wide interface (500 fields)" (it : @bench.T) {
  it.bench(fn() {
    let module_ = Parser::from_source(wide_500).parse_module() catch {
      _ => return
    }
    it.keep(module_.interfaces.length())
  })
}

///|
test "bench parser: wide interface (2000 fields)" (it : @bench.T) {
  it.bench(fn() {
    let module_ = Parser::from_source(wide_2000).parse_module() catch {
      _ => return
    }
    it.keep(module_.interfaces.length())
  })
}

///|
test "bench parser: JSDoc-heavy (300 documented decls)" (it : @bench.T) {
  it.bench(fn() {
    let module_ = Parser::from_source(jsdoc_heavy_300).parse_module() catch {
      _ => return
    }
    it.keep(module_.funcs.length())
  })
}

///|
/// `.tsx` mode: `<T>expr` in expression position triggers the JSX
/// speculation scan (tsc would reject old-style casts here, but the
/// parser still has to disambiguate — this tracks that path's cost).
test "bench parser: old-style cast heavy (200 funcs, .tsx JSX speculation)" (
  it : @bench.T,
) {
  it.bench(fn() {
    let module_ = Parser::from_source(cast_heavy_200).parse_module() catch {
      _ => return
    }
    it.keep(module_.funcs.length())
  })
}

///|
/// `.ts` mode (`allow_jsx` off): the same casts parse as type
/// assertions with no JSX speculation — the mode tscheck uses for every
/// non-`.tsx` file.
test "bench parser: old-style cast heavy (200 funcs, .ts assertion mode)" (
  it : @bench.T,
) {
  it.bench(fn() {
    let module_ = Parser::from_source_with_jsx(cast_heavy_200, false).parse_module() catch {
      _ => return
    }
    it.keep(module_.funcs.length())
  })
}

///|
/// Reading the typescript submodule files is async-only, so file-backed
/// benchmarks live under `moon test` rather than `moon bench`. Run with:
///   moon test --target native -p mizchi/ts/parser --filter "bench parser: TypeScript lib"
async test "bench parser: TypeScript lib files (file IO)" {
  let candidates = [
    "typescript/src/lib/es5.d.ts", "typescript/src/lib/dom.generated.d.ts", "typescript/src/compiler/scanner.ts",
    "typescript/src/compiler/parser.ts",
  ]
  let prepared : Array[(String, String)] = []
  for path in candidates {
    try @fs.read_file(path) catch {
      _ => ()
    } noraise {
      data => {
        let text = data.text()
        prepared.push((path, text))
      }
    }
  }
  if prepared.length() == 0 {
    println("skip: typescript submodule files not found")
    return
  }
  let bencher = @bench.new()
  for entry in prepared {
    let (path, text) = entry
    let bytes = text.length()
    let label = "parse \{path} (\{bytes} chars)"
    bencher.bench(name=label, count=5, fn() {
      let module_ = Parser::from_source(text).parse_module() catch {
        _ => return
      }
      bencher.keep(module_.interfaces.length())
    })
  }
  println(bencher.dump_summaries())
}
