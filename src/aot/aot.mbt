// AOT (Ahead-of-Time) compilation for TypeScript to wasm-gc.

///|
/// Result of AOT compilation for a single function.
pub struct AOTCompiledFunction {
  name : String
  ast : @ast.TsFunc
  wasm_bytes : Bytes
  func_index : UInt
}

///|
/// Result of AOT compilation for a module.
pub struct AOTCompilationResult {
  compiled_functions : Array[AOTCompiledFunction]
  uncompiled_functions : Array[@ast.TsFunc]
}

///|
/// Compile all compilable functions in a module to wasm-gc.
/// Returns both the compiled functions and the functions that couldn't be compiled.
pub fn compile_module_aot(mod : @ast.TsModule) -> AOTCompilationResult {
  let compiled : Array[AOTCompiledFunction] = []
  let uncompiled : Array[@ast.TsFunc] = []
  // Find compilable functions
  let compilable = @analysis.find_compilable_functions(mod)
  let compilable_names : Array[String] = []
  for pair in compilable {
    compilable_names.push(pair.0)
  }
  // Try to compile each compilable function
  for pair in compilable {
    let (name, func) = pair
    match compile_single_function(func) {
      Some((wasm_bytes, func_index)) =>
        compiled.push({ name, ast: func, wasm_bytes, func_index })
      None =>
        // Compilation failed, add to uncompiled
        uncompiled.push(func)
    }
  }
  // Add non-compilable functions to uncompiled
  for func in mod.funcs {
    if not(compilable_names.contains(func.name)) {
      uncompiled.push(func)
    }
  }
  { compiled_functions: compiled, uncompiled_functions: uncompiled }
}

///|
/// Try to compile a single function to wasm-gc.
/// Returns the wasm bytes and function index on success, None on failure.
fn compile_single_function(func : @ast.TsFunc) -> (Bytes, UInt)? {
  // Create a minimal module with just this function
  let mod : @ast.TsModule = { funcs: [func], interfaces: [], imports: [] }
  try {
    let wasm_module = @codegen.compile_module_gc(mod)
    // Encode the module to bytes
    let encoded = @encode.encode(wasm_module)
    // The function index is 0 since it's the only function
    Some((encoded, 0U))
  } catch {
    _ => None
  }
}

///|
/// Check if a function is compilable to wasm-gc.
pub fn is_function_compilable(func : @ast.TsFunc) -> Bool {
  @analysis.can_compile_to_wasm(func).is_compilable()
}

///|
/// Get compilation info for a module (useful for debugging).
pub fn get_compilation_info(
  mod : @ast.TsModule,
) -> (Int, Int, Array[String], Array[String]) {
  let compilable : Array[String] = []
  let not_compilable : Array[String] = []
  for func in mod.funcs {
    match @analysis.can_compile_to_wasm(func) {
      @analysis.CompilabilityResult::Compilable => compilable.push(func.name)
      @analysis.CompilabilityResult::NotCompilable(reason) =>
        not_compilable.push("\{func.name}: \{reason}")
    }
  }
  (compilable.length(), not_compilable.length(), compilable, not_compilable)
}
