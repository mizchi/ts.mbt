// JSValue interpreter
// ASTrun

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
}

///|
pub(all) struct JSGeneratorState {
  func : @parser.TsFunc
  env : JSEnv
  mut index : Int
  mut done : Bool
}

///|
priv enum GenSignal {
  Continue
  Yield(JSValue)
  Return(JSValue)
}

///|
// / interpretercreate
pub fn JSInterpreter::new() -> JSInterpreter {
  let env = js_new_env(None)
  let object_proto = js_new_object()
  let function_proto = JSValue::Function({
    id: fresh_function_id(),
    params: [],
    body: Native("Function.prototype"),
    env,
    is_arrow: false,
    is_strict: false,
    is_generator: false,
    props: [],
    object_proto: Some(object_proto),
  })
  let interp = {
    global_env: env,
    last_error: None,
    steps: 0,
    step_limit: 1_000_000,
    object_proto,
    function_proto,
    generators: [],
  }
  interp.install_builtins()
  interp
}

///|
// / step limit
pub fn JSInterpreter::set_step_limit(self : JSInterpreter, limit : Int) -> Unit {
  if limit > 0 {
    self.step_limit = limit
  }
}

///|
// / functioncreate
fn JSInterpreter::make_native(self : JSInterpreter, name : String) -> JSValue {
  JSValue::Function({
    id: fresh_function_id(),
    params: [],
    body: Native(name),
    env: self.global_env,
    is_arrow: false,
    is_strict: false,
    is_generator: false,
    props: [],
    object_proto: Some(self.function_proto),
  })
}

///|
// / arguments objectcreate
fn JSInterpreter::make_arguments(
  self : JSInterpreter,
  args : Array[JSValue],
) -> JSValue {
  let obj = self.new_object()
  let _ = js_set_prop(obj, "__class", String("Arguments"))
  for i, item in args {
    let _ = js_set_prop(obj, i.to_string(), item)
  }
  let _ = js_set_prop(obj, "length", Number(args.length().to_double()))
  obj
}

///|
// / function length propertyset
fn JSInterpreter::set_function_length(
  _self : JSInterpreter,
  func : JSValue,
  len : Double,
) -> Unit {
  let _ = js_define_data_prop(func, "length", Number(len), false, false, true)
}

///|
// / function name propertyset
fn JSInterpreter::set_function_name(
  _self : JSInterpreter,
  func : JSValue,
  name : String,
) -> Unit {
  let _ = js_define_data_prop(func, "name", String(name), false, false, true)
}

///|
// / datacreate
fn JSInterpreter::make_data_descriptor(
  self : JSInterpreter,
  value : JSValue,
  writable : Bool,
  enumerable : Bool,
  configurable : Bool,
) -> JSValue {
  let desc = self.new_object()
  let _ = js_set_prop(desc, "value", value)
  let _ = js_set_prop(desc, "writable", Bool(writable))
  let _ = js_set_prop(desc, "enumerable", Bool(enumerable))
  let _ = js_set_prop(desc, "configurable", Bool(configurable))
  desc
}

///|
// / RegExp objectcreate
fn JSInterpreter::make_regexp(
  self : JSInterpreter,
  pattern : String,
  flags : String,
) -> JSValue {
  match regexp_compile(pattern, flags) {
    None =>
      return self.set_error_kind("SyntaxError", "Invalid regular expression")
    Some(_) => ()
  }
  let ctor = self.global_env.get("RegExp")
  let proto = match ctor {
    Function(_) => js_get_prop(ctor, "prototype")
    _ => self.object_proto
  }
  let obj = js_new_object_with_proto(Some(proto))
  let _ = js_set_prop(obj, "__class", String("RegExp"))
  let _ = js_set_prop(obj, "source", String(pattern))
  let _ = js_set_prop(obj, "flags", String(flags))
  let _ = js_set_prop(obj, "global", Bool(regexp_has_global(flags)))
  let _ = js_set_prop(obj, "lastIndex", Number(0.0))
  obj
}

