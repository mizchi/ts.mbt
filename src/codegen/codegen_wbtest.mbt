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
  let r1 = runtime.call_compiled(
    b"bitand",
    [@runtime.Value::I32(12), @runtime.Value::I32(10)],
  )
  assert_eq(r1[0], @runtime.Value::I32(8))
  // 0b1100 | 0b1010 = 0b1110 = 14
  let r2 = runtime.call_compiled(
    b"bitor",
    [@runtime.Value::I32(12), @runtime.Value::I32(10)],
  )
  assert_eq(r2[0], @runtime.Value::I32(14))
  // 0b1100 ^ 0b1010 = 0b0110 = 6
  let r3 = runtime.call_compiled(
    b"bitxor",
    [@runtime.Value::I32(12), @runtime.Value::I32(10)],
  )
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
  let r1 = runtime.call_compiled(
    b"shl",
    [@runtime.Value::I32(1), @runtime.Value::I32(4)],
  )
  assert_eq(r1[0], @runtime.Value::I32(16))
  // 16 >> 2 = 4
  let r2 = runtime.call_compiled(
    b"shr",
    [@runtime.Value::I32(16), @runtime.Value::I32(2)],
  )
  assert_eq(r2[0], @runtime.Value::I32(4))
  // 0xFFFFFFF8 (-8) >>> 1 = 0x7FFFFFFC = 2147483644 (unsigned shift)
  let r3 = runtime.call_compiled(
    b"ushr",
    [@runtime.Value::I32(0xFFFFFFF8), @runtime.Value::I32(1)],
  )
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
  let r1 = runtime.call_compiled(
    b"coalesce",
    [@runtime.Value::I32(5), @runtime.Value::I32(10)],
  )
  assert_eq(r1[0], @runtime.Value::I32(5))
  // When a is 0 (treated as null-ish), return b
  let r2 = runtime.call_compiled(
    b"coalesce",
    [@runtime.Value::I32(0), @runtime.Value::I32(42)],
  )
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
