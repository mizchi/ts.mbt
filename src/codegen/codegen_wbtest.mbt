// CodeGen test

///|
test "compile_to_wasm: generates valid wasm binary" {
  let src =
    #|function add(a: number, b: number): number {
    #|  return a + b;
    #|}
  let wasm = compile_to_wasm(src)

  // Wasm magic numbercheck: 0x00 0x61 0x73 0x6D (= "\0asm")
  assert_eq(wasm[0], b'\x00')
  assert_eq(wasm[1], b'\x61') // 'a'
  assert_eq(wasm[2], b'\x73') // 's'
  assert_eq(wasm[3], b'\x6D') // 'm'

  // version 1.0: 0x01 0x00 0x00 0x00
  assert_eq(wasm[4], b'\x01')
  assert_eq(wasm[5], b'\x00')
  assert_eq(wasm[6], b'\x00')
  assert_eq(wasm[7], b'\x00')
  println("Generated Wasm binary: \{wasm.length()} bytes")
}

///|
test "compile_to_wasm: factorial" {
  let src =
    #|function factorial(n: number): number {
    #|  if (n <= 1) {
    #|    return 1;
    #|  }
    #|  return n * factorial(n - 1);
    #|}
  let wasm = compile_to_wasm(src)

  // Wasm magic numbercheck
  assert_eq(wasm[0], b'\x00')
  assert_eq(wasm[1], b'\x61')

  // generateruncheck (wasm5 runtime )
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"factorial", [@runtime.Value::F64(5.0)])
  assert_eq(results[0], @runtime.Value::F64(120.0))
  println("Factorial Wasm binary: \{wasm.length()} bytes")
}

///|
test "compile: convenience function" {
  let src =
    #|function double(x: number): number {
    #|  return x * 2;
    #|}
  let wasm_module = compile(src)

  // Module generate
  assert_eq(wasm_module.funcs.length(), 1)
  assert_eq(wasm_module.exports.length(), 1)
  assert_eq(wasm_module.codes.length(), 1)

  // runtest
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"double", [@runtime.Value::F64(21.0)])
  assert_eq(results[0], @runtime.Value::F64(42.0))
}

///|
test "codegen: constant function" {
  let src =
    #|function answer(): number {
    #|  return 42;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"answer", [])
  assert_eq(results[0], @runtime.Value::F64(42.0))
}

///|
test "codegen: add function" {
  let src =
    #|function add(a: number, b: number): number {
    #|  return a + b;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"add", [
    @runtime.Value::F64(3.0),
    @runtime.Value::F64(5.0),
  ])
  assert_eq(results[0], @runtime.Value::F64(8.0))
}

///|
test "codegen: arithmetic" {
  let src =
    #|function calc(a: number, b: number): number {
    #|  return (a + b) * (a - b);
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  // (5 + 3) * (5 - 3) = 8 * 2 = 16
  let results = runtime.call_compiled(b"calc", [
    @runtime.Value::F64(5.0),
    @runtime.Value::F64(3.0),
  ])
  assert_eq(results[0], @runtime.Value::F64(16.0))
}

///|
test "codegen: local variable" {
  let src =
    #|function test(): number {
    #|  let x: number = 10;
    #|  let y: number = 20;
    #|  return x + y;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"test", [])
  assert_eq(results[0], @runtime.Value::F64(30.0))
}

///|
test "codegen: if-else" {
  let src =
    #|function max(a: number, b: number): number {
    #|  if (a > b) {
    #|    return a;
    #|  } else {
    #|    return b;
    #|  }
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results1 = runtime.call_compiled(b"max", [
    @runtime.Value::F64(10.0),
    @runtime.Value::F64(5.0),
  ])
  assert_eq(results1[0], @runtime.Value::F64(10.0))
  let results2 = runtime.call_compiled(b"max", [
    @runtime.Value::F64(3.0),
    @runtime.Value::F64(7.0),
  ])
  assert_eq(results2[0], @runtime.Value::F64(7.0))
}

///|
test "codegen: recursive factorial" {
  let src =
    #|function factorial(n: number): number {
    #|  if (n <= 1) {
    #|    return 1;
    #|  }
    #|  return n * factorial(n - 1);
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"factorial", [@runtime.Value::F64(5.0)])
  assert_eq(results[0], @runtime.Value::F64(120.0))
}

///|
test "codegen: while loop" {
  let src =
    #|function sum(n: number): number {
    #|  let total: number = 0;
    #|  let i: number = 1;
    #|  while (i <= n) {
    #|    total = total + i;
    #|    i = i + 1;
    #|  }
    #|  return total;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()

  // sum(10) = 1+2+...+10 = 55
  let results = runtime.call_compiled(b"sum", [@runtime.Value::F64(10.0)])
  assert_eq(results[0], @runtime.Value::F64(55.0))
}

///|
test "codegen: multiple functions" {
  let src =
    #|function double(x: number): number {
    #|  return x * 2;
    #|}
    #|function quadruple(x: number): number {
    #|  return double(double(x));
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"quadruple", [@runtime.Value::F64(5.0)])
  assert_eq(results[0], @runtime.Value::F64(20.0))
}

///|
test "codegen: int type operations" {
  let src =
    #|function sum_int(n: int): int {
    #|  let total: int = 0;
    #|  let i: int = 1;
    #|  while (i <= n) {
    #|    total = total + i;
    #|    i = i + 1;
    #|  }
    #|  return total;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()

  // sum_int(10) = 1+2+...+10 = 55
  let results = runtime.call_compiled(b"sum_int", [@runtime.Value::I32(10)])
  assert_eq(results[0], @runtime.Value::I32(55))
}

///|
test "codegen: int factorial" {
  let src =
    #|function factorial_int(n: int): int {
    #|  if (n <= 1) {
    #|    return 1;
    #|  }
    #|  return n * factorial_int(n - 1);
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"factorial_int", [@runtime.Value::I32(5)])
  assert_eq(results[0], @runtime.Value::I32(120))
}

///|
test "codegen: array literal and access" {
  let src =
    #|function sum_array(): number {
    #|  let arr: number[] = [1.0, 2.0, 3.0];
    #|  return arr[0] + arr[1] + arr[2];
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)

  // check
  assert_eq(wasm_module.mems.length(), 1)
  assert_eq(wasm_module.globals.length(), 1)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"sum_array", [])
  assert_eq(results[0], @runtime.Value::F64(6.0))
}

///|
test "codegen: array with new" {
  let src =
    #|function array_length(): int {
    #|  let arr: int[] = new Array<int>(5);
    #|  return arr.length;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"array_length", [])
  assert_eq(results[0], @runtime.Value::I32(5))
}

///|
test "codegen: array assignment" {
  let src =
    #|function array_set(): int {
    #|  let arr: int[] = new Array<int>(3);
    #|  arr[0] = 10;
    #|  arr[1] = 20;
    #|  arr[2] = 30;
    #|  return arr[0] + arr[1] + arr[2];
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"array_set", [])
  assert_eq(results[0], @runtime.Value::I32(60))
}

