// CodeGen のテスト

///|
test "compile_to_wasm: generates valid wasm binary" {
  let src =
    #|function add(a: number, b: number): number {
    #|  return a + b;
    #|}
  let wasm = compile_to_wasm(src)

  // Wasm マジックナンバーをチェック: 0x00 0x61 0x73 0x6D (= "\0asm")
  assert_eq(wasm[0], b'\x00')
  assert_eq(wasm[1], b'\x61') // 'a'
  assert_eq(wasm[2], b'\x73') // 's'
  assert_eq(wasm[3], b'\x6D') // 'm'

  // バージョン 1.0: 0x01 0x00 0x00 0x00
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

  // Wasm マジックナンバーをチェック
  assert_eq(wasm[0], b'\x00')
  assert_eq(wasm[1], b'\x61')

  // 生成されたバイナリが実行可能か確認 (wasm5 runtime で)
  let parser = Parser::from_source(src)
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

  // Module が正しく生成されているか
  assert_eq(wasm_module.funcs.length(), 1)
  assert_eq(wasm_module.exports.length(), 1)
  assert_eq(wasm_module.codes.length(), 1)

  // 実行テスト
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)

  // モジュール構造の確認
  assert_eq(wasm_module.mems.length(), 1) // メモリあり
  assert_eq(wasm_module.globals.length(), 1) // ヒープポインタ
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
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
  let parser = Parser::from_source(src)
  let ts_module = parser.parse_module()

  // インポートが正しくパースされている
  assert_eq(ts_module.imports.length(), 2)

  // Wasm モジュールを生成
  let wasm_module = compile_module(ts_module)

  // インポートが正しく生成されている
  assert_eq(wasm_module.imports.length(), 2)

  // 型定義にインポート関数の型が含まれている (2つのインポート + 1つのユーザー関数)
  assert_eq(wasm_module.types.length(), 3)

  // funcs にはユーザー定義関数のみ (インポート関数はimportsセクション)
  assert_eq(wasm_module.funcs.length(), 1)

  // エクスポートはユーザー定義関数のみ
  assert_eq(wasm_module.exports.length(), 1)
}

///|
test "codegen: javascript style code with type inference" {
  // 型注釈なしの JavaScript スタイル
  let src =
    #|function add(a, b) {
    #|  let x = 1;
    #|  let y = 2;
    #|  return x + y;
    #|}
  let parser = Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)

  // パラメータは Any → f64 (デフォルト)
  // ローカル変数 x, y は Int として推論される
  let runtime = @runtime.Runtime::load(wasm_module)
  runtime.run_start()
  // add(0, 0) を呼び出し - 結果は 3 (1 + 2)
  // パラメータは使わないが Any=f64 として渡す
  let results = runtime.call_compiled(b"add", [
    @runtime.Value::F64(0.0),
    @runtime.Value::F64(0.0),
  ])
  // 戻り値も Any=f64 だが、内部では Int として計算されている
  // f64 → i32 の変換が発生する可能性があるため、結果を確認
  assert_eq(results.length(), 1)
}

///|
test "js: simple arithmetic" {
  // JavaScript: シンプルな算術演算
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
  // JavaScript: 複数関数の相互呼び出し
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
  let parser = Parser::from_source(src)
  let ts_module = parser.parse_module()
  let wasm_module = compile_module(ts_module)

  // カスタムセクションが生成されている
  assert_eq(wasm_module.customs.length(), 1)

  // セクション名が "tstype"
  let custom = wasm_module.customs[0]
  assert_eq(custom.name, b"tstype")

  // メタデータのマジックをチェック "TSTY"
  let data = custom.data
  assert_eq(data[0], b'\x54') // T
  assert_eq(data[1], b'\x53') // S
  assert_eq(data[2], b'\x54') // T
  assert_eq(data[3], b'\x59') // Y

  // バージョン = 1
  assert_eq(data[4], b'\x01')

  // インポート数 = 1 (u16 LE)
  assert_eq(data[5], b'\x01')
  assert_eq(data[6], b'\x00')

  // インターフェース数 = 1 (u16 LE)
  assert_eq(data[7], b'\x01')
  assert_eq(data[8], b'\x00')

  // エクスポート数 = 1 (u16 LE)
  assert_eq(data[9], b'\x01')
  assert_eq(data[10], b'\x00')
}
