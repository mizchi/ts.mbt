// CodeGen test
// Uses WasmtimeCli by default for faster execution in CI

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
  assert_eq(wasm[0], b'\x00')
  assert_eq(wasm[1], b'\x61')
  assert_run_f64(wasm, "factorial", [5.0], 120.0)
}

///|
test "compile: convenience function" {
  let src =
    #|function double(x: number): number {
    #|  return x * 2;
    #|}
  let wasm_module = compile(src)
  assert_eq(wasm_module.funcs.length(), 1)
  assert_eq(wasm_module.exports.length(), 1)
  assert_eq(wasm_module.codes.length(), 1)
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "double", [21.0], 42.0)
}

///|
test "codegen: constant function" {
  let src =
    #|function answer(): number {
    #|  return 42;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "answer", [], 42.0)
}

///|
test "codegen: add function" {
  let src =
    #|function add(a: number, b: number): number {
    #|  return a + b;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "add", [3.0, 5.0], 8.0)
}

///|
test "codegen: arithmetic" {
  let src =
    #|function calc(a: number, b: number): number {
    #|  return (a + b) * (a - b);
    #|}
  let wasm = compile_to_wasm(src)
  // (5 + 3) * (5 - 3) = 8 * 2 = 16
  assert_run_f64(wasm, "calc", [5.0, 3.0], 16.0)
}

///|
test "codegen: local variable" {
  let src =
    #|function test(): number {
    #|  let x: number = 10;
    #|  let y: number = 20;
    #|  return x + y;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "test", [], 30.0)
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
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "max", [10.0, 5.0], 10.0)
  assert_run_f64(wasm, "max", [3.0, 7.0], 7.0)
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
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "factorial", [5.0], 120.0)
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
  let wasm = compile_to_wasm(src)
  // sum(10) = 1+2+...+10 = 55
  assert_run_f64(wasm, "sum", [10.0], 55.0)
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
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "quadruple", [5.0], 20.0)
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
  let wasm = compile_to_wasm(src)
  // sum_int(10) = 1+2+...+10 = 55
  assert_run_i32(wasm, "sum_int", [10.0], 55)
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
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "factorial_int", [5.0], 120)
}

///|
test "codegen: array literal and access" {
  let src =
    #|function sum_array(): number {
    #|  let arr: number[] = [1.0, 2.0, 3.0];
    #|  return arr[0] + arr[1] + arr[2];
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "sum_array", [], 6.0)
}

///|
test "codegen: array with new" {
  let src =
    #|function array_length(): int {
    #|  let arr: int[] = new Array<int>(5);
    #|  return arr.length;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "array_length", [], 5)
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
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "array_set", [], 60)
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
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "createPoint", [], 30.0)
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
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "testCounter", [], 42)
}

///|
test "codegen: object literal with computed key" {
  let src =
    #|interface Point {
    #|  x: int;
    #|  y: int;
    #|}
    #|function makePoint(a: int, b: int): int {
    #|  let p: Point = { ["x"]: a, y: b };
    #|  return p.x + p.y;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "makePoint", [2.0, 5.0], 7)
}

///|
test "codegen: array literal with spread" {
  let src =
    #|function spreadArray(): int {
    #|  let a: int[] = [1, 2];
    #|  let b: int[] = [3, 4, 5];
    #|  let c: int[] = [0, ...a, 9, ...b];
    #|  return c.length + c[1] + c[3] + c[5];
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "spreadArray", [], 21)
}

///|
test "codegen: call with spread" {
  let src =
    #|function sum3(a: int, b: int, c: int): int {
    #|  return a + b + c;
    #|}
    #|function callSpread(): int {
    #|  let xs: int[] = [2, 3];
    #|  return sum3(1, ...xs);
    #|}
    #|function callSpreadOnly(): int {
    #|  let ys: int[] = [4, 5, 6];
    #|  return sum3(...ys);
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "callSpread", [], 6)
  assert_run_i32(wasm, "callSpreadOnly", [], 15)
}

///|
test "codegen: ternary operator" {
  let src =
    #|function abs(x: number): number {
    #|  return x >= 0.0 ? x : -x;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "abs", [5.0], 5.0)
  assert_run_f64(wasm, "abs", [-3.0], 3.0)
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
  let wasm = compile_to_wasm(src)
  // x starts at 10, a = x++ (a=10, x=11), b = ++x (x=12, b=12)
  // result = 10 + 12 = 22
  assert_run_i32(wasm, "testIncDec", [], 22)
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
  let wasm = compile_to_wasm(src)
  // x = 10, x += 5 (15), x *= 2 (30), x -= 10 (20)
  assert_run_i32(wasm, "testCompound", [], 20)
}

