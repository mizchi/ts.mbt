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
}

///|
pub(all) struct JSGeneratorState {
  func : @ast.TsFunc
  env : JSEnv
  mut index : Int
  mut done : Bool
  mut cont : ((JSValue) -> GenSignal)?
  mut active_iterators : Array[JSValue]
}

///|
pub(all) enum GenSignal {
  Continue
  Yield(JSValue)
  Suspend(JSValue, (JSValue) -> GenSignal)
  Return(JSValue)
}

///|
pub(all) struct MicrotaskJob {
  handler : JSValue
  argument : JSValue
  promise : JSValue?
  is_reject : Bool
}
