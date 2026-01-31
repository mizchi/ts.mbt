// JS function/closure structures and helpers.

///|
// /
pub struct JSClosure {
  id : Int
  params : Array[String]
  body : JSFuncBody
  env : JSEnv
  is_arrow : Bool
  is_strict : Bool
  is_generator : Bool
  is_async : Bool
  props : Array[JSProp]
  mut object_proto : JSValue?
} derive(Show)

///|
/// Compiled wasm function representation for AOT compilation.
pub struct CompiledFunc {
  name : String // Function name for identification
  ast : @ast.TsFunc // Original AST for fallback
  wasm_bytes : Bytes // Compiled wasm-gc module
  func_index : UInt // Function index in the wasm module
}

///|
impl Show for CompiledFunc with output(self, logger) {
  logger.write_string("CompiledFunc(\{self.name}, index=\{self.func_index})")
}

///|
/// Create a new CompiledFunc
pub fn CompiledFunc::new(
  name : String,
  ast : @ast.TsFunc,
  wasm_bytes : Bytes,
  func_index : UInt,
) -> CompiledFunc {
  { name, ast, wasm_bytes, func_index }
}

///|
/// Create a JSValue function with compiled wasm body.
/// Used by AOT compiler to wrap compiled functions.
pub fn js_new_compiled_function(
  name : String,
  ast : @ast.TsFunc,
  wasm_bytes : Bytes,
  func_index : UInt,
  env : JSEnv,
) -> JSValue {
  let param_names : Array[String] = []
  for p in ast.params {
    match p.binding {
      Some(@ast.TsBinding::Ident(id)) => param_names.push(id)
      _ => param_names.push("_")
    }
  }
  let compiled = CompiledFunc::new(name, ast, wasm_bytes, func_index)
  JSValue::Function({
    id: fresh_function_id(),
    params: param_names,
    body: Compiled(compiled),
    env,
    is_arrow: false,
    is_strict: false,
    is_generator: ast.is_generator,
    is_async: ast.is_async,
    props: [],
    object_proto: None,
  })
}

///|
// / function(AST)
pub enum JSFuncBody {
  Ast(@ast.TsFunc) // Interpreted function
  Native(String) // Built-in native function
  Bound(JSValue, JSValue, Array[JSValue]) // target, thisArg, bound args
  Compiled(CompiledFunc) // AOT compiled to wasm-gc
} derive(Show)

// === ID generator (object/function/array identity) ===

///|
priv struct IdGen {
  mut object_id : Int
  mut function_id : Int
  mut array_id : Int
}

///|
let id_gen : IdGen = { object_id: 1, function_id: 1, array_id: 1 }

///|
fn fresh_object_id() -> Int {
  let id = id_gen.object_id
  id_gen.object_id = id + 1
  gc_stats.objects_created += 1
  id
}

///|
fn fresh_function_id() -> Int {
  let id = id_gen.function_id
  id_gen.function_id = id + 1
  gc_stats.functions_created += 1
  id
}

///|
fn fresh_array_id() -> Int {
  let id = id_gen.array_id
  id_gen.array_id = id + 1
  gc_stats.arrays_created += 1
  id
}

// === GC stats tracking ===

///|
/// Tracks allocation statistics for GC testing
pub struct GCStats {
  mut objects_created : Int
  mut functions_created : Int
  mut arrays_created : Int
  mut envs_created : Int
}

///|
let gc_stats : GCStats = {
  objects_created: 0,
  functions_created: 0,
  arrays_created: 0,
  envs_created: 0,
}

///|
/// Reset GC stats counters
pub fn gc_stats_reset() -> Unit {
  gc_stats.objects_created = 0
  gc_stats.functions_created = 0
  gc_stats.arrays_created = 0
  gc_stats.envs_created = 0
}

///|
/// Get current GC stats snapshot
pub fn gc_stats_snapshot() -> (Int, Int, Int, Int) {
  (
    gc_stats.objects_created,
    gc_stats.functions_created,
    gc_stats.arrays_created,
    gc_stats.envs_created,
  )
}

///|
/// Get total allocations since last reset
pub fn gc_stats_total() -> Int {
  gc_stats.objects_created +
  gc_stats.functions_created +
  gc_stats.arrays_created +
  gc_stats.envs_created
}

///|
/// Increment env counter (called from jsvalue_env.mbt)
pub fn gc_stats_inc_env() -> Unit {
  gc_stats.envs_created += 1
}

// === typecheck ===

///|
// / nativefunctioncreate
pub fn js_new_native_function_with_env(
  name : String,
  env : JSEnv,
  object_proto : JSValue?,
) -> JSValue {
  JSValue::Function({
    id: fresh_function_id(),
    params: [],
    body: Native(name),
    env,
    is_arrow: false,
    is_strict: false,
    is_generator: false,
    is_async: false,
    props: [],
    object_proto,
  })
}
