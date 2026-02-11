///|
fn make_large_source(funcs : Int) -> String {
  let sb = StringBuilder::new()
  let mut i = 0
  while i < funcs {
    sb
    ..write_string("function f")
    ..write_string(i.to_string())
    ..write_string("(x) { return x + ")
    ..write_string(i.to_string())
    .write_string("; }\n")
    i = i + 1
  }
  sb..write_string("function main() {\n").write_string("  let acc = 0;\n")
  let mut j = 0
  while j < funcs {
    sb
    ..write_string("  acc += f")
    ..write_string(j.to_string())
    ..write_string("(")
    ..write_string(j.to_string())
    .write_string(");\n")
    j = j + 1
  }
  sb..write_string("  return acc;\n").write_string("}\n")
  sb.to_string()
}

///|
let parser_small_src : String =
  #|function fib(n) {
  #|  if (n <= 1) return n;
  #|  return fib(n - 1) + fib(n - 2);
  #|}
  #|function main() {
  #|  let sum = 0;
  #|  for (let i = 0; i < 20; i++) { sum += fib(i); }
  #|  return sum;
  #|}

///|
let parser_large_src : String = make_large_source(200)

///|
let runtime_small_src : String =
  #|function sum(n) {
  #|  let s = 0;
  #|  for (let i = 0; i < n; i++) { s += i; }
  #|  return s;
  #|}
  #|function main() {
  #|  let total = 0;
  #|  for (let i = 0; i < 200; i++) { total += sum(200); }
  #|  return total;
  #|}

///|
let runtime_large_src : String = make_large_source(200)

///|
test "bench parser tokenize small" (b : @bench.T) {
  b.bench(
    () => {
      let lexer = @parser.Lexer::new(parser_small_src)
      let _ = lexer.tokenize()
    },
    name="parser.tokenize.small",
    count=10,
  )
}

///|
test "bench parser module small" (b : @bench.T) {
  b.bench(
    () => {
      let parser = @parser.Parser::from_source(parser_small_src)
      let _ = try! parser.parse_module()
    },
    name="parser.module.small",
    count=5,
  )
}

///|
test "bench parser module large" (b : @bench.T) {
  b.bench(
    () => {
      let parser = @parser.Parser::from_source(parser_large_src)
      let _ = try! parser.parse_module()
    },
    name="parser.module.large",
    count=1,
  )
}

///|
test "bench runtime run small" (b : @bench.T) {
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(runtime_small_src)
    },
    name="runtime.run.small",
    count=1,
  )
}

///|
test "bench runtime run large" (b : @bench.T) {
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(runtime_large_src)
    },
    name="runtime.run.large",
    count=1,
  )
}