///|
// / create
fn JSInterpreter::make_accessor_descriptor(
  self : JSInterpreter,
  get : JSValue?,
  set : JSValue?,
  enumerable : Bool,
  configurable : Bool,
) -> JSValue {
  let desc = self.new_object()
  match get {
    Some(g) => {
      let _ = js_set_prop(desc, "get", g)
    }
    None => {
      let _ = js_set_prop(desc, "get", Undefined)
    }
  }
  match set {
    Some(s) => {
      let _ = js_set_prop(desc, "set", s)
    }
    None => {
      let _ = js_set_prop(desc, "set", Undefined)
    }
  }
  let _ = js_set_prop(desc, "enumerable", Bool(enumerable))
  let _ = js_set_prop(desc, "configurable", Bool(configurable))
  desc
}

///|
// / bound function length compute
fn JSInterpreter::calc_bound_length(
  _self : JSInterpreter,
  target : JSValue,
  bound_arg_len : Int,
) -> Double {
  let target_len = js_get_prop(target, "length")
  match target_len {
    Number(n) => {
      if n.is_nan() || n == 0.0 {
        0.0
      } else if n.is_pos_inf() {
        n
      } else if n.is_neg_inf() {
        0.0
      } else {
        let abs = n.abs()
        let int_val = abs.floor()
        let signed = if n < 0.0 { -int_val } else { int_val }
        let mut len = signed - bound_arg_len.to_double()
        if len < 0.0 {
          len = 0.0
        }
        if len == 0.0 {
          len = 0.0
        }
        len
      }
    }
    _ => 0.0
  }
}

///|
// / strict mode check
fn JSInterpreter::is_strict_body(
  _self : JSInterpreter,
  body : @parser.TsBlock,
  inherit_strict : Bool,
) -> Bool {
  if inherit_strict {
    return true
  }
  if body.stmts.length() == 0 {
    return false
  }
  match body.stmts[0] {
    @parser.TsStmt::Expr(@parser.TsExpr::StringLit(s)) => s == "use strict"
    _ => false
  }
}

///|
// / errorobjectcreate
fn JSInterpreter::set_error(self : JSInterpreter, message : String) -> JSValue {
  self.set_error_kind("Error", message)
}

///|
// / errorerrorobjectcreate
fn JSInterpreter::set_error_kind(
  self : JSInterpreter,
  name : String,
  message : String,
) -> JSValue {
  let obj = self.make_error_obj(name, message)
  let _ = js_set_prop(obj, "error", js_get_prop(obj, "message"))
  self.last_error = Some(obj)
  obj
}

///|
// / errorobjectcreate
fn JSInterpreter::make_error_obj(
  self : JSInterpreter,
  name : String,
  message : String,
) -> JSValue {
  let ctor = self.global_env.get(name)
  let proto = match ctor {
    Function(_) => {
      let p = js_get_prop(ctor, "prototype")
      match p {
        Object(_) | Function(_) => Some(p)
        _ => Some(self.object_proto)
      }
    }
    _ => Some(self.object_proto)
  }
  let obj = js_new_object_with_proto(proto)
  let _ = js_set_prop(obj, "name", JSValue::String(name))
  let _ = js_set_prop(obj, "message", JSValue::String(message))
  obj
}

///|
// / run
fn JSInterpreter::tick(self : JSInterpreter) -> Unit {
  match self.last_error {
    Some(_) => ()
    None => {
      self.steps += 1
      if self.steps > self.step_limit {
        let _ = self.set_error("Step limit exceeded")
      }
    }
  }
}

///|
// / errorget
fn JSInterpreter::take_error(self : JSInterpreter) -> JSValue? {
  match self.last_error {
    Some(err) => {
      self.last_error = None
      Some(err)
    }
    None => None
  }
}

///|
// / error()
fn JSInterpreter::peek_error(self : JSInterpreter) -> JSValue? {
  self.last_error
}

///|
// / Object.prototype objectcreate
fn JSInterpreter::new_object(self : JSInterpreter) -> JSValue {
  js_new_object_with_proto(Some(self.object_proto))
}