///|
test "codegen: logical assignment (var)" {
  let src =
    #|function andAssign(a: int): int {
    #|  let x = a;
    #|  x &&= 5;
    #|  return x;
    #|}
    #|function orAssign(a: int): int {
    #|  let x = a;
    #|  x ||= 5;
    #|  return x;
    #|}
    #|function coalesceAssign(a: int, b: int): int {
    #|  let x = a;
    #|  x ??= b;
    #|  return x;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "andAssign", [0.0], 0)
  assert_run_i32(wasm, "andAssign", [2.0], 5)
  assert_run_i32(wasm, "orAssign", [0.0], 5)
  assert_run_i32(wasm, "orAssign", [2.0], 2)
  // nullish is approximated as 0
  assert_run_i32(wasm, "coalesceAssign", [0.0, 7.0], 7)
  assert_run_i32(wasm, "coalesceAssign", [3.0, 7.0], 3)
}

///|
test "codegen: logical assignment (prop)" {
  let src =
    #|interface Counter {
    #|  count: int;
    #|}
    #|function propAndAssign(a: int): int {
    #|  let c: Counter = new Counter();
    #|  c.count = a;
    #|  c.count &&= 10;
    #|  return c.count;
    #|}
    #|function propOrAssign(a: int): int {
    #|  let c: Counter = new Counter();
    #|  c.count = a;
    #|  c.count ||= 10;
    #|  return c.count;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "propAndAssign", [0.0], 0)
  assert_run_i32(wasm, "propAndAssign", [2.0], 10)
  assert_run_i32(wasm, "propOrAssign", [0.0], 10)
  assert_run_i32(wasm, "propOrAssign", [2.0], 2)
}

///|
test "codegen: logical assignment (index)" {
  let src =
    #|function indexOrAssign(a: int): int {
    #|  let arr: int[] = new Array<int>(1);
    #|  arr[0] = a;
    #|  let i = 0;
    #|  arr[i++] ||= 7;
    #|  return i + arr[0];
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "indexOrAssign", [0.0], 8)
  assert_run_i32(wasm, "indexOrAssign", [5.0], 6)
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
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "sumFor", [10.0], 55)
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
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "sumArray", [], 15.0)
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
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "countArray", [], 60)
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
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "compare", [5.0, 5.0], 0.0)
  assert_run_f64(wasm, "compare", [3.0, 7.0], 1.0)
  assert_run_f64(wasm, "compare", [10.0, 5.0], 2.0)
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
  assert_eq(ts_module.imports.length(), 2)
  let wasm_module = compile_module(ts_module)
  assert_eq(wasm_module.imports.length(), 2)
  assert_eq(wasm_module.types.length(), 3)
  assert_eq(wasm_module.funcs.length(), 1)
  assert_eq(wasm_module.exports.length(), 1)
}

///|
test "codegen: javascript style code with type inference" {
  let src =
    #|function add(a, b) {
    #|  let x = 1;
    #|  let y = 2;
    #|  return x + y;
    #|}
  let wasm = compile_to_wasm(src)
  // result 3 (1 + 2), args are ignored
  match run_wasm(wasm, "add", [0.0, 0.0]) {
    RunResult::F64(_) => ()
    RunResult::I32(_) => ()
    RunResult::Error(e) => fail("Run error: \{e}")
  }
}

///|
test "js: simple arithmetic" {
  let src =
    #|function calc(): int {
    #|  let a = 10;
    #|  let b = 3;
    #|  let sum = a + b;
    #|  return sum;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "calc", [], 13)
}

///|
test "js: multiple functions call" {
  let src =
    #|function double(x: int): int {
    #|  return x * 2;
    #|}
    #|function main(): int {
    #|  return double(5);
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "main", [], 10)
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
  assert_eq(wasm_module.customs.length(), 1)
  let custom = wasm_module.customs[0]
  assert_eq(custom.name, b"tstype")
  let data = custom.data
  assert_eq(data[0], b'\x54') // T
  assert_eq(data[1], b'\x53') // S
  assert_eq(data[2], b'\x54') // T
  assert_eq(data[3], b'\x59') // Y
  assert_eq(data[4], b'\x01') // version = 1
  assert_eq(data[5], b'\x01') // import = 1
  assert_eq(data[6], b'\x00')
  assert_eq(data[7], b'\x01') // interface = 1
  assert_eq(data[8], b'\x00')
  assert_eq(data[9], b'\x01') // export = 1
  assert_eq(data[10], b'\x00')
}