///|
/// TypeScript d.ts parsing benchmark
let ts_dts_src : String =
  #|interface Array<T> {
  #|    readonly length: number;
  #|    toString(): string;
  #|    toLocaleString(): string;
  #|    pop(): T | undefined;
  #|    push(...items: T[]): number;
  #|    concat(...items: ConcatArray<T>[]): T[];
  #|    concat(...items: (T | ConcatArray<T>)[]): T[];
  #|    join(separator?: string): string;
  #|    reverse(): T[];
  #|    shift(): T | undefined;
  #|    slice(start?: number, end?: number): T[];
  #|    sort(compareFn?: (a: T, b: T) => number): this;
  #|    splice(start: number, deleteCount?: number): T[];
  #|    splice(start: number, deleteCount: number, ...items: T[]): T[];
  #|    unshift(...items: T[]): number;
  #|    indexOf(searchElement: T, fromIndex?: number): number;
  #|    lastIndexOf(searchElement: T, fromIndex?: number): number;
  #|    every<S extends T>(predicate: (value: T, index: number, array: T[]) => value is S, thisArg?: any): this is S[];
  #|    every(predicate: (value: T, index: number, array: T[]) => unknown, thisArg?: any): boolean;
  #|    some(predicate: (value: T, index: number, array: T[]) => unknown, thisArg?: any): boolean;
  #|    forEach(callbackfn: (value: T, index: number, array: T[]) => void, thisArg?: any): void;
  #|    map<U>(callbackfn: (value: T, index: number, array: T[]) => U, thisArg?: any): U[];
  #|    filter<S extends T>(predicate: (value: T, index: number, array: T[]) => value is S, thisArg?: any): S[];
  #|    filter(predicate: (value: T, index: number, array: T[]) => unknown, thisArg?: any): T[];
  #|    reduce(callbackfn: (previousValue: T, currentValue: T, currentIndex: number, array: T[]) => T): T;
  #|    reduce(callbackfn: (previousValue: T, currentValue: T, currentIndex: number, array: T[]) => T, initialValue: T): T;
  #|    reduce<U>(callbackfn: (previousValue: U, currentValue: T, currentIndex: number, array: T[]) => U, initialValue: U): U;
  #|    reduceRight(callbackfn: (previousValue: T, currentValue: T, currentIndex: number, array: T[]) => T): T;
  #|    reduceRight(callbackfn: (previousValue: T, currentValue: T, currentIndex: number, array: T[]) => T, initialValue: T): T;
  #|    reduceRight<U>(callbackfn: (previousValue: U, currentValue: T, currentIndex: number, array: T[]) => U, initialValue: U): U;
  #|    readonly [n: number]: T;
  #|}
  #|
  #|type Partial<T> = {
  #|    [P in keyof T]?: T[P];
  #|};
  #|
  #|type Required<T> = {
  #|    [P in keyof T]-?: T[P];
  #|};
  #|
  #|type Omit<T, K extends keyof any> = Pick<T, Exclude<keyof T, K>>;

///|
test "bench parser typescript dts" (b : @bench.T) {
  b.bench(
    () => {
      let parser = @parser.Parser::from_source(ts_dts_src)
      let _ = try! parser.parse_module()
    },
    name="parser.typescript.dts",
    count=5,
  )
}

// ============================================================
// Initialization Benchmarks
// ============================================================

///|
test "bench init interpreter" (b : @bench.T) {
  b.bench(
    () => {
      let _ = @runtime.JSInterpreter::new()
    },
    name="init.interpreter",
    count=100,
  )
}

///|
test "bench init lexer" (b : @bench.T) {
  b.bench(
    () => {
      let _ = @parser.Lexer::new("function f() { return 1; }")
    },
    name="init.lexer",
    count=100,
  )
}

///|
test "bench init parser" (b : @bench.T) {
  b.bench(
    () => {
      let _ = @parser.Parser::from_source("function f() { return 1; }")
    },
    name="init.parser",
    count=100,
  )
}

// ============================================================
// Size-based Execution Benchmarks (fibonacci)
// ============================================================

///|
fn fib_source(n : Int) -> String {
  let sb = StringBuilder::new()
  sb.write_string("function fib(n) {\n")
  sb.write_string("  if (n <= 1) return n;\n")
  sb.write_string("  return fib(n - 1) + fib(n - 2);\n")
  sb.write_string("}\n")
  sb.write_string("function main() {\n")
  sb.write_string("  return fib(")
  sb.write_string(n.to_string())
  sb.write_string(");\n")
  sb.write_string("}")
  sb.to_string()
}

///|
test "bench runtime fib(10)" (b : @bench.T) {
  let src = fib_source(10)
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(src)
    },
    name="runtime.fib.10",
    count=10,
  )
}

///|
test "bench runtime fib(15)" (b : @bench.T) {
  let src = fib_source(15)
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(src)
    },
    name="runtime.fib.15",
    count=5,
  )
}

///|
test "bench runtime fib(20)" (b : @bench.T) {
  let src = fib_source(20)
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(src)
    },
    name="runtime.fib.20",
    count=3,
  )
}

///|
test "bench runtime fib(25)" (b : @bench.T) {
  let src = fib_source(25)
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(src)
    },
    name="runtime.fib.25",
    count=1,
  )
}

// ============================================================
// Size-based Loop Benchmarks
// ============================================================

