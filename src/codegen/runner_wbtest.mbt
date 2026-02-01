// WasmRunner - pluggable wasm execution backend

///|
/// Result of wasm function execution
pub enum RunResult {
  F64(Double)
  I32(Int)
  Error(String)
}

///|
/// Runner type enum
pub enum RunnerType {
  Wasmx
  WasmtimeCli
}

///|
/// Global runner type
let runner_type : Ref[RunnerType?] = { val: None }

///|
/// Set the global runner type
pub fn set_runner_type(r : RunnerType) -> Unit {
  runner_type.val = Some(r)
}

///|
/// Clear the global runner
pub fn clear_runner() -> Unit {
  runner_type.val = None
}

///|
/// Check if runner is available
pub fn has_runner() -> Bool {
  match runner_type.val {
    Some(_) => true
    None => false
  }
}

///|
/// Run wasm with the configured runner
pub fn run_wasm(
  wasm_bytes : Bytes,
  func_name : String,
  args : Array[Double]
) -> RunResult {
  match runner_type.val {
    Some(Wasmx) => run_with_wasmx(wasm_bytes, func_name, args)
    Some(WasmtimeCli) => run_with_wasmtime(wasm_bytes, func_name, args)
    None => RunResult::Error("No runner configured")
  }
}

///|
/// Run with wasmx
fn run_with_wasmx(
  wasm_bytes : Bytes,
  func_name : String,
  args : Array[Double]
) -> RunResult {
  // Parse wasm bytes to module
  let module_ = @parse.parse(wasm_bytes) catch {
    e => return RunResult::Error("Parse error: \{e}")
  }

  // Load runtime
  let runtime = @runtime.Runtime::load(module_) catch {
    e => return RunResult::Error("Load error: \{e}")
  }

  // Run start function
  runtime.run_start() catch {
    e => return RunResult::Error("Start error: \{e}")
  }

  // Convert args to Value
  let wasm_args : Array[@runtime.Value] = []
  for arg in args {
    wasm_args.push(@runtime.Value::F64(arg))
  }

  // Call function
  let func_bytes = Bytes::from_iter(func_name.iter().map(fn(c) { c.to_int().to_byte() }))
  let results = runtime.call_compiled(func_bytes, wasm_args) catch {
    e => return RunResult::Error("Call error: \{e}")
  }

  // Return first result
  if results.length() > 0 {
    match results[0] {
      @runtime.Value::F64(v) => RunResult::F64(v)
      @runtime.Value::I32(v) => RunResult::I32(v.reinterpret_as_int())
      _ => RunResult::Error("Unsupported result type")
    }
  } else {
    RunResult::Error("No result")
  }
}

///|
/// Helper to assert F64 result
pub fn assert_run_f64(
  wasm_bytes : Bytes,
  func_name : String,
  args : Array[Double],
  expected : Double
) -> Unit raise Error {
  match run_wasm(wasm_bytes, func_name, args) {
    RunResult::F64(v) => assert_eq(v, expected)
    RunResult::Error(e) => fail("Run error: \{e}")
    _ => fail("Expected F64 result")
  }
}

///|
test "runner: basic wasmx test" {
  set_runner_type(RunnerType::Wasmx)

  let src =
    #|function add(a: number, b: number): number {
    #|  return a + b;
    #|}

  let wasm = compile_to_wasm(src)
  assert_run_f64(wasm, "add", [3.0, 5.0], 8.0)

  clear_runner()
}

///|
test "runner: basic wasmtime test" {
  set_runner_type(RunnerType::WasmtimeCli)

  let src =
    #|function add(a: number, b: number): number {
    #|  return a + b;
    #|}

  let wasm = compile_to_wasm(src)
  match run_wasm(wasm, "add", [3.0, 5.0]) {
    RunResult::F64(v) => assert_eq(v, 8.0)
    RunResult::Error(e) => {
      // wasmtime may not be installed, so allow error
      println("Wasmtime CLI error (may be expected): \{e}")
    }
    _ => fail("Expected F64 result")
  }

  clear_runner()
}