///|
test "codegen: analyze_and_compile with type inference" {
  let src =
    #|function compute(): int {
    #|  let x = 10;
    #|  let y = 20;
    #|  let z = x + y;
    #|  return z;
    #|}
  let wasm_module = analyze_and_compile(src)
  let wasm = @encode.encode(wasm_module)
  assert_run_i32(wasm, "compute", [], 30)
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
  let wasm = @encode.encode(wasm_module)
  // result = (1+0) + (1+1) + (1+2) + (1+3) + (1+4) = 1+2+3+4+5 = 15
  assert_run_i32(wasm, "nested", [], 15)
}

///|
test "codegen: constant folding in binary operations" {
  let src =
    #|function test(): int {
    #|  return 10 + 20 * 3;
    #|}
  let wasm = compile_to_wasm(src)
  // 10 + 20 * 3 = 10 + 60 = 70
  assert_run_i32(wasm, "test", [], 70)
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
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "test", [], 42)
}

///|
test "codegen: constant folding in ternary" {
  let src =
    #|function test(): int {
    #|  return false ? 100 : 200;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "test", [], 200)
}

///|
test "codegen: typed module preserves function types" {
  let src =
    #|function addNumbers(a: number, b: number): number {
    #|  let sum = a + b;
    #|  return sum;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "addNumbers", [3.5, 2.5], 6.0)
}

///|
test "codegen: constant propagation" {
  let src =
    #|function test(): int {
    #|  const x = 10;
    #|  const y = 20;
    #|  return x + y;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "test", [], 30)
}

///|
test "codegen: constant propagation replaces variable reads" {
  let src =
    #|function compute(n: int): int {
    #|  const factor = 3;
    #|  return n * factor;
    #|}
  let wasm = compile_to_wasm(src)
  // n=7, factor=3, result=21
  assert_run_i32(wasm, "compute", [7.0], 21)
}

///|
test "codegen: bitwise NOT operator" {
  let src =
    #|function bitnot(x: int): int {
    #|  return ~x;
    #|}
  let wasm = compile_to_wasm(src)
  // ~0 = -1 (0xFFFFFFFF)
  assert_run_i32(wasm, "bitnot", [0.0], 0xFFFFFFFF)
  // ~1 = -2 (0xFFFFFFFE)
  assert_run_i32(wasm, "bitnot", [1.0], 0xFFFFFFFE)
  // ~0xFFFFFFFF = 0
  assert_run_i32(wasm, "bitnot", [(0xFFFFFFFF).to_double()], 0)
}

///|
test "codegen: bitwise AND, OR, XOR" {
  let src =
    #|function bitand(a: int, b: int): int { return a & b; }
    #|function bitor(a: int, b: int): int { return a | b; }
    #|function bitxor(a: int, b: int): int { return a ^ b; }
  let wasm = compile_to_wasm(src)
  // 0b1100 & 0b1010 = 0b1000 = 8
  assert_run_i32(wasm, "bitand", [12.0, 10.0], 8)
  // 0b1100 | 0b1010 = 0b1110 = 14
  assert_run_i32(wasm, "bitor", [12.0, 10.0], 14)
  // 0b1100 ^ 0b1010 = 0b0110 = 6
  assert_run_i32(wasm, "bitxor", [12.0, 10.0], 6)
}

///|
test "codegen: bit shift operations" {
  let src =
    #|function shl(a: int, b: int): int { return a << b; }
    #|function shr(a: int, b: int): int { return a >> b; }
    #|function ushr(a: int, b: int): int { return a >>> b; }
  let wasm = compile_to_wasm(src)
  // 1 << 4 = 16
  assert_run_i32(wasm, "shl", [1.0, 4.0], 16)
  // 16 >> 2 = 4
  assert_run_i32(wasm, "shr", [16.0, 2.0], 4)
  // 0xFFFFFFF8 (-8) >>> 1 = 0x7FFFFFFC
  assert_run_i32(wasm, "ushr", [(0xFFFFFFF8).to_double(), 1.0], 0x7FFFFFFC)
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
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "grade", [5.0], 100)
  assert_run_i32(wasm, "grade", [3.0], 60)
  assert_run_i32(wasm, "grade", [1.0], 0)
}

///|
test "codegen: switch with default only" {
  let src =
    #|function always42(x: int): int {
    #|  switch (x) {
    #|    default: return 42;
    #|  }
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "always42", [0.0], 42)
  assert_run_i32(wasm, "always42", [999.0], 42)
}

///|
test "codegen: comma operator" {
  let src =
    #|function commaTest(a: int): int {
    #|  let x = 1;
    #|  return (x = a, x + 2);
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "commaTest", [5.0], 7)
}

///|
test "codegen: logical and short-circuit" {
  let src =
    #|function andTest(a: int): int {
    #|  let x = 1;
    #|  let y = (a && (x = 5));
    #|  return x;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "andTest", [0.0], 1)
  assert_run_i32(wasm, "andTest", [1.0], 5)
}

