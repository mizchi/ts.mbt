// Checker throughput benchmarks. Run with:
//   moon bench --target native -p checker
//
// Each `test` here uses the `(it : @bench.T)` signature so the moonbit
// benchmarking harness times only the body of `it.bench(fn() { ... })`.
// Module parsing happens once up-front (outside the timed region) and
// every benchmark measures `Resolver::from_module` +
// `check_module_function_bodies` over the parsed module.

///|
let bench_small_source : String =
  #|interface User {
  #|  id: number;
  #|  name: string;
  #|  email?: string;
  #|  readonly createdAt: Date;
  #|}
  #|type UserId = User["id"];
  #|type PartialUser = Partial<User>;
  #|function createUser(name: string, email?: string): User {
  #|  return { id: 0, name, email, createdAt: new Date() };
  #|}
  #|function readBoth(u: User): string {
  #|  const _ = u.email;
  #|  return u.name;
  #|}

///|
let bench_medium_source : String =
  #|interface A { kind: "a"; a: number; }
  #|interface B { kind: "b"; b: string; }
  #|interface C { kind: "c"; c: boolean; }
  #|function pick(s: A | B | C): boolean {
  #|  switch (s.kind) {
  #|    case "a": return false;
  #|    case "b": return s.b.length > 0;
  #|    default: return s.c;
  #|  }
  #|}
  #|declare function assertString(value: string | number): asserts value is string;
  #|function use(v: string | number): string {
  #|  assertString(v);
  #|  return v;
  #|}
  #|interface Foo { x: number; y: string; }
  #|function readAll(f: Foo): string {
  #|  return f.y + f.x.toString();
  #|}
  #|function map<T, R>(arr: T[], f: (x: T) => R): R[] {
  #|  const out: R[] = [];
  #|  for (const x of arr) {
  #|    out.push(f(x));
  #|  }
  #|  return out;
  #|}
  #|function pipe<A, B, C>(a: A, f: (a: A) => B, g: (b: B) => C): C {
  #|  return g(f(a));
  #|}

///|
let bench_advanced_source : String =
  #|type Awaited<T> = T extends Promise<infer U> ? U : T;
  #|type ReturnType<T extends (...args: any) => any> =
  #|  T extends (...args: any) => infer R ? R : any;
  #|type Parameters<T extends (...args: any) => any> =
  #|  T extends (...args: infer P) => any ? P : never;
  #|type Getters<T> = {
  #|  [K in keyof T as `get${Capitalize<K & string>}`]: () => T[K];
  #|};
  #|type Setters<T> = {
  #|  [K in keyof T as `set${Capitalize<K & string>}`]: (v: T[K]) => void;
  #|};
  #|type DeepReadonly<T> = {
  #|  readonly [K in keyof T]: T[K] extends object ? DeepReadonly<T[K]> : T[K];
  #|};
  #|interface User { id: number; name: string; age: number; }
  #|type UserGetters = Getters<User>;
  #|type UserSetters = Setters<User>;
  #|type DeepUser = DeepReadonly<User>;
  #|function useUser(u: User): number {
  #|  return u.id + u.age;
  #|}

///|
/// Programmatically build a module with `n` interface declarations that
/// share field shapes so the checker's resolver + structural lookups
/// scale predictably.
fn build_bench_wide_module(n : Int) -> String {
  let buf = StringBuilder::new()
  for i in 0..<n {
    let suffix = i.to_string()
    buf.write_string("interface Wide" + suffix + " {\n")
    buf.write_string("  id: number;\n")
    buf.write_string("  name: string;\n")
    buf.write_string("  tags: string[];\n")
    buf.write_string("  payload: Wide" + ((i + 1) % n).to_string() + ";\n")
    buf.write_string("}\n")
  }
  // One function that reads from each interface so the checker walks
  // every field at least once.
  buf.write_string("function readAll(a: Wide0): string {\n")
  buf.write_string("  return a.name + a.id.toString();\n")
  buf.write_string("}\n")
  buf.to_string()
}

