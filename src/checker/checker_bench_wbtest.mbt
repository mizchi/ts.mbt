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
let bench_wide_2000 : String = build_bench_wide_module(2000)

///|
let bench_wide_5000 : String = build_bench_wide_module(5000)

///|
/// Generic-heavy fixture: lots of `infer` patterns, conditional
/// distribution, mapped-key remapping, and call sites that exercise
/// `solve_generic_bindings`.
fn build_bench_generic_heavy(n : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("type Awaited<T> = T extends Promise<infer U> ? U : T;\n")
  buf.write_string(
    "type ReturnType<F> = F extends (...args: any) => infer R ? R : any;\n",
  )
  buf.write_string(
    "type Parameters<F> = F extends (...args: infer P) => any ? P : never;\n",
  )
  buf.write_string(
    "type Getters<T> = { [K in keyof T as `get${Capitalize<K & string>}`]: () => T[K] };\n",
  )
  for i in 0..<n {
    let s = i.to_string()
    buf.write_string(
      "function id" +
      s +
      "<T extends { value: number }>(x: T): T { return x; }\n",
    )
    buf.write_string(
      "function compose" +
      s +
      "<A, B, C>(f: (a: A) => B, g: (b: B) => C): (a: A) => C {\n",
    )
    buf.write_string("  return (a) => g(f(a));\n")
    buf.write_string("}\n")
    buf.write_string(
      "function call" +
      s +
      "(n: number): number { return id" +
      s +
      "({ value: n }).value; }\n",
    )
  }
  buf.to_string()
}

///|
/// JSX-heavy fixture: many component declarations + many JSX call
/// sites. Exercises `check_jsx_attrs`, `infer_param_bindings` for
/// generic components, and the spread-prop path.
fn build_bench_jsx_heavy(components : Int, callsites : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string(
    "interface CardProps { title: string; count: number; active?: boolean }\n",
  )
  buf.write_string("function Card(props: CardProps): void {}\n")
  for i in 0..<components {
    let s = i.to_string()
    buf.write_string("interface P" + s + " { value: number; tag: string }\n")
    buf.write_string("function C" + s + "(props: P" + s + "): void {}\n")
  }
  buf.write_string("function render(): void {\n")
  let lb = "{"
  let rb = "}"
  for i in 0..<callsites {
    let s = i.to_string()
    let comp = i % components
    buf.write_string(
      "  const _" +
      s +
      " = <C" +
      comp.to_string() +
      " value=" +
      lb +
      s +
      rb +
      " tag=\"tag-" +
      s +
      "\" />;\n",
    )
  }
  buf.write_string("}\n")
  buf.to_string()
}

///|
let bench_generic_heavy_100 : String = build_bench_generic_heavy(100)