///|
test "codegen: logical or short-circuit" {
  let src =
    #|function orTest(a: int): int {
    #|  let x = 1;
    #|  let y = (a || (x = 5));
    #|  return x;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "orTest", [0.0], 5)
  assert_run_i32(wasm, "orTest", [1.0], 1)
}

///|
test "codegen: void operator" {
  let src =
    #|function voidTest(a: int): int {
    #|  let x = 1;
    #|  void (x = a + 1);
    #|  return x;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "voidTest", [2.0], 3)
}

///|
test "codegen: typeof operator (static)" {
  let src =
    #|function typeOfNumber(): string {
    #|  return typeof 1;
    #|}
    #|function typeOfParam(x: number): string {
    #|  return typeof x;
    #|}
  let wasm = compile_to_wasm(src)
  let wasm_module = compile(src)
  let pool = wasm_module.datas[0].init
  let ptr1 = match run_wasm(wasm, "typeOfNumber", []) {
    RunResult::I32(v) => v
    RunResult::F64(v) => v.to_int()
    RunResult::Error(e) => fail("Run error: \{e}")
  }
  let s1 = decode_string_from_pool(pool, ptr1)
  assert_eq(s1, "number")
  let ptr2 = match run_wasm(wasm, "typeOfParam", [5.0]) {
    RunResult::I32(v) => v
    RunResult::F64(v) => v.to_int()
    RunResult::Error(e) => fail("Run error: \{e}")
  }
  let s2 = decode_string_from_pool(pool, ptr2)
  assert_eq(s2, "number")
}

///|
test "codegen: template literal (string only)" {
  let src =
    #|function tplLen(): int {
    #|  let name: string = "bob";
    #|  return `hi ${name}!`.length;
    #|}
    #|function tplConst(): int {
    #|  return `ab`.length;
    #|}
    #|function tplMulti(): int {
    #|  let a: string = "x";
    #|  let b: string = "y";
    #|  return `${a}-${b}`.length;
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_i32(wasm, "tplLen", [], 7)
  assert_run_i32(wasm, "tplConst", [], 2)
  assert_run_i32(wasm, "tplMulti", [], 3)
}

///|
test "codegen: template literal (ToString)" {
  let src_int =
    #|function tplInt(n: int): int {
    #|  return `${n}`.length;
    #|}
  let wasm_int = compile_to_wasm(src_int)
  assert_run_i32(wasm_int, "tplInt", [42.0], 2)

  let src_bool =
    #|function tplBool(a: int): int {
    #|  let b: boolean = a > 0;
    #|  return `${b}`.length;
    #|}
  let wasm_bool = compile_to_wasm(src_bool)
  assert_run_i32(wasm_bool, "tplBool", [1.0], 4)
  assert_run_i32(wasm_bool, "tplBool", [0.0], 5)

  let src_num =
    #|function tplNum(n: number): int {
    #|  return `${n}`.length;
    #|}
  let wasm_num = compile_to_wasm(src_num)
  assert_run_i32(wasm_num, "tplNum", [12.0], 2)

  let src_null =
    #|function tplNull(): int {
    #|  return `${null}`.length;
    #|}
  let wasm_null = compile_to_wasm(src_null)
  assert_run_i32(wasm_null, "tplNull", [], 4)
}

///|
test "codegen: nullish coalescing operator" {
  let src =
    #|function coalesce(a: int, b: int): int {
    #|  return a ?? b;
    #|}
  let wasm = compile_to_wasm(src)
  // When a is non-zero, return a
  assert_run_i32(wasm, "coalesce", [5.0, 10.0], 5)
  // When a is 0 (treated as null-ish), return b
  assert_run_i32(wasm, "coalesce", [0.0, 42.0], 42)
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
  let wasm = compile_to_wasm(src)
  // sum of 1 to 5 = 15
  assert_run_i32(wasm, "sumDoWhile", [5.0], 15)
  // do-while executes at least once even if condition is false initially
  assert_run_i32(wasm, "sumDoWhile", [0.0], 1)
}