///|
fn loop_source(iterations : Int) -> String {
  let sb = StringBuilder::new()
  sb.write_string("function main() {\n")
  sb.write_string("  let sum = 0;\n")
  sb.write_string("  for (let i = 0; i < ")
  sb.write_string(iterations.to_string())
  sb.write_string("; i++) { sum += i; }\n")
  sb.write_string("  return sum;\n")
  sb.write_string("}")
  sb.to_string()
}

///|
test "bench runtime loop 100" (b : @bench.T) {
  let src = loop_source(100)
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(src)
    },
    name="runtime.loop.100",
    count=50,
  )
}

///|
test "bench runtime loop 1000" (b : @bench.T) {
  let src = loop_source(1000)
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(src)
    },
    name="runtime.loop.1000",
    count=10,
  )
}

///|
test "bench runtime loop 10000" (b : @bench.T) {
  let src = loop_source(10000)
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(src)
    },
    name="runtime.loop.10000",
    count=5,
  )
}

// ============================================================
// Parse vs Execute Separation Benchmarks
// ============================================================

///|
test "bench parse only fib" (b : @bench.T) {
  let src = fib_source(20)
  b.bench(
    () => {
      let parser = @parser.Parser::from_source(src)
      let _ = try! parser.parse_module()
    },
    name="parse.fib",
    count=50,
  )
}

///|
test "bench execute only fib(20)" (b : @bench.T) {
  let src = fib_source(20)
  // Pre-parse the module
  let parser = @parser.Parser::from_source(src)
  let module_ = try! parser.parse_module()
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = interp.run_module(module_)
    },
    name="execute.fib.20",
    count=3,
  )
}

// ============================================================
// Object/Array Creation Benchmarks
// ============================================================

///|
let object_create_src : String =
  #|function main() {
  #|  let arr = [];
  #|  for (let i = 0; i < 100; i++) {
  #|    arr.push({ x: i, y: i * 2, z: i * 3 });
  #|  }
  #|  return arr.length;
  #|}

///|
test "bench runtime object creation" (b : @bench.T) {
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(object_create_src)
    },
    name="runtime.object.create",
    count=10,
  )
}

///|
let array_ops_src : String =
  #|function main() {
  #|  let arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  #|  let sum = 0;
  #|  for (let i = 0; i < 100; i++) {
  #|    sum += arr.reduce((a, b) => a + b, 0);
  #|  }
  #|  return sum;
  #|}

///|
test "bench runtime array reduce" (b : @bench.T) {
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(array_ops_src)
    },
    name="runtime.array.reduce",
    count=5,
  )
}

// ============================================================
// String Operations Benchmarks
// ============================================================

///|
let string_concat_src : String =
  #|function main() {
  #|  let s = "";
  #|  for (let i = 0; i < 100; i++) {
  #|    s = s + "x";
  #|  }
  #|  return s.length;
  #|}

///|
test "bench runtime string concat" (b : @bench.T) {
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(string_concat_src)
    },
    name="runtime.string.concat",
    count=20,
  )
}

///|
let string_methods_src : String =
  #|function main() {
  #|  let s = "hello world test string for benchmark";
  #|  let count = 0;
  #|  for (let i = 0; i < 100; i++) {
  #|    count += s.indexOf("test");
  #|    count += s.slice(0, 5).length;
  #|    count += s.toUpperCase().length;
  #|  }
  #|  return count;
  #|}

///|
test "bench runtime string methods" (b : @bench.T) {
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(string_methods_src)
    },
    name="runtime.string.methods",
    count=10,
  )
}

// ============================================================
// GC / Memory Allocation Benchmarks
// ============================================================

///|
let gc_object_creation_src : String =
  #|function main() {
  #|  for (let i = 0; i < 1000; i++) {
  #|    let obj = { a: 1, b: 2, c: i };
  #|  }
  #|  return "done";
  #|}

///|
test "bench gc object creation" (b : @bench.T) {
  b.bench(
    () => {
      @runtime.gc_stats_reset()
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(gc_object_creation_src)
    },
    name="gc.object.creation.1000",
    count=5,
  )
}

///|
let gc_array_creation_src : String =
  #|function main() {
  #|  for (let i = 0; i < 1000; i++) {
  #|    let arr = [1, 2, 3, i];
  #|  }
  #|  return "done";
  #|}

