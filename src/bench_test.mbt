///|
fn make_large_source(funcs : Int) -> String {
  let sb = StringBuilder::new()
  let mut i = 0
  while i < funcs {
    sb..write_string("function f")
      ..write_string(i.to_string())
      ..write_string("(x) { return x + ")
      ..write_string(i.to_string())
      ..write_string("; }\n")
    i = i + 1
  }
  sb..write_string("function main() {\n")
    ..write_string("  let acc = 0;\n")
  let mut j = 0
  while j < funcs {
    sb..write_string("  acc += f")
      ..write_string(j.to_string())
      ..write_string("(")
      ..write_string(j.to_string())
      ..write_string(");\n")
    j = j + 1
  }
  sb..write_string("  return acc;\n")
    ..write_string("}\n")
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