// ============ wasm-gc tests ============
// These tests verify wasm-gc module structure, not execution

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
  assert_true(wasm_module.types.length() >= 3)
  let wasm = @encode.encode(wasm_module)
  assert_eq(wasm[0], b'\x00')
  assert_eq(wasm[1], b'\x61')
  assert_eq(wasm[2], b'\x73')
  assert_eq(wasm[3], b'\x6D')
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
  let struct_type_idx = 2U
  match wasm_module.types[struct_type_idx.reinterpret_as_int()] {
    @core.TypeDef::Struct(st) => assert_eq(st.fields.length(), 2)
    _ => fail("Expected struct type at index 2")
  }
  let wasm = @encode.encode(wasm_module)
  assert_true(wasm.length() > 0)
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
  match wasm_module.types[0] {
    @core.TypeDef::Array(arr_type) =>
      match arr_type.element.storage {
        @core.StorageType::Val(@core.ValType::I32) => ()
        _ => fail("Expected i32 storage type")
      }
    _ => fail("Expected array type at index 0")
  }
  let wasm = @encode.encode(wasm_module)
  assert_true(wasm.length() > 0)
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
  assert_true(wasm_module.types.length() >= 4)
  match wasm_module.types[2] {
    @core.TypeDef::Struct(st) => assert_eq(st.fields.length(), 2)
    _ => fail("Expected Point struct at index 2")
  }
  match wasm_module.types[3] {
    @core.TypeDef::Struct(st) => assert_eq(st.fields.length(), 2)
    _ => fail("Expected Rect struct at index 3")
  }
  let wasm = @encode.encode(wasm_module)
  assert_true(wasm.length() > 0)
}

// ============ Math function tests ============

///|
test "codegen: Math.sqrt" {
  let src =
    #|function sqrt16(): number {
    #|  return Math.sqrt(16.0);
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "sqrt16", [], 4.0)
}

///|
test "codegen: Math.abs" {
  let src =
    #|function absNeg(): number {
    #|  return Math.abs(-5.0);
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "absNeg", [], 5.0)
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
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "floorTest", [], 3.0)
  assert_run_f64(wasm, "ceilTest", [], 4.0)
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
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "minTest", [], 3.0)
  assert_run_f64(wasm, "maxTest", [], 5.0)
}

///|
test "codegen: Math.pow with constant exponent" {
  let src =
    #|function pow2_10(): number {
    #|  return Math.pow(2.0, 10);
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "pow2_10", [], 1024.0)
}

///|
test "codegen: Math.round" {
  let src =
    #|function roundTest(): number {
    #|  return Math.round(3.5);
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "roundTest", [], 4.0)
}

///|
test "codegen: Math.trunc" {
  let src =
    #|function truncTest(): number {
    #|  return Math.trunc(-3.7);
    #|}
  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "truncTest", [], -3.0)
}

///|
test "codegen: pure function with Math - distance" {
  let src =
    #|function distance(x1: number, y1: number, x2: number, y2: number): number {
    #|  let dx: number = x2 - x1;
    #|  let dy: number = y2 - y1;
    #|  return Math.sqrt(dx * dx + dy * dy);
    #|}
  let wasm = compile_to_wasm(src)
  // distance(0, 0, 3, 4) = sqrt(9 + 16) = sqrt(25) = 5
  assert_run_f64(wasm, "distance", [0.0, 0.0, 3.0, 4.0], 5.0)
}