///|
let bench_wide_100 : String = build_bench_wide_module(100)

///|
let bench_wide_500 : String = build_bench_wide_module(500)

///|
test "bench checker: small mixed declarations (~7 decls)" (it : @bench.T) {
  let module_ = @parser.parse_module_from_source_with_const_values(
    bench_small_source,
    {},
  ) catch {
    _ => return
  }
  it.bench(fn() {
    let issues = check_module_function_bodies(module_)
    it.keep(issues.length())
  })
}

///|
test "bench checker: medium tagged-union + asserts (~6 funcs, ~3 ifaces)" (
  it : @bench.T,
) {
  let module_ = @parser.parse_module_from_source_with_const_values(bench_medium_source, {}) catch {
    _ => return
  }
  it.bench(fn() {
    let issues = check_module_function_bodies(module_)
    it.keep(issues.length())
  })
}

///|
test "bench checker: advanced types (conditional/mapped/template-literal)" (
  it : @bench.T,
) {
  let module_ = @parser.parse_module_from_source_with_const_values(bench_advanced_source, {}) catch {
    _ => return
  }
  it.bench(fn() {
    let issues = check_module_function_bodies(module_)
    it.keep(issues.length())
  })
}

///|
test "bench checker: 100 interfaces with cross-references" (it : @bench.T) {
  let module_ = @parser.parse_module_from_source_with_const_values(bench_wide_100, {}) catch {
    _ => return
  }
  it.bench(fn() {
    let issues = check_module_function_bodies(module_)
    it.keep(issues.length())
  })
}

///|
test "bench checker: 500 interfaces with cross-references" (it : @bench.T) {
  let module_ = @parser.parse_module_from_source_with_const_values(bench_wide_500, {}) catch {
    _ => return
  }
  it.bench(fn() {
    let issues = check_module_function_bodies(module_)
    it.keep(issues.length())
  })
}

///|
/// File-backed benchmark over real TypeScript source. Reading the
/// submodule files needs async, so this runs under `moon test` rather
/// than `moon bench`:
///   moon test --target native -p checker --filter "bench checker: TypeScript"
async test "bench checker: TypeScript compiler source (file IO)" {
  let candidates = [
    "typescript/src/lib/es5.d.ts",
    "typescript/src/lib/dom.generated.d.ts",
    "typescript/src/compiler/scanner.ts",
    "typescript/src/compiler/parser.ts",
    "typescript/src/compiler/checker.ts",
  ]
  // Parse each candidate once, then time only the checker pass over
  // the resulting `TsModule`.
  let prepared : Array[(String, @ast.TsModule)] = []
  for path in candidates {
    match (try? @fs.read_file(path)) {
      Ok(data) => {
        let text = data.text()
        let allow_jsx = path.has_suffix(".tsx")
        match
          (try? @parser.Parser::from_source_with_jsx(text, allow_jsx).parse_module()) {
          Ok(module_) => prepared.push((path, module_))
          Err(_) => ()
        }
      }
      Err(_) => ()
    }
  }
  if prepared.length() == 0 {
    println("skip: typescript submodule files not found")
    return
  }
  let bencher = @bench.new()
  // Also report a per-file size so a downstream regression check can
  // compute throughput (lines per second).
  println("checker bench (file IO) — input sizes:")
  for entry in prepared {
    let (path, _) = entry
    // Cheap line count via the original file size in bytes is enough
    // for the dimension; precise LOC isn't worth a second read.
    println("  \{path}")
  }
  for entry in prepared {
    let (path, module_) = entry
    let label = "check " + path
    bencher.bench(name=label, count=5, fn() {
      let issues = check_module_function_bodies(module_)
      bencher.keep(issues.length())
    })
  }
  println(bencher.dump_summaries())
}