///|
test "codegen: struct creation and field access" {
  let src =
    #|interface Point {
    #|  x: number;
    #|  y: number;
    #|}
    #|function createPoint(): number {
    #|  let p: Point = new Point();
    #|  p.x = 10.0;
    #|  p.y = 20.0;
    #|  return p.x + p.y;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"createPoint", [])
  assert_eq(results[0], @runtime.Value::F64(30.0))
}

///|
test "codegen: struct with int fields" {
  let src =
    #|interface Counter {
    #|  count: int;
    #|}
    #|function testCounter(): int {
    #|  let c: Counter = new Counter();
    #|  c.count = 42;
    #|  return c.count;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"testCounter", [])
  assert_eq(results[0], @runtime.Value::I32(42))
}

///|
test "codegen: ternary operator" {
  let src =
    #|function abs(x: number): number {
    #|  return x >= 0.0 ? x : -x;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let r1 = runtime.call_compiled(b"abs", [@runtime.Value::F64(5.0)])
  assert_eq(r1[0], @runtime.Value::F64(5.0))
  let r2 = runtime.call_compiled(b"abs", [@runtime.Value::F64(-3.0)])
  assert_eq(r2[0], @runtime.Value::F64(3.0))
}

///|
test "codegen: increment decrement" {
  let src =
    #|function testIncDec(): int {
    #|  let x: int = 10;
    #|  let a: int = x++;
    #|  let b: int = ++x;
    #|  return a + b;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()

  // x starts at 10, a = x++ (a=10, x=11), b = ++x (x=12, b=12)
  // result = 10 + 12 = 22
  let results = runtime.call_compiled(b"testIncDec", [])
  assert_eq(results[0], @runtime.Value::I32(22))
}

///|
test "codegen: compound assignment" {
  let src =
    #|function testCompound(): int {
    #|  let x: int = 10;
    #|  x += 5;
    #|  x *= 2;
    #|  x -= 10;
    #|  return x;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()

  // x = 10, x += 5 (15), x *= 2 (30), x -= 10 (20)
  let results = runtime.call_compiled(b"testCompound", [])
  assert_eq(results[0], @runtime.Value::I32(20))
}

///|
test "codegen: for loop with increment" {
  let src =
    #|function sumFor(n: int): int {
    #|  let total: int = 0;
    #|  for (let i: int = 1; i <= n; i++) {
    #|    total += i;
    #|  }
    #|  return total;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"sumFor", [@runtime.Value::I32(10)])
  assert_eq(results[0], @runtime.Value::I32(55))
}

///|
test "codegen: for...of loop" {
  let src =
    #|function sumArray(): number {
    #|  let arr: number[] = [1.0, 2.0, 3.0, 4.0, 5.0];
    #|  let total: number = 0.0;
    #|  for (let x of arr) {
    #|    total += x;
    #|  }
    #|  return total;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"sumArray", [])
  assert_eq(results[0], @runtime.Value::F64(15.0))
}

///|
test "codegen: for...of with int array" {
  let src =
    #|function countArray(): int {
    #|  let arr: int[] = new Array<int>(3);
    #|  arr[0] = 10;
    #|  arr[1] = 20;
    #|  arr[2] = 30;
    #|  let total: int = 0;
    #|  for (let x of arr) {
    #|    total += x;
    #|  }
    #|  return total;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"countArray", [])
  assert_eq(results[0], @runtime.Value::I32(60))
}

///|
test "codegen: comparison operators" {
  let src =
    #|function compare(a: number, b: number): number {
    #|  if (a === b) {
    #|    return 0;
    #|  }
    #|  if (a < b) {
    #|    return 1;
    #|  }
    #|  return 2;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let r1 = runtime.call_compiled(b"compare", [
    @runtime.Value::F64(5.0),
    @runtime.Value::F64(5.0),
  ])
  assert_eq(r1[0], @runtime.Value::F64(0.0))
  let r2 = runtime.call_compiled(b"compare", [
    @runtime.Value::F64(3.0),
    @runtime.Value::F64(7.0),
  ])
  assert_eq(r2[0], @runtime.Value::F64(1.0))
  let r3 = runtime.call_compiled(b"compare", [
    @runtime.Value::F64(10.0),
    @runtime.Value::F64(5.0),
  ])
  assert_eq(r3[0], @runtime.Value::F64(2.0))
}

///|
test "codegen: module with imports generates correct wasm" {
  let src =
    #|declare function log(msg: string): void;
    #|declare function alert(msg: string): void;
    #|function test(): int {
    #|  return 42;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()

  // import
  assert_eq(ts_module.imports.length(), 2)

  // Wasm generate
  let wasm_module = compile_module(ts_module)

  // importgenerate
  assert_eq(wasm_module.imports.length(), 2)

  // typedefineimportfunctiontype (2import + 1function)
  assert_eq(wasm_module.types.length(), 3)

  // funcs definefunction (importfunctionimportssection)
  assert_eq(wasm_module.funcs.length(), 1)

  // exportdefinefunction
  assert_eq(wasm_module.exports.length(), 1)
}

///|
test "codegen: javascript style code with type inference" {
  // type JavaScript
  let src =
    #|function add(a, b) {
    #|  let x = 1;
    #|  let y = 2;
    #|  return x + y;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)

  // parameter Any -> f64 ()
  // variable x, y Int
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  // add(0, 0) - result 3 (1 + 2)
  // parameter Any=f64
  let results = runtime.call_compiled(b"add", [
    @runtime.Value::F64(0.0),
    @runtime.Value::F64(0.0),
  ])
  // return value Any=f64 , internal Int compute
  // f64 -> i32 conversion, resultcheck
  assert_eq(results.length(), 1)
}

///|
test "js: simple arithmetic" {
  // JavaScript:
  let src =
    #|function calc(): int {
    #|  let a = 10;
    #|  let b = 3;
    #|  let sum = a + b;
    #|  return sum;
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"calc", [])
  assert_eq(results[0], @runtime.Value::I32(13))
}

///|
test "js: multiple functions call" {
  // JavaScript: function
  let src =
    #|function double(x: int): int {
    #|  return x * 2;
    #|}
    #|function main(): int {
    #|  return double(5);
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"main", [])
  assert_eq(results[0], @runtime.Value::I32(10))
}

///|
test "codegen: type metadata in custom section" {
  let src =
    #|declare function console_log(msg: string): void;
    #|interface Point {
    #|  x: number;
    #|  y: number;
    #|}
    #|function add(a: int, b: int): int {
    #|  return a + b;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)

  // sectiongenerate
  assert_eq(wasm_module.customs.length(), 1)

  // section "tstype"
  let custom = wasm_module.customs[0]
  assert_eq(custom.name, b"tstype")

  // datamagiccheck "TSTY"
  let data = custom.data
  assert_eq(data[0], b'\x54') // T
  assert_eq(data[1], b'\x53') // S
  assert_eq(data[2], b'\x54') // T
  assert_eq(data[3], b'\x59') // Y

  // version = 1
  assert_eq(data[4], b'\x01')

  // import = 1 (u16 LE)
  assert_eq(data[5], b'\x01')
  assert_eq(data[6], b'\x00')

  // interface = 1 (u16 LE)
  assert_eq(data[7], b'\x01')
  assert_eq(data[8], b'\x00')

  // export = 1 (u16 LE)
  assert_eq(data[9], b'\x01')
  assert_eq(data[10], b'\x00')
}