// ============ Generator tests ============
// These tests verify generator IR and codegen structure

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
  let analysis = @analysis.analyze_generator(func)
  assert_true(analysis.compilable)
  assert_eq(analysis.yield_points.length(), 1)
  assert_eq(analysis.persisted_vars.length(), 2)
  let sm = transform_to_state_machine(func, analysis)
  assert_eq(sm.name, "counter")
  assert_eq(sm.params.length(), 1)
  assert_eq(sm.locals.length(), 1)
  assert_eq(sm.states.length(), 2)
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
  assert_eq(analysis.persisted_vars.length(), 4)
  let sm = transform_to_state_machine(func, analysis)
  assert_eq(sm.name, "fib")
  assert_eq(sm.params.length(), 1)
  assert_eq(sm.locals.length(), 3)
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
  let analysis = @analysis.analyze_generator(func)
  assert_true(analysis.compilable)
  let sm = transform_to_state_machine(func, analysis)
  let wasm_code = compile_generator(sm, 0U)
  match wasm_code.state_struct_type {
    @core.TypeDef::Struct(st) => assert_eq(st.fields.length(), 6)
    _ => assert_true(false)
  }
  assert_true(wasm_code.create_func_code.body.instrs.length() > 0)
  assert_true(wasm_code.next_func_code.body.instrs.length() > 0)
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
  let wasm_module = compile_module_gc(ts_module)
  let export_names : Array[String] = []
  for exp in wasm_module.exports {
    let name = bytes_to_string(exp.name)
    export_names.push(name)
  }
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
fn decode_string_from_pool(pool : BytesView, offset : Int) -> String {
  let b0 = pool[offset].to_int()
  let b1 = pool[offset + 1].to_int()
  let b2 = pool[offset + 2].to_int()
  let b3 = pool[offset + 3].to_int()
  let len = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  let start = offset + 4
  let end = start + len
  bytes_to_string(pool[start:end].to_bytes())
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
  let analysis = @analysis.analyze_generator(func)
  assert_true(analysis.compilable)
  let sm = transform_to_state_machine(func, analysis)
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
  let analysis = @analysis.analyze_generator(func)
  assert_true(analysis.compilable)
  let sm = transform_to_state_machine(func, analysis)
  let wasm_code = compile_generator(sm, 0U)
  assert_true(wasm_code.next_func_code.body.instrs.length() > 0)
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
  let graph = @analysis.build_call_graph(ts_module)
  let groups = @analysis.find_aot_groups(ts_module, graph)
  assert_eq(groups.length(), 1)
  let group = groups[0]
  match compile_aot_group(group, ts_module, 0U) {
    Some(code) => assert_eq(code.funcs.length(), 4)
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
  assert_false(group.external_calls.contains("add"))
  match compile_aot_group(group, ts_module, 0U) {
    Some(code) => {
      assert_eq(code.funcs.length(), 3)
      match code.func_map.get("add") {
        Some(_) => ()
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

// ============ Closure codegen tests ============

///|
test "compile_arrow_func: no captures" {
  let params : Array[@ast.TsParam] = [
    {
      name: "x",
      type_: @ast.TsType::Number,
      binding: None,
      is_rest: false,
      default: None,
    },
  ]
  let body = @ast.TsArrowBody::ArrowExpr(
    @ast.TsExpr::BinOp(
      @ast.TsBinOp::Add,
      @ast.TsExpr::Var("x"),
      @ast.TsExpr::IntLit(1),
    ),
  )
  let outer_scope : Array[String] = []
  let ctx = ClosureCodegenCtx::new(0U)
  match compile_arrow_func(params, body, outer_scope, ctx) {
    Some(code) => {
      assert_true(code.env_struct_type is None)
      assert_eq(code.capture_names.length(), 0)
    }
    None => fail("Expected compilable closure")
  }
}

///|
test "compile_arrow_func: with capture" {
  let params : Array[@ast.TsParam] = [
    {
      name: "a",
      type_: @ast.TsType::Number,
      binding: None,
      is_rest: false,
      default: None,
    },
  ]
  let body = @ast.TsArrowBody::ArrowExpr(
    @ast.TsExpr::BinOp(
      @ast.TsBinOp::Add,
      @ast.TsExpr::Var("a"),
      @ast.TsExpr::Var("x"),
    ),
  )
  let outer_scope : Array[String] = ["x"]
  let ctx = ClosureCodegenCtx::new(0U)
  match compile_arrow_func(params, body, outer_scope, ctx) {
    Some(code) => {
      assert_true(code.env_struct_type is Some(_))
      assert_eq(code.capture_names.length(), 1)
      assert_eq(code.capture_names[0], "x")
    }
    None => fail("Expected compilable closure")
  }
}

///|
test "compile_arrow_func: block body" {
  let params : Array[@ast.TsParam] = [
    {
      name: "n",
      type_: @ast.TsType::Number,
      binding: None,
      is_rest: false,
      default: None,
    },
  ]
  let body = @ast.TsArrowBody::ArrowBlock({
    stmts: [
      @ast.TsStmt::Let(
        @ast.TsBinding::Ident("result"),
        @ast.TsType::Number,
        @ast.TsExpr::BinOp(
          @ast.TsBinOp::Mul,
          @ast.TsExpr::Var("n"),
          @ast.TsExpr::IntLit(2),
        ),
      ),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("result"))),
    ],
  })
  let outer_scope : Array[String] = []
  let ctx = ClosureCodegenCtx::new(0U)
  match compile_arrow_func(params, body, outer_scope, ctx) {
    Some(code) => assert_true(code.env_struct_type is None)
    None => fail("Expected compilable closure")
  }
}

///|
test "compile_func_expr: simple function" {
  let func : @ast.TsFunc = {
    name: "double",
    params: [
      {
        name: "x",
        type_: @ast.TsType::Number,
        binding: None,
        is_rest: false,
        default: None,
      },
    ],
    return_type: @ast.TsType::Number,
    body: {
      stmts: [
        @ast.TsStmt::Return(
          Some(
            @ast.TsExpr::BinOp(
              @ast.TsBinOp::Mul,
              @ast.TsExpr::Var("x"),
              @ast.TsExpr::IntLit(2),
            ),
          ),
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
          Some(
            @ast.TsExpr::BinOp(
              @ast.TsBinOp::Add,
              @ast.TsExpr::Var("a"),
              @ast.TsExpr::Var("b"),
            ),
          ),
        ),
      ],
    },
    is_generator: false,
    is_async: false,
  }
  let outer_scope : Array[String] = ["a", "b", "c"]
  let ctx = ClosureCodegenCtx::new(0U)
  match compile_func_expr(func, outer_scope, ctx) {
    Some(code) => {
      assert_true(code.env_struct_type is Some(_))
      assert_eq(code.capture_names.length(), 2)
      assert_true(code.capture_names.contains("a"))
      assert_true(code.capture_names.contains("b"))
    }
    None => fail("Expected compilable function")
  }
}

///|
test "compile_arrow_func: mutable capture (Phase 3)" {
  let params : Array[@ast.TsParam] = []
  let body = @ast.TsArrowBody::ArrowBlock({
    stmts: [
      @ast.TsStmt::Assign(
        "x",
        @ast.TsExpr::BinOp(
          @ast.TsBinOp::Add,
          @ast.TsExpr::Var("x"),
          @ast.TsExpr::IntLit(1),
        ),
      ),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("x"))),
    ],
  })
  let outer_scope : Array[String] = ["x"]
  let ctx = ClosureCodegenCtx::new(0U)
  match compile_arrow_func(params, body, outer_scope, ctx) {
    Some(code) => {
      assert_true(code.env_struct_type is Some(_))
      assert_eq(code.capture_names.length(), 1)
      assert_eq(code.capture_names[0], "x")
      match code.env_struct_type {
        Some(@core.TypeDef::Struct(struct_type)) => {
          assert_eq(struct_type.fields.length(), 1)
          assert_true(struct_type.fields[0].mutable)
        }
        _ => fail("Expected struct type")
      }
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
        @ast.TsStmt::Assign(
          "count",
          @ast.TsExpr::BinOp(
            @ast.TsBinOp::Add,
            @ast.TsExpr::Var("count"),
            @ast.TsExpr::Var("step"),
          ),
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
      match code.env_struct_type {
        Some(@core.TypeDef::Struct(struct_type)) =>
          assert_eq(struct_type.fields.length(), 2)
        _ => fail("Expected struct type")
      }
    }
    None => fail("Expected compilable function")
  }
}

// ============ Lifted vars analysis tests ============

///|
test "analyze_lifted_vars: no closures" {
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(
        @ast.TsBinding::Ident("x"),
        @ast.TsType::Number,
        @ast.TsExpr::IntLit(1),
      ),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("x"))),
    ],
  }
  let params : Array[String] = []
  let info = analyze_lifted_vars(block, params)
  assert_eq(info.lifted_vars.length(), 0)
}

