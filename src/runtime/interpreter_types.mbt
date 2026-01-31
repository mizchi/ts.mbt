// JSValue interpreter types

///|
// / interpreter
pub struct JSInterpreter {
  global_env : JSEnv
  mut last_error : JSValue?
  mut steps : Int
  mut step_limit : Int
  object_proto : JSValue
  function_proto : JSValue
  generators : Array[JSGeneratorState]
  mut current_gen_id : Int?
  mut microtasks : Array[MicrotaskJob]
  mut symbol_counter : Int
  symbol_registry : Map[String, String] // Global symbol registry for Symbol.for/keyFor
}

///|
pub(all) struct JSGeneratorState {
  func : @ast.TsFunc
  env : JSEnv
  mut index : Int
  mut done : Bool
  mut cont : ((JSValue) -> GenSignal)?
  mut active_iterators : Array[JSValue]
  // AOT mode fields
  mut aot_mode : Bool // true if this generator is AOT compiled
  mut aot_wasm_bytes : Bytes? // compiled wasm module bytes
  mut aot_state_data : Array[Double] // state struct data: [state_num, done_flag, params..., locals...]
}

///|
pub(all) enum GenSignal {
  Continue
  Yield(JSValue)
  YieldRaw(JSValue) // For yield*: returns the raw iterator result object as-is
  Suspend(JSValue, (JSValue) -> GenSignal)
  SuspendRaw(JSValue, (JSValue) -> GenSignal) // For yield*: raw result with continuation
  Return(JSValue)
}

///|
pub(all) struct MicrotaskJob {
  handler : JSValue
  argument : JSValue
  promise : JSValue?
  is_reject : Bool
}