///|
test "bench gc array creation" (b : @bench.T) {
  b.bench(
    () => {
      @runtime.gc_stats_reset()
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(gc_array_creation_src)
    },
    name="gc.array.creation.1000",
    count=5,
  )
}

///|
let gc_closure_creation_src : String =
  #|function main() {
  #|  let funcs = [];
  #|  for (let i = 0; i < 100; i++) {
  #|    funcs.push(() => i);
  #|  }
  #|  return funcs.length;
  #|}

///|
test "bench gc closure creation" (b : @bench.T) {
  b.bench(
    () => {
      @runtime.gc_stats_reset()
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(gc_closure_creation_src)
    },
    name="gc.closure.creation.100",
    count=10,
  )
}

///|
let gc_nested_scopes_src : String =
  #|function main() {
  #|  let sum = 0;
  #|  for (let i = 0; i < 100; i++) {
  #|    for (let j = 0; j < 10; j++) {
  #|      let x = i + j;
  #|      sum += x;
  #|    }
  #|  }
  #|  return sum;
  #|}

///|
test "bench gc nested scopes" (b : @bench.T) {
  b.bench(
    () => {
      @runtime.gc_stats_reset()
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(gc_nested_scopes_src)
    },
    name="gc.nested.scopes",
    count=10,
  )
}

// ============================================================
// Weak Collection Benchmarks
// ============================================================

///|
let weakmap_bench_src : String =
  #|function main() {
  #|  let wm = new WeakMap();
  #|  let keys = [];
  #|  for (let i = 0; i < 100; i++) {
  #|    let k = { id: i };
  #|    keys.push(k);
  #|    wm.set(k, i * 2);
  #|  }
  #|  let sum = 0;
  #|  for (let k of keys) {
  #|    sum += wm.get(k);
  #|  }
  #|  return sum;
  #|}

///|
test "bench weakmap operations" (b : @bench.T) {
  b.bench(
    () => {
      @runtime.gc_stats_reset()
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(weakmap_bench_src)
    },
    name="gc.weakmap.100",
    count=10,
  )
}

///|
let weakset_bench_src : String =
  #|function main() {
  #|  let ws = new WeakSet();
  #|  let items = [];
  #|  for (let i = 0; i < 100; i++) {
  #|    let item = { id: i };
  #|    items.push(item);
  #|    ws.add(item);
  #|  }
  #|  let count = 0;
  #|  for (let item of items) {
  #|    if (ws.has(item)) count++;
  #|  }
  #|  return count;
  #|}

///|
test "bench weakset operations" (b : @bench.T) {
  b.bench(
    () => {
      @runtime.gc_stats_reset()
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(weakset_bench_src)
    },
    name="gc.weakset.100",
    count=10,
  )
}

///|
let weakref_bench_src : String =
  #|function main() {
  #|  let refs = [];
  #|  for (let i = 0; i < 100; i++) {
  #|    refs.push(new WeakRef({ value: i }));
  #|  }
  #|  let sum = 0;
  #|  for (let wr of refs) {
  #|    let obj = wr.deref();
  #|    if (obj) sum += obj.value;
  #|  }
  #|  return sum;
  #|}

///|
test "bench weakref operations" (b : @bench.T) {
  b.bench(
    () => {
      @runtime.gc_stats_reset()
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(weakref_bench_src)
    },
    name="gc.weakref.100",
    count=10,
  )
}

// ============================================================
// AOT vs Interpreter Benchmarks
// ============================================================

///|
let aot_add_src : String =
  #|export function add(a: number, b: number): number {
  #|  return a + b;
  #|}

///|
test "bench AOT compile add" (b : @bench.T) {
  let parser = @parser.Parser::from_source(aot_add_src)
  let module_ = try! parser.parse_module()
  b.bench(
    () => {
      let _ = try! @aot.compile_module_to_wasm(module_)
    },
    name="aot.compile.add",
    count=20,
  )
}

///|
test "bench AOT call add" (b : @bench.T) {
  let parser = @parser.Parser::from_source(aot_add_src)
  let module_ = try! parser.parse_module()
  let runtime = try! @aot.create_aot_runtime(module_)
  b.bench(
    () => {
      let _ = try! runtime.call("add", [10.0, 32.0])
    },
    name="aot.call.add",
    count=100,
  )
}