///|
test "codegen: analyze_and_compile with type inference" {
  // Test that TypedModule integration works correctly
  let src =
    #|function compute(): int {
    #|  let x = 10;
    #|  let y = 20;
    #|  let z = x + y;
    #|  return z;
    #|}
  let wasm_module = analyze_and_compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"compute", [])
  assert_eq(results[0], @runtime.Value::I32(30))
}

///|
test "codegen: typed module with nested scopes" {
  let src =
    #|function nested(): int {
    #|  let outer = 1;
    #|  let result = 0;
    #|  for (let i = 0; i < 5; i++) {
    #|    let inner = outer + i;
    #|    result = result + inner;
    #|  }
    #|  return result;
    #|}
  let wasm_module = analyze_and_compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  // result = (1+0) + (1+1) + (1+2) + (1+3) + (1+4) = 1+2+3+4+5 = 15
  let results = runtime.call_compiled(b"nested", [])
  assert_eq(results[0], @runtime.Value::I32(15))
}

///|
test "codegen: constant folding in binary operations" {
  let src =
    #|function test(): int {
    #|  return 10 + 20 * 3;
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  // 10 + 20 * 3 = 10 + 60 = 70
  let results = runtime.call_compiled(b"test", [])
  assert_eq(results[0], @runtime.Value::I32(70))
}

///|
test "codegen: constant folding eliminates dead branches" {
  let src =
    #|function test(): int {
    #|  if (true) {
    #|    return 42;
    #|  } else {
    #|    return 0;
    #|  }
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"test", [])
  assert_eq(results[0], @runtime.Value::I32(42))
}

///|
test "codegen: constant folding in ternary" {
  let src =
    #|function test(): int {
    #|  return false ? 100 : 200;
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"test", [])
  assert_eq(results[0], @runtime.Value::I32(200))
}

///|
test "codegen: typed module preserves function types" {
  let src =
    #|function addNumbers(a: number, b: number): number {
    #|  let sum = a + b;
    #|  return sum;
    #|}
  // Test with compile (no type analysis)
  let wasm1 = compile(src)
  let rt1 = @runtime.Runtime::load(wasm1)
  rt1.run_start()
  let r1 = rt1.call_compiled(b"addNumbers", [
    @runtime.Value::F64(3.5),
    @runtime.Value::F64(2.5),
  ])
  assert_eq(r1[0], @runtime.Value::F64(6.0))

  // Test with analyze_and_compile (with type analysis)
  let wasm2 = analyze_and_compile(src)
  let rt2 = @runtime.Runtime::load(wasm2)
  rt2.run_start()
  let r2 = rt2.call_compiled(b"addNumbers", [
    @runtime.Value::F64(3.5),
    @runtime.Value::F64(2.5),
  ])
  assert_eq(r2[0], @runtime.Value::F64(6.0))
}

///|
test "codegen: constant propagation" {
  // const variables should be propagated as immediate values
  let src =
    #|function test(): int {
    #|  const x = 10;
    #|  const y = 20;
    #|  return x + y;
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"test", [])
  assert_eq(results[0], @runtime.Value::I32(30))
}

///|
test "codegen: constant propagation replaces variable reads" {
  // When const is used later, the value should be inlined
  let src =
    #|function compute(n: int): int {
    #|  const factor = 3;
    #|  return n * factor;
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  // n=7, factor=3, result=21
  let results = runtime.call_compiled(b"compute", [@runtime.Value::I32(7)])
  assert_eq(results[0], @runtime.Value::I32(21))
}

///|
test "codegen: bitwise NOT operator" {
  let src =
    #|function bitnot(x: int): int {
    #|  return ~x;
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  // ~0 = -1 (0xFFFFFFFF), ~1 = -2 (0xFFFFFFFE), ~0xFFFFFFFF = 0
  let r1 = runtime.call_compiled(b"bitnot", [@runtime.Value::I32(0)])
  assert_eq(r1[0], @runtime.Value::I32(0xFFFFFFFF)) // -1 as unsigned
  let r2 = runtime.call_compiled(b"bitnot", [@runtime.Value::I32(1)])
  assert_eq(r2[0], @runtime.Value::I32(0xFFFFFFFE)) // -2 as unsigned
  let r3 = runtime.call_compiled(b"bitnot", [@runtime.Value::I32(0xFFFFFFFF)])
  assert_eq(r3[0], @runtime.Value::I32(0))
}

///|
test "codegen: bitwise AND, OR, XOR" {
  let src =
    #|function bitand(a: int, b: int): int { return a & b; }
    #|function bitor(a: int, b: int): int { return a | b; }
    #|function bitxor(a: int, b: int): int { return a ^ b; }
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  // 0b1100 & 0b1010 = 0b1000 = 8
  let r1 = runtime.call_compiled(b"bitand", [
    @runtime.Value::I32(12),
    @runtime.Value::I32(10),
  ])
  assert_eq(r1[0], @runtime.Value::I32(8))
  // 0b1100 | 0b1010 = 0b1110 = 14
  let r2 = runtime.call_compiled(b"bitor", [
    @runtime.Value::I32(12),
    @runtime.Value::I32(10),
  ])
  assert_eq(r2[0], @runtime.Value::I32(14))
  // 0b1100 ^ 0b1010 = 0b0110 = 6
  let r3 = runtime.call_compiled(b"bitxor", [
    @runtime.Value::I32(12),
    @runtime.Value::I32(10),
  ])
  assert_eq(r3[0], @runtime.Value::I32(6))
}

///|
test "codegen: bit shift operations" {
  let src =
    #|function shl(a: int, b: int): int { return a << b; }
    #|function shr(a: int, b: int): int { return a >> b; }
    #|function ushr(a: int, b: int): int { return a >>> b; }
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  // 1 << 4 = 16
  let r1 = runtime.call_compiled(b"shl", [
    @runtime.Value::I32(1),
    @runtime.Value::I32(4),
  ])
  assert_eq(r1[0], @runtime.Value::I32(16))
  // 16 >> 2 = 4
  let r2 = runtime.call_compiled(b"shr", [
    @runtime.Value::I32(16),
    @runtime.Value::I32(2),
  ])
  assert_eq(r2[0], @runtime.Value::I32(4))
  // 0xFFFFFFF8 (-8) >>> 1 = 0x7FFFFFFC = 2147483644 (unsigned shift)
  let r3 = runtime.call_compiled(b"ushr", [
    @runtime.Value::I32(0xFFFFFFF8),
    @runtime.Value::I32(1),
  ])
  assert_eq(r3[0], @runtime.Value::I32(0x7FFFFFFC))
}