///|
test "analyze_lifted_vars: closure captures local" {
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(
        @ast.TsBinding::Ident("x"),
        @ast.TsType::Number,
        @ast.TsExpr::IntLit(1),
      ),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("f"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc(
          [],
          @ast.TsArrowBody::ArrowExpr(@ast.TsExpr::Var("x")),
          false,
        ),
      ),
      @ast.TsStmt::Return(
        Some(@ast.TsExpr::CallExpr(@ast.TsExpr::Var("f"), [])),
      ),
    ],
  }
  let params : Array[String] = []
  let info = analyze_lifted_vars(block, params)
  assert_eq(info.lifted_vars.length(), 1)
  assert_true(info.lifted_vars.contains("x"))
  assert_eq(info.is_mutated.get("x"), Some(false))
}

///|
test "analyze_lifted_vars: closure mutates captured var" {
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(
        @ast.TsBinding::Ident("x"),
        @ast.TsType::Number,
        @ast.TsExpr::IntLit(1),
      ),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("inc"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc(
          [],
          @ast.TsArrowBody::ArrowBlock({
            stmts: [
              @ast.TsStmt::Assign(
                "x",
                @ast.TsExpr::BinOp(
                  @ast.TsBinOp::Add,
                  @ast.TsExpr::Var("x"),
                  @ast.TsExpr::IntLit(1),
                ),
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
  assert_eq(info.lifted_vars.length(), 1)
  assert_true(info.lifted_vars.contains("x"))
  assert_eq(info.is_mutated.get("x"), Some(true))
  assert_eq(info.field_indices.get("x"), Some(0U))
}

///|
test "analyze_lifted_vars: multiple closures share captured var" {
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(
        @ast.TsBinding::Ident("x"),
        @ast.TsType::Number,
        @ast.TsExpr::IntLit(0),
      ),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("inc"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc(
          [],
          @ast.TsArrowBody::ArrowBlock({
            stmts: [
              @ast.TsStmt::Assign(
                "x",
                @ast.TsExpr::BinOp(
                  @ast.TsBinOp::Add,
                  @ast.TsExpr::Var("x"),
                  @ast.TsExpr::IntLit(1),
                ),
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
                @ast.TsExpr::BinOp(
                  @ast.TsBinOp::Sub,
                  @ast.TsExpr::Var("x"),
                  @ast.TsExpr::IntLit(1),
                ),
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
  assert_eq(info.lifted_vars.length(), 1)
  assert_true(info.lifted_vars.contains("x"))
  assert_eq(info.is_mutated.get("x"), Some(true))
}

///|
test "analyze_lifted_vars: param captured" {
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("f"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc(
          [],
          @ast.TsArrowBody::ArrowExpr(@ast.TsExpr::Var("n")),
          false,
        ),
      ),
      @ast.TsStmt::Return(
        Some(@ast.TsExpr::CallExpr(@ast.TsExpr::Var("f"), [])),
      ),
    ],
  }
  let params : Array[String] = ["n"]
  let info = analyze_lifted_vars(block, params)
  assert_eq(info.lifted_vars.length(), 1)
  assert_true(info.lifted_vars.contains("n"))
}

// ============ compile_func_body_with_env tests ============

///|
test "compile_func_body_with_env: no closures" {
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(
        @ast.TsBinding::Ident("x"),
        @ast.TsType::Number,
        @ast.TsExpr::IntLit(1),
      ),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("x"))),
    ],
  }
  let params : Array[@ast.TsParam] = []
  let lifted_info = analyze_lifted_vars(block, [])
  let result = compile_func_body_with_env(block, params, lifted_info, 0U)
  assert_true(result.env_struct_type is None)
  assert_true(result.env_local_idx is None)
}

///|
test "compile_func_body_with_env: with captured read-only var" {
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(
        @ast.TsBinding::Ident("x"),
        @ast.TsType::Number,
        @ast.TsExpr::IntLit(1),
      ),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("f"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc(
          [],
          @ast.TsArrowBody::ArrowExpr(@ast.TsExpr::Var("x")),
          false,
        ),
      ),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("x"))),
    ],
  }
  let params : Array[@ast.TsParam] = []
  let lifted_info = analyze_lifted_vars(block, [])
  let result = compile_func_body_with_env(block, params, lifted_info, 0U)
  assert_true(result.env_struct_type is Some(_))
  assert_true(result.env_local_idx is Some(_))
  match result.env_struct_type {
    Some(@core.TypeDef::Struct(struct_type)) => {
      assert_eq(struct_type.fields.length(), 1)
      assert_false(struct_type.fields[0].mutable)
    }
    _ => fail("Expected struct type")
  }
}

///|
test "compile_func_body_with_env: with mutable captured var" {
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(
        @ast.TsBinding::Ident("x"),
        @ast.TsType::Number,
        @ast.TsExpr::IntLit(1),
      ),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("inc"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc(
          [],
          @ast.TsArrowBody::ArrowBlock({
            stmts: [
              @ast.TsStmt::Assign(
                "x",
                @ast.TsExpr::BinOp(
                  @ast.TsBinOp::Add,
                  @ast.TsExpr::Var("x"),
                  @ast.TsExpr::IntLit(1),
                ),
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
  assert_true(result.env_struct_type is Some(_))
  match result.env_struct_type {
    Some(@core.TypeDef::Struct(struct_type)) => {
      assert_eq(struct_type.fields.length(), 1)
      assert_true(struct_type.fields[0].mutable)
    }
    _ => fail("Expected struct type")
  }
  let has_struct_new = result.func_code.body.instrs
    .iter()
    .any(fn(i) {
      match i {
        @core.Instr::StructNew(_) => true
        _ => false
      }
    })
  assert_true(has_struct_new)
}

///|
test "compile_func_body_with_env: outer assignment to captured var" {
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(
        @ast.TsBinding::Ident("x"),
        @ast.TsType::Number,
        @ast.TsExpr::IntLit(1),
      ),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("f"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc(
          [],
          @ast.TsArrowBody::ArrowExpr(@ast.TsExpr::Var("x")),
          false,
        ),
      ),
      @ast.TsStmt::Assign("x", @ast.TsExpr::IntLit(2)),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("x"))),
    ],
  }
  let params : Array[@ast.TsParam] = []
  let lifted_info = analyze_lifted_vars(block, [])
  let result = compile_func_body_with_env(block, params, lifted_info, 0U)
  assert_true(result.env_struct_type is Some(_))
  let struct_set_count = result.func_code.body.instrs
    .iter()
    .fold(init=0, fn(count, i) {
      match i {
        @core.Instr::StructSet(_, _) => count + 1
        _ => count
      }
    })
  assert_true(struct_set_count >= 2)
}
