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
// / function(AST)
pub enum JSFuncBody {
  Ast(@ast.TsFunc) // run
  Native(String) // function
  Bound(JSValue, JSValue, Array[JSValue]) // target, thisArg, bound args
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
  id
}

///|
fn fresh_function_id() -> Int {
  let id = id_gen.function_id
  id_gen.function_id = id + 1
  id
}

///|
fn fresh_array_id() -> Int {
  let id = id_gen.array_id
  id_gen.array_id = id + 1
  id
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
    is_generator: false, is_async: false,
    props: [],
    object_proto,
  })
}