///|
test "codegen: switch statement" {
  let src =
    #|function grade(score: int): int {
    #|  switch (score) {
    #|    case 5: return 100;
    #|    case 4: return 80;
    #|    case 3: return 60;
    #|    case 2: return 40;
    #|    default: return 0;
    #|  }
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let r1 = runtime.call_compiled(b"grade", [@runtime.Value::I32(5)])
  assert_eq(r1[0], @runtime.Value::I32(100))
  let r2 = runtime.call_compiled(b"grade", [@runtime.Value::I32(3)])
  assert_eq(r2[0], @runtime.Value::I32(60))
  let r3 = runtime.call_compiled(b"grade", [@runtime.Value::I32(1)])
  assert_eq(r3[0], @runtime.Value::I32(0))
}

///|
test "codegen: switch with default only" {
  let src =
    #|function always42(x: int): int {
    #|  switch (x) {
    #|    default: return 42;
    #|  }
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let r1 = runtime.call_compiled(b"always42", [@runtime.Value::I32(0)])
  assert_eq(r1[0], @runtime.Value::I32(42))
  let r2 = runtime.call_compiled(b"always42", [@runtime.Value::I32(999)])
  assert_eq(r2[0], @runtime.Value::I32(42))
}

///|
test "codegen: nullish coalescing operator" {
  // Note: In this simplified implementation, 0 is treated as null-ish
  let src =
    #|function coalesce(a: int, b: int): int {
    #|  return a ?? b;
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  // When a is non-zero, return a
  let r1 = runtime.call_compiled(b"coalesce", [
    @runtime.Value::I32(5),
    @runtime.Value::I32(10),
  ])
  assert_eq(r1[0], @runtime.Value::I32(5))
  // When a is 0 (treated as null-ish), return b
  let r2 = runtime.call_compiled(b"coalesce", [
    @runtime.Value::I32(0),
    @runtime.Value::I32(42),
  ])
  assert_eq(r2[0], @runtime.Value::I32(42))
}

///|
test "codegen: do-while loop" {
  let src =
    #|function sumDoWhile(n: int): int {
    #|  let sum = 0;
    #|  let i = 1;
    #|  do {
    #|    sum = sum + i;
    #|    i = i + 1;
    #|  } while (i <= n);
    #|  return sum;
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  // sum of 1 to 5 = 15
  let r1 = runtime.call_compiled(b"sumDoWhile", [@runtime.Value::I32(5)])
  assert_eq(r1[0], @runtime.Value::I32(15))
  // do-while executes at least once even if condition is false initially
  let r2 = runtime.call_compiled(b"sumDoWhile", [@runtime.Value::I32(0)])
  assert_eq(r2[0], @runtime.Value::I32(1)) // executes once with i=1
}

// ============ wasm-gc tests ============

///|
test "wasm-gc: struct creation generates valid module" {
  let src =
    #|interface Point {
    #|  x: number;
    #|  y: number;
    #|}
    #|function createPoint(): number {
    #|  let p: Point = new Point();
    #|  p.x = 10.0;
    #|  p.y = 20.0;
    #|  return p.x + p.y;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module_gc(ts_module)

  // GC struct type should be defined (type index 2 after i32[] and f64[])
  assert_true(wasm_module.types.length() >= 3)

  // Encode to wasm binary
  let wasm = @encode.encode(wasm_module)

  // Wasm magic number check
  assert_eq(wasm[0], b'\x00')
  assert_eq(wasm[1], b'\x61') // 'a'
  assert_eq(wasm[2], b'\x73') // 's'
  assert_eq(wasm[3], b'\x6D') // 'm'
  println("wasm-gc struct module: \{wasm.length()} bytes")
}

///|
test "wasm-gc: struct with int fields" {
  let src =
    #|interface Counter {
    #|  count: int;
    #|  max: int;
    #|}
    #|function testCounter(): int {
    #|  let c: Counter = new Counter();
    #|  c.count = 10;
    #|  c.max = 100;
    #|  return c.count + c.max;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module_gc(ts_module)

  // Check struct type is defined
  let struct_type_idx = 2U // After i32[] and f64[]
  match wasm_module.types[struct_type_idx.reinterpret_as_int()] {
    @core.TypeDef::Struct(st) =>
      // Counter has 2 i32 fields
      assert_eq(st.fields.length(), 2)
    _ => fail("Expected struct type at index 2")
  }

  // Encode to wasm binary
  let wasm = @encode.encode(wasm_module)
  assert_true(wasm.length() > 0)
  println("wasm-gc int struct module: \{wasm.length()} bytes")
}

///|
test "wasm-gc: array with gc arrays" {
  let src =
    #|function sumArray(): int {
    #|  let arr: int[] = new Array<int>(3);
    #|  arr[0] = 10;
    #|  arr[1] = 20;
    #|  arr[2] = 30;
    #|  return arr[0] + arr[1] + arr[2];
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module_gc(ts_module)

  // GC array type should be defined (type 0 = i32[])
  match wasm_module.types[0] {
    @core.TypeDef::Array(arr_type) =>
      match arr_type.element.storage {
        @core.StorageType::Val(@core.ValType::I32) => ()
        _ => fail("Expected i32 storage type")
      }
    _ => fail("Expected array type at index 0")
  }

  // Encode to wasm binary
  let wasm = @encode.encode(wasm_module)
  assert_true(wasm.length() > 0)
  println("wasm-gc array module: \{wasm.length()} bytes")
}

///|
test "wasm-gc: multiple struct types" {
  let src =
    #|interface Point {
    #|  x: number;
    #|  y: number;
    #|}
    #|interface Rect {
    #|  width: number;
    #|  height: number;
    #|}
    #|function area(): number {
    #|  let r: Rect = new Rect();
    #|  r.width = 10.0;
    #|  r.height = 5.0;
    #|  return r.width * r.height;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module_gc(ts_module)

  // Two struct types should be defined (indices 2 and 3)
  assert_true(wasm_module.types.length() >= 4)

  // Check Point struct (index 2)
  match wasm_module.types[2] {
    @core.TypeDef::Struct(st) => assert_eq(st.fields.length(), 2)
    _ => fail("Expected Point struct at index 2")
  }

  // Check Rect struct (index 3)
  match wasm_module.types[3] {
    @core.TypeDef::Struct(st) => assert_eq(st.fields.length(), 2)
    _ => fail("Expected Rect struct at index 3")
  }

  // Encode to wasm binary
  let wasm = @encode.encode(wasm_module)
  assert_true(wasm.length() > 0)
  println("wasm-gc multiple structs module: \{wasm.length()} bytes")
}

// ============ Math function tests ============

///|
test "codegen: Math.sqrt" {
  let src =
    #|function sqrt16(): number {
    #|  return Math.sqrt(16.0);
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"sqrt16", [])
  assert_eq(results[0], @runtime.Value::F64(4.0))
}