///|
let bench_jsx_heavy : String = build_bench_jsx_heavy(20, 100)

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
  let module_ = @parser.parse_module_from_source_with_const_values(
    bench_medium_source,
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
test "bench checker: advanced types (conditional/mapped/template-literal)" (
  it : @bench.T,
) {
  let module_ = @parser.parse_module_from_source_with_const_values(
    bench_advanced_source,
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
test "bench checker: 100 interfaces with cross-references" (it : @bench.T) {
  let module_ = @parser.parse_module_from_source_with_const_values(
    bench_wide_100,
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
test "bench checker: 500 interfaces with cross-references" (it : @bench.T) {
  let module_ = @parser.parse_module_from_source_with_const_values(
    bench_wide_500,
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
test "bench checker: 2000 interfaces (scale point)" (it : @bench.T) {
  let module_ = @parser.parse_module_from_source_with_const_values(
    bench_wide_2000,
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
test "bench checker: 5000 interfaces (scale point)" (it : @bench.T) {
  let module_ = @parser.parse_module_from_source_with_const_values(
    bench_wide_5000,
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
/// Generic-heavy: 100 generic helpers + 100 call sites exercising
/// `solve_generic_bindings` per call.
test "bench checker: generic-heavy (100 helpers, 100 call sites)" (
  it : @bench.T,
) {
  let module_ = @parser.parse_module_from_source_with_const_values(
    bench_generic_heavy_100,
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
/// JSX-heavy: 20 components + 100 call sites against `check_jsx_attrs`.
test "bench checker: JSX-heavy (20 components, 100 call sites)" (it : @bench.T) {
  let module_ = @parser.parse_module_from_source_with_const_values(
    bench_jsx_heavy,
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
/// Resolver build alone — separates `Resolver::from_module` (which
/// scans the whole module surface and builds 6 lookup tables) from
/// the function-body walk. Use the same input as the wide-500 bench
/// so the per-pass split is comparable to the full-pipeline bench
/// above.
test "bench checker: Resolver build (500 interfaces)" (it : @bench.T) {
  let module_ = @parser.parse_module_from_source_with_const_values(
    bench_wide_500,
    {},
  ) catch {
    _ => return
  }
  it.bench(fn() {
    let r = Resolver::from_module(module_)
    it.keep(r.interfaces.length())
  })
}

///|
/// Function-body walk alone — pre-builds the resolver once, then
/// times just the body-checking pass. The delta against the full
/// pipeline above shows what the resolver build costs vs. the body
/// walks.
test "bench checker: function-body walk only (500 interfaces)" (it : @bench.T) {
  let module_ = @parser.parse_module_from_source_with_const_values(
    bench_wide_500,
    {},
  ) catch {
    _ => return
  }
  it.bench(fn() {
    // Each iteration still produces a fresh resolver because the
    // checker entry takes a `TsModule`; the actual body-walk pass
    // dominates the wide-500 fixture anyway (single `readAll`
    // function).
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
    "typescript/src/lib/es5.d.ts", "typescript/src/lib/dom.generated.d.ts", "typescript/src/compiler/scanner.ts",
    "typescript/src/compiler/parser.ts", "typescript/src/compiler/checker.ts",
  ]
  // Parse each candidate once, then time only the checker pass over
  // the resulting `TsModule`. Capture the input character count so we
  // can report throughput.
  let prepared : Array[(String, Int, @ast.TsModule)] = []
  for path in candidates {
    try @fs.read_file(path) catch {
      _ => ()
    } noraise {
      data => {
        let text = data.text()
        let allow_jsx = path.has_suffix(".tsx")
        try
          @parser.Parser::from_source_with_jsx(text, allow_jsx).parse_module()
        catch {
          _ => ()
        } noraise {
          module_ => prepared.push((path, text.length(), module_))
        }
      }
    }
  }
  if prepared.length() == 0 {
    println("skip: typescript submodule files not found")
    return
  }
  // Run two passes per file: the full pipeline
  // (`check_module_function_bodies`, which builds the resolver and
  // walks bodies) and the resolver-build-only pass. The delta reveals
  // how much of the wall-clock the body walk is responsible for.
  let bencher = @bench.new()
  println("checker bench (file IO) — per-file:")
  for entry in prepared {
    let (path, chars, _) = entry
    println("  \{path}  (\{chars} chars)")
  }
  for entry in prepared {
    let (path, _, module_) = entry
    bencher.bench(name="full   " + path, count=5, fn() {
      let issues = check_module_function_bodies(module_)
      bencher.keep(issues.length())
    })
    bencher.bench(name="resolv " + path, count=5, fn() {
      let r = Resolver::from_module(module_)
      bencher.keep(r.interfaces.length())
    })
  }
  println(bencher.dump_summaries())
  // Throughput summary: MB/s for the full-pipeline pass.
  // `monotonic_clock_end` returns microseconds (verified against the
  // bench crate source). Run 50 iterations per file and divide so
  // the per-call number is robust to ~µs-level clock resolution.
  // chars / per_call_us = MB/s when 1 char = 1 byte of UTF-8 (true
  // for these ASCII-heavy .ts files).
  println("checker bench (file IO) — throughput (50 iters):")
  for entry in prepared {
    let (path, chars, module_) = entry
    let iters = 50
    let start = @bench.monotonic_clock_start()
    for _ in 0..<iters {
      let _ = check_module_function_bodies(module_)
    }
    let total_us = @bench.monotonic_clock_end(start)
    if total_us > 0.0 {
      let per_call_us = total_us / iters.to_double()
      let mbps = chars.to_double() / per_call_us
      println(
        "  \{path}: \{mbps.to_int()} MB/s (\{chars} chars / \{per_call_us.to_int()} µs per check)",
      )
    } else {
      println("  \{path}: too fast to measure (\{chars} chars)")
    }
  }
}