///|
let aot_loop_src : String =
  #|export function sum(n: number): number {
  #|  let s: number = 0;
  #|  for (let i: number = 0; i < n; i = i + 1) {
  #|    s = s + i;
  #|  }
  #|  return s;
  #|}

///|
test "bench AOT compile loop" (b : @bench.T) {
  let parser = @parser.Parser::from_source(aot_loop_src)
  let module_ = try! parser.parse_module()
  b.bench(
    () => {
      let _ = try! @aot.compile_module_to_wasm(module_)
    },
    name="aot.compile.loop",
    count=10,
  )
}

///|
test "bench AOT call loop(1000)" (b : @bench.T) {
  let parser = @parser.Parser::from_source(aot_loop_src)
  let module_ = try! parser.parse_module()
  let runtime = try! @aot.create_aot_runtime(module_)
  b.bench(
    () => {
      let _ = try! runtime.call("sum", [1000.0])
    },
    name="aot.call.loop.1000",
    count=50,
  )
}

///|
test "bench interpreter call loop(1000)" (b : @bench.T) {
  let src =
    #|function sum(n) {
    #|  let s = 0;
    #|  for (let i = 0; i < n; i++) { s += i; }
    #|  return s;
    #|}
    #|function main() {
    #|  return sum(1000);
    #|}
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(src)
    },
    name="interpreter.call.loop.1000",
    count=50,
  )
}

///|
let aot_fib_src : String =
  #|export function fib(n: number): number {
  #|  if (n <= 1) { return n; }
  #|  return fib(n - 1) + fib(n - 2);
  #|}

///|
test "bench AOT compile fib" (b : @bench.T) {
  let parser = @parser.Parser::from_source(aot_fib_src)
  let module_ = try! parser.parse_module()
  b.bench(
    () => {
      let _ = try! @aot.compile_module_to_wasm(module_)
    },
    name="aot.compile.fib",
    count=10,
  )
}

///|
test "bench AOT call fib(20)" (b : @bench.T) {
  let parser = @parser.Parser::from_source(aot_fib_src)
  let module_ = try! parser.parse_module()
  let runtime = try! @aot.create_aot_runtime(module_)
  b.bench(
    () => {
      let _ = try! runtime.call("fib", [20.0])
    },
    name="aot.call.fib.20",
    count=3,
  )
}

///|
test "bench interpreter vs AOT loop(10000)" (b : @bench.T) {
  // Interpreter version
  let interp_src =
    #|function sum(n) {
    #|  let s = 0;
    #|  for (let i = 0; i < n; i++) { s += i; }
    #|  return s;
    #|}
    #|function main() {
    #|  return sum(10000);
    #|}
  b.bench(
    () => {
      let interp = @runtime.JSInterpreter::new()
      let _ = try! interp.run(interp_src)
    },
    name="compare.interpreter.loop.10000",
    count=5,
  )
  // AOT version
  let parser = @parser.Parser::from_source(aot_loop_src)
  let module_ = try! parser.parse_module()
  let runtime = try! @aot.create_aot_runtime(module_)
  b.bench(
    () => {
      let _ = try! runtime.call("sum", [10000.0])
    },
    name="compare.aot.loop.10000",
    count=5,
  )
}

///|
let aot_math_src : String =
  #|export function distance(x1: number, y1: number, x2: number, y2: number): number {
  #|  const dx: number = x2 - x1;
  #|  const dy: number = y2 - y1;
  #|  return Math.sqrt(dx * dx + dy * dy);
  #|}

///|
test "bench AOT call math.sqrt" (b : @bench.T) {
  let parser = @parser.Parser::from_source(aot_math_src)
  let module_ = try! parser.parse_module()
  let runtime = try! @aot.create_aot_runtime(module_)
  b.bench(
    () => {
      let _ = try! runtime.call("distance", [0.0, 0.0, 3.0, 4.0])
    },
    name="aot.call.math.sqrt",
    count=100,
  )
}