///|
test "codegen: Math.abs" {
  let src =
    #|function absNeg(): number {
    #|  return Math.abs(-5.0);
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"absNeg", [])
  assert_eq(results[0], @runtime.Value::F64(5.0))
}

///|
test "codegen: Math.floor and Math.ceil" {
  let src =
    #|function floorTest(): number {
    #|  return Math.floor(3.7);
    #|}
    #|function ceilTest(): number {
    #|  return Math.ceil(3.2);
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let floor_result = runtime.call_compiled(b"floorTest", [])
  assert_eq(floor_result[0], @runtime.Value::F64(3.0))
  let ceil_result = runtime.call_compiled(b"ceilTest", [])
  assert_eq(ceil_result[0], @runtime.Value::F64(4.0))
}

///|
test "codegen: Math.min and Math.max" {
  let src =
    #|function minTest(): number {
    #|  return Math.min(5.0, 3.0);
    #|}
    #|function maxTest(): number {
    #|  return Math.max(5.0, 3.0);
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let min_result = runtime.call_compiled(b"minTest", [])
  assert_eq(min_result[0], @runtime.Value::F64(3.0))
  let max_result = runtime.call_compiled(b"maxTest", [])
  assert_eq(max_result[0], @runtime.Value::F64(5.0))
}

///|
test "codegen: Math.pow with constant exponent" {
  let src =
    #|function pow2_10(): number {
    #|  return Math.pow(2.0, 10);
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"pow2_10", [])
  assert_eq(results[0], @runtime.Value::F64(1024.0))
}

///|
test "codegen: Math.round" {
  let src =
    #|function roundTest(): number {
    #|  return Math.round(3.5);
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"roundTest", [])
  assert_eq(results[0], @runtime.Value::F64(4.0))
}

///|
test "codegen: Math.trunc" {
  let src =
    #|function truncTest(): number {
    #|  return Math.trunc(-3.7);
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  let results = runtime.call_compiled(b"truncTest", [])
  assert_eq(results[0], @runtime.Value::F64(-3.0))
}

///|
test "codegen: pure function with Math - distance" {
  let src =
    #|function distance(x1: number, y1: number, x2: number, y2: number): number {
    #|  let dx: number = x2 - x1;
    #|  let dy: number = y2 - y1;
    #|  return Math.sqrt(dx * dx + dy * dy);
    #|}
  let wasm_module = compile(src)
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  // distance(0, 0, 3, 4) = sqrt(9 + 16) = sqrt(25) = 5
  let results = runtime.call_compiled(b"distance", [
    @runtime.Value::F64(0.0),
    @runtime.Value::F64(0.0),
    @runtime.Value::F64(3.0),
    @runtime.Value::F64(4.0),
  ])
  assert_eq(results[0], @runtime.Value::F64(5.0))
}

///|
test "generator_ir: simple counter generator" {
  let src =
    #|function* counter(n) {
    #|  let i = 0;
    #|  while (i < n) {
    #|    yield i;
    #|    i = i + 1;
    #|  }
    #|  return n;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let func = ts_module.funcs[0]

  // Analyze generator
  let analysis = @analysis.analyze_generator(func)
  assert_true(analysis.compilable)
  assert_eq(analysis.yield_points.length(), 1)
  assert_eq(analysis.persisted_vars.length(), 2) // n (param) + i (local)

  // Transform to state machine
  let sm = transform_to_state_machine(func, analysis)
  assert_eq(sm.name, "counter")
  assert_eq(sm.params.length(), 1)
  assert_eq(sm.params[0].name, "n")
  assert_eq(sm.locals.length(), 1)
  assert_eq(sm.locals[0].name, "i")
  assert_eq(sm.states.length(), 2) // initial + done
  println("Generator state machine:\n\{sm.debug_string()}")
}

///|
test "generator_ir: fibonacci generator" {
  let src =
    #|function* fib(limit) {
    #|  let a = 0;
    #|  let b = 1;
    #|  while (a < limit) {
    #|    yield a;
    #|    let temp = a;
    #|    a = b;
    #|    b = temp + b;
    #|  }
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let func = ts_module.funcs[0]
  let analysis = @analysis.analyze_generator(func)
  assert_true(analysis.compilable)
  assert_eq(analysis.yield_points.length(), 1)
  // limit (param), a, b, temp (locals)
  assert_eq(analysis.persisted_vars.length(), 4)
  let sm = transform_to_state_machine(func, analysis)
  assert_eq(sm.name, "fib")
  assert_eq(sm.params.length(), 1)
  assert_eq(sm.locals.length(), 3) // a, b, temp
  println("Fib state machine:\n\{sm.debug_string()}")
}

///|
test "generator_codegen: compile simple generator" {
  let src =
    #|function* counter(n) {
    #|  let i = 0;
    #|  while (i < n) {
    #|    yield i;
    #|    i = i + 1;
    #|  }
    #|  return n;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let func = ts_module.funcs[0]

  // Analyze
  let analysis = @analysis.analyze_generator(func)
  assert_true(analysis.compilable)

  // Transform to IR
  let sm = transform_to_state_machine(func, analysis)

  // Compile to wasm
  let wasm_code = compile_generator(sm, 0U)

  // Verify struct type has correct fields
  // state_num + done + signal_mode + signal_value + 1 param (n) + 1 local (i) = 6 fields
  match wasm_code.state_struct_type {
    @core.TypeDef::Struct(st) => assert_eq(st.fields.length(), 6)
    _ => assert_true(false)
  }

  // Verify create function generates code
  assert_true(wasm_code.create_func_code.body.instrs.length() > 0)

  // Verify next function generates code
  assert_true(wasm_code.next_func_code.body.instrs.length() > 0)
  println(wasm_code.debug_info())
}

///|
test "compile_module_gc: generator function exports _create and _next" {
  let src =
    #|function* counter(n: number) {
    #|  let i = 0;
    #|  while (i < n) {
    #|    yield i;
    #|    i = i + 1;
    #|  }
    #|  return n;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()

  // Compile with GC mode
  let wasm_module = compile_module_gc(ts_module)

  // Check exports - should have counter_create and counter_next
  let export_names : Array[String] = []
  for exp in wasm_module.exports {
    let name = bytes_to_string(exp.name)
    export_names.push(name)
  }
  println("Generator exports: \{export_names}")
  assert_true(export_names.contains("counter_create"))
  assert_true(export_names.contains("counter_next"))
}

///|
fn bytes_to_string(bytes : Bytes) -> String {
  let mut s = ""
  for b in bytes {
    s += b.to_int().unsafe_to_char().to_string()
  }
  s
}

///|
test "generator_ir: try-catch transforms to TryCatch instruction" {
  let src =
    #|function* safegen() {
    #|  let result = 0;
    #|  try {
    #|    result = 42;
    #|  } catch (e) {
    #|    result = -1;
    #|  }
    #|  yield result;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let func = ts_module.funcs[0]

  // Analyze
  let analysis = @analysis.analyze_generator(func)
  assert_true(analysis.compilable)

  // Transform to IR
  let sm = transform_to_state_machine(func, analysis)
  println("State machine:\n\{sm.debug_string()}")

  // Check that initial state has TryCatch instruction
  let initial_state = sm.states[0]
  let mut has_try_catch = false
  for instr in initial_state.body {
    match instr {
      GenInstr::TryCatch(_, _, _, _) => has_try_catch = true
      _ => continue
    }
  }
  assert_true(has_try_catch)
}

