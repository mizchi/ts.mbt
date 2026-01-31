// AOT Runtime - Execute compiled wasm functions using wasm5 runtime.

///|
/// AOT runtime for executing compiled wasm functions.
pub struct AOTRuntime {
  // Compiled wasm module as bytes
  wasm_bytes : Bytes
  // wasm5 runtime instance (lazy initialized)
  mut runtime : @wasm_runtime.Runtime?
  // Function name to export index mapping
  func_indices : Map[String, Int]
  // Original AST functions for fallback
  fallback_funcs : Map[String, @ast.TsFunc]
}

///|
/// Create a new AOT runtime from compilation result.
pub fn AOTRuntime::new(compiled_module : AOTCompiledModule) -> AOTRuntime {
  let func_indices : Map[String, Int] = {}
  let fallback_funcs : Map[String, @ast.TsFunc] = {}
  for i, func in compiled_module.functions {
    func_indices[func.name] = i
    fallback_funcs[func.name] = func.ast
  }
  {
    wasm_bytes: compiled_module.wasm_bytes,
    runtime: None,
    func_indices,
    fallback_funcs,
  }
}

///|
/// Runtime initialization error.
pub suberror RuntimeInitError {
  ParseError(String)
  LoadError(String)
  CallError(String)
}

///|
/// Initialize the wasm runtime (lazy).
fn AOTRuntime::init_runtime(
  self : AOTRuntime,
) -> @wasm_runtime.Runtime raise RuntimeInitError {
  match self.runtime {
    Some(rt) => rt
    None => {
      // Parse the wasm bytes
      let module_ = @parse.parse(self.wasm_bytes) catch {
        e => raise RuntimeInitError::ParseError(e.to_string())
      }
      // Load into runtime
      let rt = @wasm_runtime.Runtime::load(module_) catch {
        e => raise RuntimeInitError::LoadError(e.to_string())
      }
      self.runtime = Some(rt)
      rt
    }
  }
}

///|
/// Call a compiled function by name.
pub fn AOTRuntime::call(
  self : AOTRuntime,
  name : String,
  args : Array[Double],
) -> Double raise RuntimeInitError {
  let rt = self.init_runtime()
  // Convert args to wasm values
  let wasm_args : Array[@core.Value] = []
  for arg in args {
    wasm_args.push(@core.Value::F64(arg))
  }
  // Call the function
  let name_bytes = Bytes::from_array(
    name.to_array().map(fn(c) { c.to_int().to_byte() }),
  )
  let results = rt.call_compiled(name_bytes, wasm_args) catch {
    e => raise RuntimeInitError::CallError(e.to_string())
  }
  // Convert result back
  if results.length() > 0 {
    match results[0] {
      @core.Value::F64(v) => v
      @core.Value::I32(v) => v.reinterpret_as_int().to_double()
      @core.Value::I64(v) => v.to_double()
      @core.Value::F32(v) => v.to_double()
      _ => 0.0
    }
  } else {
    0.0
  }
}

///|
/// Check if a function is available in the AOT runtime.
pub fn AOTRuntime::has_function(self : AOTRuntime, name : String) -> Bool {
  self.func_indices.contains(name)
}

///|
/// Get the original AST for fallback.
pub fn AOTRuntime::get_fallback(
  self : AOTRuntime,
  name : String,
) -> @ast.TsFunc? {
  self.fallback_funcs.get(name)
}

///|
/// Compiled module containing all AOT-compiled functions.
pub struct AOTCompiledModule {
  // All compiled functions in order
  functions : Array[AOTCompiledFunction]
  // Combined wasm module bytes
  wasm_bytes : Bytes
}

///|
/// AOT compilation error type.
pub suberror AOTError {
  CodeGenError(String)
  EncodeError(String)
}

///|
/// Compile a module to a single wasm module with all compilable functions.
pub fn compile_module_to_wasm(
  mod : @ast.TsModule,
) -> AOTCompiledModule raise AOTError {
  // Get all compilable functions
  let compilable = @analysis.find_compilable_functions(mod)
  if compilable.length() == 0 {
    return { functions: [], wasm_bytes: b"" }
  }
  // Create a module with only compilable functions
  let funcs : Array[@ast.TsFunc] = []
  for pair in compilable {
    funcs.push(pair.1)
  }
  let compile_mod : @ast.TsModule = {
    funcs,
    interfaces: mod.interfaces,
    imports: mod.imports,
  }
  // Compile to wasm-gc
  let wasm_module = @codegen.compile_module_gc(compile_mod) catch {
    e => raise AOTError::CodeGenError(e.to_string())
  }
  // Encode to bytes
  let wasm_bytes = @encode.encode(wasm_module) catch {
    e => raise AOTError::EncodeError(e.to_string())
  }
  // Create function info
  let functions : Array[AOTCompiledFunction] = []
  for i, pair in compilable {
    functions.push({
      name: pair.0,
      ast: pair.1,
      wasm_bytes, // Same module for all
      func_index: i.reinterpret_as_uint(),
    })
  }
  { functions, wasm_bytes }
}

///|
/// Create an AOT runtime from a TypeScript module.
pub fn create_aot_runtime(mod : @ast.TsModule) -> AOTRuntime raise AOTError {
  let compiled = compile_module_to_wasm(mod)
  AOTRuntime::new(compiled)
}