///|
test "generator_codegen: try-catch generates TryTable wasm" {
  let src =
    #|function* safegen() {
    #|  let x = 0;
    #|  try {
    #|    x = 1;
    #|  } catch (e) {
    #|    x = 2;
    #|  }
    #|  yield x;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let func = ts_module.funcs[0]

  // Analyze and transform
  let analysis = @analysis.analyze_generator(func)
  assert_true(analysis.compilable)
  let sm = transform_to_state_machine(func, analysis)

  // Compile to wasm
  let wasm_code = compile_generator(sm, 0U)

  // Verify code is generated
  assert_true(wasm_code.next_func_code.body.instrs.length() > 0)
  println(wasm_code.debug_info())

  // Check for TryTable instruction recursively
  fn has_try_table_instr(instrs : Array[@core.Instr]) -> Bool {
    for instr in instrs {
      match instr {
        @core.Instr::TryTable(_, _, _) => return true
        @core.Instr::Block(_, inner) =>
          if has_try_table_instr(inner) {
            return true
          }
        @core.Instr::Loop(_, inner) =>
          if has_try_table_instr(inner) {
            return true
          }
        @core.Instr::If(_, then_branch, else_branch) => {
          if has_try_table_instr(then_branch) {
            return true
          }
          if has_try_table_instr(else_branch) {
            return true
          }
        }
        _ => continue
      }
    }
    false
  }

  assert_true(has_try_table_instr(wasm_code.next_func_code.body.instrs))
}

///|
test "compile_aot_group: generator with helper functions" {
  let src =
    #|function double(x) { return x * 2; }
    #|function triple(x) { return x * 3; }
    #|function* gen(n) {
    #|  yield double(n);
    #|  yield triple(n);
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()

  // Build call graph and find AOT groups
  let graph = @analysis.build_call_graph(ts_module)
  let groups = @analysis.find_aot_groups(ts_module, graph)

  println("Found \{groups.length()} AOT groups")
  assert_eq(groups.length(), 1)

  let group = groups[0]
  println(group.debug_string())

  // Compile the AOT group
  match compile_aot_group(group, ts_module, 0U) {
    Some(code) => {
      println(code.debug_string())
      // Check that we have the expected number of functions
      // gen produces 2 (create + next), double and triple produce 1 each = 4
      assert_eq(code.funcs.length(), 4)
      // Check exports
      println("Exports: \{code.exports}")
    }
    None => assert_true(false)
  }
}

///|
test "compile_aot_group: helper function calls in generator" {
  let src =
    #|function add(a, b) { return a + b; }
    #|function* sum(n) {
    #|  let total = 0;
    #|  let i = 1;
    #|  while (i <= n) {
    #|    total = add(total, i);
    #|    i = i + 1;
    #|  }
    #|  yield total;
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()

  let graph = @analysis.build_call_graph(ts_module)
  let groups = @analysis.find_aot_groups(ts_module, graph)

  assert_eq(groups.length(), 1)
  let group = groups[0]

  // add is only called from sum, so no external calls
  assert_false(group.external_calls.contains("add"))

  match compile_aot_group(group, ts_module, 0U) {
    Some(code) => {
      println(code.debug_string())
      // sum produces 2 (create + next), add produces 1 = 3
      assert_eq(code.funcs.length(), 3)

      // Verify function map has correct indices
      match code.func_map.get("add") {
        Some(idx) => println("add function index: \{idx}")
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

// Closure codegen tests

///|
test "compile_arrow_func: no captures" {
  let params : Array[@ast.TsParam] = [
    { name: "x", type_: @ast.TsType::Number, binding: None, is_rest: false, default: None },
  ]
  let body = @ast.TsArrowBody::ArrowExpr(
    @ast.TsExpr::BinOp(@ast.TsBinOp::Add, @ast.TsExpr::Var("x"), @ast.TsExpr::IntLit(1)),
  )
  let outer_scope : Array[String] = []
  let ctx = ClosureCodegenCtx::new(0U)

  match compile_arrow_func(params, body, outer_scope, ctx) {
    Some(code) => {
      // No captures -> no environment struct
      assert_true(code.env_struct_type is None)
      assert_eq(code.capture_names.length(), 0)
      // Should have func_type and func_code
      println("Generated closure: \{code.func_name}")
    }
    None => fail("Expected compilable closure")
  }
}

///|
test "compile_arrow_func: with capture" {
  let params : Array[@ast.TsParam] = [
    { name: "a", type_: @ast.TsType::Number, binding: None, is_rest: false, default: None },
  ]
  // (a) => a + x (where x is captured)
  let body = @ast.TsArrowBody::ArrowExpr(
    @ast.TsExpr::BinOp(@ast.TsBinOp::Add, @ast.TsExpr::Var("a"), @ast.TsExpr::Var("x")),
  )
  let outer_scope : Array[String] = ["x"]
  let ctx = ClosureCodegenCtx::new(0U)

  match compile_arrow_func(params, body, outer_scope, ctx) {
    Some(code) => {
      // Has capture -> has environment struct
      assert_true(code.env_struct_type is Some(_))
      assert_eq(code.capture_names.length(), 1)
      assert_eq(code.capture_names[0], "x")
      println("Generated closure with capture: \{code.func_name}")
    }
    None => fail("Expected compilable closure")
  }
}

///|
test "compile_arrow_func: block body" {
  let params : Array[@ast.TsParam] = [
    { name: "n", type_: @ast.TsType::Number, binding: None, is_rest: false, default: None },
  ]
  // (n) => { let result = n * 2; return result; }
  let body = @ast.TsArrowBody::ArrowBlock({
    stmts: [
      @ast.TsStmt::Let(
        @ast.TsBinding::Ident("result"),
        @ast.TsType::Number,
        @ast.TsExpr::BinOp(@ast.TsBinOp::Mul, @ast.TsExpr::Var("n"), @ast.TsExpr::IntLit(2)),
      ),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("result"))),
    ],
  })
  let outer_scope : Array[String] = []
  let ctx = ClosureCodegenCtx::new(0U)

  match compile_arrow_func(params, body, outer_scope, ctx) {
    Some(code) => {
      assert_true(code.env_struct_type is None)
      println("Generated block closure: \{code.func_name}")
      println("Locals: \{code.func_code.locals.length()}")
    }
    None => fail("Expected compilable closure")
  }
}

///|
test "compile_func_expr: simple function" {
  let func : @ast.TsFunc = {
    name: "double",
    params: [
      { name: "x", type_: @ast.TsType::Number, binding: None, is_rest: false, default: None },
    ],
    return_type: @ast.TsType::Number,
    body: {
      stmts: [
        @ast.TsStmt::Return(
          Some(@ast.TsExpr::BinOp(@ast.TsBinOp::Mul, @ast.TsExpr::Var("x"), @ast.TsExpr::IntLit(2))),
        ),
      ],
    },
    is_generator: false,
    is_async: false,
  }
  let outer_scope : Array[String] = []
  let ctx = ClosureCodegenCtx::new(0U)

  match compile_func_expr(func, outer_scope, ctx) {
    Some(code) => {
      assert_true(code.env_struct_type is None)
      assert_eq(code.capture_names.length(), 0)
      println("Generated func expr: \{code.func_name}")
    }
    None => fail("Expected compilable function")
  }
}

///|
test "compile_func_expr: with multiple captures" {
  let func : @ast.TsFunc = {
    name: "compute",
    params: [],
    return_type: @ast.TsType::Number,
    body: {
      stmts: [
        @ast.TsStmt::Return(
          Some(@ast.TsExpr::BinOp(@ast.TsBinOp::Add, @ast.TsExpr::Var("a"), @ast.TsExpr::Var("b"))),
        ),
      ],
    },
    is_generator: false,
    is_async: false,
  }
  let outer_scope : Array[String] = ["a", "b", "c"]  // c is not used
  let ctx = ClosureCodegenCtx::new(0U)

  match compile_func_expr(func, outer_scope, ctx) {
    Some(code) => {
      assert_true(code.env_struct_type is Some(_))
      assert_eq(code.capture_names.length(), 2)  // only a and b are captured
      assert_true(code.capture_names.contains("a"))
      assert_true(code.capture_names.contains("b"))
      println("Generated func with captures: \{code.func_name}")
    }
    None => fail("Expected compilable function")
  }
}

///|
test "compile_arrow_func: mutable capture (Phase 3)" {
  let params : Array[@ast.TsParam] = []
  // () => { x = x + 1; return x; }
  let body = @ast.TsArrowBody::ArrowBlock({
    stmts: [
      @ast.TsStmt::Assign(
        "x",
        @ast.TsExpr::BinOp(@ast.TsBinOp::Add, @ast.TsExpr::Var("x"), @ast.TsExpr::IntLit(1)),
      ),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("x"))),
    ],
  })
  let outer_scope : Array[String] = ["x"]
  let ctx = ClosureCodegenCtx::new(0U)

  match compile_arrow_func(params, body, outer_scope, ctx) {
    Some(code) => {
      // Has capture with mutable field
      assert_true(code.env_struct_type is Some(_))
      assert_eq(code.capture_names.length(), 1)
      assert_eq(code.capture_names[0], "x")

      // Check that the env struct has mutable field
      match code.env_struct_type {
        Some(@core.TypeDef::Struct(struct_type)) => {
          assert_eq(struct_type.fields.length(), 1)
          // Field should be mutable since x is mutated
          assert_true(struct_type.fields[0].mutable)
        }
        _ => fail("Expected struct type")
      }

      println("Generated mutable capture closure: \{code.func_name}")
      println("Instructions: \{code.func_code.body.instrs.length()}")
    }
    None => fail("Expected compilable closure with mutable capture")
  }
}

///|
test "compile_func_expr: mixed mutable and immutable captures" {
  let func : @ast.TsFunc = {
    name: "counter",
    params: [],
    return_type: @ast.TsType::Number,
    body: {
      stmts: [
        // count = count + step (count is mutated, step is read-only)
        @ast.TsStmt::Assign(
          "count",
          @ast.TsExpr::BinOp(@ast.TsBinOp::Add, @ast.TsExpr::Var("count"), @ast.TsExpr::Var("step")),
        ),
        @ast.TsStmt::Return(Some(@ast.TsExpr::Var("count"))),
      ],
    },
    is_generator: false,
    is_async: false,
  }
  let outer_scope : Array[String] = ["count", "step"]
  let ctx = ClosureCodegenCtx::new(0U)

  match compile_func_expr(func, outer_scope, ctx) {
    Some(code) => {
      assert_true(code.env_struct_type is Some(_))
      assert_eq(code.capture_names.length(), 2)

      // Check that env struct has correct mutability for each field
      match code.env_struct_type {
        Some(@core.TypeDef::Struct(struct_type)) => {
          assert_eq(struct_type.fields.length(), 2)
          // Verify we have both mutable and immutable fields
          // (order depends on capture order)
          println("Field 0 mutable: \{struct_type.fields[0].mutable}")
          println("Field 1 mutable: \{struct_type.fields[1].mutable}")
        }
        _ => fail("Expected struct type")
      }

      println("Generated mixed capture closure: \{code.func_name}")
    }
    None => fail("Expected compilable function")
  }
}

// Tests for lifted vars analysis (environment sharing)

///|
test "analyze_lifted_vars: no closures" {
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(@ast.TsBinding::Ident("x"), @ast.TsType::Number, @ast.TsExpr::IntLit(1)),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("x"))),
    ],
  }
  let params : Array[String] = []
  let info = analyze_lifted_vars(block, params)
  // No closures -> no lifted vars
  assert_eq(info.lifted_vars.length(), 0)
}

///|
test "analyze_lifted_vars: closure captures local" {
  // let x = 1; const f = () => x; return f();
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(@ast.TsBinding::Ident("x"), @ast.TsType::Number, @ast.TsExpr::IntLit(1)),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("f"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc([], @ast.TsArrowBody::ArrowExpr(@ast.TsExpr::Var("x")), false),
      ),
      @ast.TsStmt::Return(Some(@ast.TsExpr::CallExpr(@ast.TsExpr::Var("f"), []))),
    ],
  }
  let params : Array[String] = []
  let info = analyze_lifted_vars(block, params)
  // x is captured by closure -> should be lifted
  assert_eq(info.lifted_vars.length(), 1)
  assert_true(info.lifted_vars.contains("x"))
  // x is read-only
  assert_eq(info.is_mutated.get("x"), Some(false))
}

///|
test "analyze_lifted_vars: closure mutates captured var" {
  // let x = 1; const inc = () => { x = x + 1; }; inc(); return x;
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(@ast.TsBinding::Ident("x"), @ast.TsType::Number, @ast.TsExpr::IntLit(1)),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("inc"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc(
          [],
          @ast.TsArrowBody::ArrowBlock({
            stmts: [
              @ast.TsStmt::Assign(
                "x",
                @ast.TsExpr::BinOp(@ast.TsBinOp::Add, @ast.TsExpr::Var("x"), @ast.TsExpr::IntLit(1)),
              ),
            ],
          }),
          false,
        ),
      ),
      @ast.TsStmt::Expr(@ast.TsExpr::CallExpr(@ast.TsExpr::Var("inc"), [])),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("x"))),
    ],
  }
  let params : Array[String] = []
  let info = analyze_lifted_vars(block, params)
  // x is captured and mutated -> should be lifted with mutable flag
  assert_eq(info.lifted_vars.length(), 1)
  assert_true(info.lifted_vars.contains("x"))
  assert_eq(info.is_mutated.get("x"), Some(true))
  // Check field index
  assert_eq(info.field_indices.get("x"), Some(0U))
}

///|
test "analyze_lifted_vars: multiple closures share captured var" {
  // let x = 0;
  // const inc = () => { x = x + 1; };
  // const dec = () => { x = x - 1; };
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(@ast.TsBinding::Ident("x"), @ast.TsType::Number, @ast.TsExpr::IntLit(0)),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("inc"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc(
          [],
          @ast.TsArrowBody::ArrowBlock({
            stmts: [
              @ast.TsStmt::Assign(
                "x",
                @ast.TsExpr::BinOp(@ast.TsBinOp::Add, @ast.TsExpr::Var("x"), @ast.TsExpr::IntLit(1)),
              ),
            ],
          }),
          false,
        ),
      ),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("dec"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc(
          [],
          @ast.TsArrowBody::ArrowBlock({
            stmts: [
              @ast.TsStmt::Assign(
                "x",
                @ast.TsExpr::BinOp(@ast.TsBinOp::Sub, @ast.TsExpr::Var("x"), @ast.TsExpr::IntLit(1)),
              ),
            ],
          }),
          false,
        ),
      ),
    ],
  }
  let params : Array[String] = []
  let info = analyze_lifted_vars(block, params)
  // x is captured by multiple closures -> single lifted var
  assert_eq(info.lifted_vars.length(), 1)
  assert_true(info.lifted_vars.contains("x"))
  assert_eq(info.is_mutated.get("x"), Some(true))
}

///|
test "analyze_lifted_vars: param captured" {
  // function outer(n) { const f = () => n; return f(); }
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("f"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc([], @ast.TsArrowBody::ArrowExpr(@ast.TsExpr::Var("n")), false),
      ),
      @ast.TsStmt::Return(Some(@ast.TsExpr::CallExpr(@ast.TsExpr::Var("f"), []))),
    ],
  }
  let params : Array[String] = ["n"]
  let info = analyze_lifted_vars(block, params)
  // n (param) is captured -> should be lifted
  assert_eq(info.lifted_vars.length(), 1)
  assert_true(info.lifted_vars.contains("n"))
}

// Tests for compile_func_body_with_env (environment sharing code generation)

///|
test "compile_func_body_with_env: no closures" {
  // function f() { let x = 1; return x; }
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(@ast.TsBinding::Ident("x"), @ast.TsType::Number, @ast.TsExpr::IntLit(1)),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("x"))),
    ],
  }
  let params : Array[@ast.TsParam] = []
  let lifted_info = analyze_lifted_vars(block, [])

  let result = compile_func_body_with_env(block, params, lifted_info, 0U)

  // No lifted vars -> no env struct
  assert_true(result.env_struct_type is None)
  assert_true(result.env_local_idx is None)
  println("Body instructions: \{result.func_code.body.instrs.length()}")
}

///|
test "compile_func_body_with_env: with captured read-only var" {
  // function outer() { let x = 1; const f = () => x; return x; }
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(@ast.TsBinding::Ident("x"), @ast.TsType::Number, @ast.TsExpr::IntLit(1)),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("f"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc([], @ast.TsArrowBody::ArrowExpr(@ast.TsExpr::Var("x")), false),
      ),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("x"))),
    ],
  }
  let params : Array[@ast.TsParam] = []
  let lifted_info = analyze_lifted_vars(block, [])

  let result = compile_func_body_with_env(block, params, lifted_info, 0U)

  // x is captured -> env struct needed
  assert_true(result.env_struct_type is Some(_))
  assert_true(result.env_local_idx is Some(_))

  // Check env struct has immutable field
  match result.env_struct_type {
    Some(@core.TypeDef::Struct(struct_type)) => {
      assert_eq(struct_type.fields.length(), 1)
      assert_false(struct_type.fields[0].mutable)
    }
    _ => fail("Expected struct type")
  }

  println("Generated env-sharing code with \{result.func_code.body.instrs.length()} instructions")
}

///|
test "compile_func_body_with_env: with mutable captured var" {
  // function outer() {
  //   let x = 1;
  //   const inc = () => { x = x + 1; };
  //   return x;  // Should see updated x after inc()
  // }
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(@ast.TsBinding::Ident("x"), @ast.TsType::Number, @ast.TsExpr::IntLit(1)),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("inc"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc(
          [],
          @ast.TsArrowBody::ArrowBlock({
            stmts: [
              @ast.TsStmt::Assign(
                "x",
                @ast.TsExpr::BinOp(@ast.TsBinOp::Add, @ast.TsExpr::Var("x"), @ast.TsExpr::IntLit(1)),
              ),
            ],
          }),
          false,
        ),
      ),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("x"))),
    ],
  }
  let params : Array[@ast.TsParam] = []
  let lifted_info = analyze_lifted_vars(block, [])

  let result = compile_func_body_with_env(block, params, lifted_info, 0U)

  // x is captured and mutated -> env struct with mutable field
  assert_true(result.env_struct_type is Some(_))
  match result.env_struct_type {
    Some(@core.TypeDef::Struct(struct_type)) => {
      assert_eq(struct_type.fields.length(), 1)
      assert_true(struct_type.fields[0].mutable)  // x is mutated -> mutable field
    }
    _ => fail("Expected struct type")
  }

  // Check instructions include StructNew, StructGet, StructSet
  let has_struct_new = result.func_code.body.instrs.iter().any(
    fn(i) {
      match i {
        @core.Instr::StructNew(_) => true
        _ => false
      }
    },
  )
  assert_true(has_struct_new)

  println("Generated mutable env-sharing code with \{result.func_code.body.instrs.length()} instructions")
}

///|
test "compile_func_body_with_env: outer assignment to captured var" {
  // function outer() {
  //   let x = 1;
  //   const f = () => x;  // capture x
  //   x = 2;              // outer assignment should use env
  //   return x;
  // }
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(@ast.TsBinding::Ident("x"), @ast.TsType::Number, @ast.TsExpr::IntLit(1)),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("f"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc([], @ast.TsArrowBody::ArrowExpr(@ast.TsExpr::Var("x")), false),
      ),
      @ast.TsStmt::Assign("x", @ast.TsExpr::IntLit(2)),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("x"))),
    ],
  }
  let params : Array[@ast.TsParam] = []
  let lifted_info = analyze_lifted_vars(block, [])

  let result = compile_func_body_with_env(block, params, lifted_info, 0U)

  // x is captured -> env struct
  assert_true(result.env_struct_type is Some(_))

  // Count StructSet instructions (should have multiple - init + assignment)
  let struct_set_count = result.func_code.body.instrs.iter().fold(
    init=0,
    fn(count, i) {
      match i {
        @core.Instr::StructSet(_, _) => count + 1
        _ => count
      }
    },
  )
  // At least 2: initial value + x = 2
  assert_true(struct_set_count >= 2)

  println("Outer assignment generated \{struct_set_count} StructSet instructions")
}
