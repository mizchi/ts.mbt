// JSValue interpreter
// ASTrun

///|
// / interpreter
pub struct JSInterpreter {
  global_env : JSEnv
  mut last_error : JSValue?
  mut steps : Int
  step_limit : Int
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

///|
// /
fn JSInterpreter::install_builtins(self : JSInterpreter) -> Unit {
  let global_obj = self.new_object()

  // Object.prototype
  let has_own = self.make_native("Object.hasOwnProperty")
  self.set_function_length(has_own, 1.0)
  let _ = js_set_prop(self.object_proto, "hasOwnProperty", has_own)
  let to_string_fn = self.make_native("Object.prototype.toString")
  self.set_function_length(to_string_fn, 0.0)
  let _ = js_set_prop(self.object_proto, "toString", to_string_fn)
  let is_proto_fn = self.make_native("Object.prototype.isPrototypeOf")
  self.set_function_length(is_proto_fn, 1.0)
  let _ = js_set_prop(self.object_proto, "isPrototypeOf", is_proto_fn)
  let value_of_fn = self.make_native("Object.prototype.valueOf")
  self.set_function_length(value_of_fn, 0.0)
  let _ = js_set_prop(self.object_proto, "valueOf", value_of_fn)
  let prop_enum_fn = self.make_native("Object.prototype.propertyIsEnumerable")
  self.set_function_length(prop_enum_fn, 1.0)
  let _ = js_set_prop(self.object_proto, "propertyIsEnumerable", prop_enum_fn)

  // Object
  let object_ctor = self.make_native("Object")
  let _ = js_define_data_prop(object_ctor, "prototype", self.object_proto, true, false, true)
  let _ = js_set_prop(object_ctor, "name", JSValue::String("Object"))
  let _ = js_set_prop(self.object_proto, "constructor", object_ctor)
  let get_own = self.make_native("Object.getOwnPropertyNames")
  self.set_function_length(get_own, 1.0)
  let _ = js_set_prop(object_ctor, "getOwnPropertyNames", get_own)
  let obj_create = self.make_native("Object.create")
  self.set_function_length(obj_create, 2.0)
  let _ = js_set_prop(object_ctor, "create", obj_create)
  let obj_get_proto = self.make_native("Object.getPrototypeOf")
  self.set_function_length(obj_get_proto, 1.0)
  let _ = js_set_prop(object_ctor, "getPrototypeOf", obj_get_proto)
  let obj_get_desc = self.make_native("Object.getOwnPropertyDescriptor")
  self.set_function_length(obj_get_desc, 2.0)
  let _ = js_set_prop(object_ctor, "getOwnPropertyDescriptor", obj_get_desc)
  let obj_define_prop = self.make_native("Object.defineProperty")
  self.set_function_length(obj_define_prop, 3.0)
  let _ = js_set_prop(object_ctor, "defineProperty", obj_define_prop)
  let obj_is_ext = self.make_native("Object.isExtensible")
  self.set_function_length(obj_is_ext, 1.0)
  let _ = js_set_prop(object_ctor, "isExtensible", obj_is_ext)
  self.global_env.define_var("Object", object_ctor)
  let _ = js_set_prop(global_obj, "Object", object_ctor)

  // console
  let console = self.new_object()
  let _ = js_set_prop(console, "log", self.make_native("console.log"))
  self.global_env.define_var("console", console)
  let _ = js_set_prop(global_obj, "console", console)

  // Math
  let math = self.new_object()
  let _ = js_set_prop(math, "floor", self.make_native("Math.floor"))
  let _ = js_set_prop(math, "ceil", self.make_native("Math.ceil"))
  let _ = js_set_prop(math, "abs", self.make_native("Math.abs"))
  let _ = js_set_prop(math, "sqrt", self.make_native("Math.sqrt"))
  let _ = js_set_prop(math, "min", self.make_native("Math.min"))
  let _ = js_set_prop(math, "max", self.make_native("Math.max"))
  let _ = js_set_prop(math, "round", self.make_native("Math.round"))
  let _ = js_set_prop(math, "random", self.make_native("Math.random"))
  let _ = js_set_prop(math, "cos", self.make_native("Math.cos"))
  let _ = js_set_prop(math, "sin", self.make_native("Math.sin"))
  let _ = js_set_prop(math, "tan", self.make_native("Math.tan"))
  let _ = js_set_prop(math, "exp", self.make_native("Math.exp"))
  let _ = js_set_prop(math, "log", self.make_native("Math.log"))
  let _ = js_define_data_prop(math, "PI", Number(@math.PI), false, false, false)
  let _ = js_define_data_prop(math, "E", Number(@math.exp(1.0)), false, false, false)
  let _ = js_define_data_prop(math, "LN2", Number(@math.ln(2.0)), false, false, false)
  self.global_env.define_var("Math", math)
  let _ = js_set_prop(global_obj, "Math", math)

  // Function
  let call_fn = self.make_native("Function.call")
  self.set_function_length(call_fn, 1.0)
  let _ = js_set_prop(self.function_proto, "call", call_fn)
  let apply_fn = self.make_native("Function.apply")
  self.set_function_length(apply_fn, 2.0)
  let _ = js_set_prop(self.function_proto, "apply", apply_fn)
  let bind_fn = self.make_native("Function.bind")
  self.set_function_length(bind_fn, 1.0)
  let _ = js_set_prop(self.function_proto, "bind", bind_fn)
  let has_instance = self.make_native("Function.prototype[@@hasInstance]")
  self.set_function_length(has_instance, 1.0)
  let _ = js_set_prop(self.function_proto, "@@hasInstance", has_instance)
  self.set_function_length(self.function_proto, 0.0)
  self.set_function_name(self.function_proto, "")
  let function_ctor = self.make_native("Function")
  self.set_function_length(function_ctor, 1.0)
  self.set_function_name(function_ctor, "Function")
  let _ = js_define_data_prop(function_ctor, "prototype", self.function_proto, true, false, true)
  let _ = js_set_prop(self.function_proto, "constructor", function_ctor)
  self.global_env.define_var("Function", function_ctor)
  let _ = js_set_prop(global_obj, "Function", function_ctor)

  // Boolean / Number / String
  let boolean_proto = self.new_object()
  let boolean_ctor = self.make_native("Boolean")
  self.set_function_length(boolean_ctor, 1.0)
  self.set_function_name(boolean_ctor, "Boolean")
  let _ = js_define_data_prop(boolean_ctor, "prototype", boolean_proto, true, false, true)
  let _ = js_set_prop(boolean_proto, "constructor", boolean_ctor)
  let bool_value_of = self.make_native("Boolean.prototype.valueOf")
  self.set_function_length(bool_value_of, 0.0)
  let _ = js_set_prop(boolean_proto, "valueOf", bool_value_of)
  self.global_env.define_var("Boolean", boolean_ctor)
  let _ = js_set_prop(global_obj, "Boolean", boolean_ctor)

  let number_proto = self.new_object()
  let number_ctor = self.make_native("Number")
  self.set_function_length(number_ctor, 1.0)
  self.set_function_name(number_ctor, "Number")
  let _ = js_define_data_prop(number_ctor, "prototype", number_proto, true, false, true)
  let _ = js_set_prop(number_proto, "constructor", number_ctor)
  let num_value_of = self.make_native("Number.prototype.valueOf")
  self.set_function_length(num_value_of, 0.0)
  let _ = js_set_prop(number_proto, "valueOf", num_value_of)
  let max_safe = JSValue::Number(9007199254740991.0)
  let _ = js_define_data_prop(number_ctor, "MAX_SAFE_INTEGER", max_safe, false, false, false)
  self.global_env.define_var("Number", number_ctor)
  let _ = js_set_prop(global_obj, "Number", number_ctor)

  let string_proto = self.new_object()
  let string_ctor = self.make_native("String")
  self.set_function_length(string_ctor, 1.0)
  self.set_function_name(string_ctor, "String")
  let _ = js_define_data_prop(string_ctor, "prototype", string_proto, true, false, true)
  let _ = js_set_prop(string_proto, "constructor", string_ctor)
  let str_value_of = self.make_native("String.prototype.valueOf")
  self.set_function_length(str_value_of, 0.0)
  let _ = js_set_prop(string_proto, "valueOf", str_value_of)
  let str_to_string = self.make_native("String.prototype.toString")
  self.set_function_length(str_to_string, 0.0)
  let _ = js_set_prop(string_proto, "toString", str_to_string)
  let str_char_at = self.make_native("String.prototype.charAt")
  self.set_function_length(str_char_at, 1.0)
  let _ = js_set_prop(string_proto, "charAt", str_char_at)
  let str_char_code_at = self.make_native("String.prototype.charCodeAt")
  self.set_function_length(str_char_code_at, 1.0)
  let _ = js_set_prop(string_proto, "charCodeAt", str_char_code_at)
  let str_code_point_at = self.make_native("String.prototype.codePointAt")
  self.set_function_length(str_code_point_at, 1.0)
  let _ = js_set_prop(string_proto, "codePointAt", str_code_point_at)
  let str_index_of = self.make_native("String.prototype.indexOf")
  self.set_function_length(str_index_of, 1.0)
  let _ = js_set_prop(string_proto, "indexOf", str_index_of)
  let str_last_index_of = self.make_native("String.prototype.lastIndexOf")
  self.set_function_length(str_last_index_of, 1.0)
  let _ = js_set_prop(string_proto, "lastIndexOf", str_last_index_of)
  let str_includes = self.make_native("String.prototype.includes")
  self.set_function_length(str_includes, 1.0)
  let _ = js_set_prop(string_proto, "includes", str_includes)
  let str_starts_with = self.make_native("String.prototype.startsWith")
  self.set_function_length(str_starts_with, 1.0)
  let _ = js_set_prop(string_proto, "startsWith", str_starts_with)
  let str_ends_with = self.make_native("String.prototype.endsWith")
  self.set_function_length(str_ends_with, 1.0)
  let _ = js_set_prop(string_proto, "endsWith", str_ends_with)
  let str_at = self.make_native("String.prototype.at")
  self.set_function_length(str_at, 1.0)
  let _ = js_set_prop(string_proto, "at", str_at)
  let str_split = self.make_native("String.prototype.split")
  self.set_function_length(str_split, 2.0)
  let _ = js_set_prop(string_proto, "split", str_split)
  let str_replace = self.make_native("String.prototype.replace")
  self.set_function_length(str_replace, 2.0)
  let _ = js_set_prop(string_proto, "replace", str_replace)
  let str_replace_all = self.make_native("String.prototype.replaceAll")
  self.set_function_length(str_replace_all, 2.0)
  let _ = js_set_prop(string_proto, "replaceAll", str_replace_all)
  let str_trim = self.make_native("String.prototype.trim")
  self.set_function_length(str_trim, 0.0)
  let _ = js_set_prop(string_proto, "trim", str_trim)
  let str_trim_start = self.make_native("String.prototype.trimStart")
  self.set_function_length(str_trim_start, 0.0)
  let _ = js_set_prop(string_proto, "trimStart", str_trim_start)
  let str_trim_end = self.make_native("String.prototype.trimEnd")
  self.set_function_length(str_trim_end, 0.0)
  let _ = js_set_prop(string_proto, "trimEnd", str_trim_end)
  let str_substring = self.make_native("String.prototype.substring")
  self.set_function_length(str_substring, 2.0)
  let _ = js_set_prop(string_proto, "substring", str_substring)
  let str_concat = self.make_native("String.prototype.concat")
  self.set_function_length(str_concat, 1.0)
  let _ = js_set_prop(string_proto, "concat", str_concat)
  let str_to_upper = self.make_native("String.prototype.toUpperCase")
  self.set_function_length(str_to_upper, 0.0)
  let _ = js_set_prop(string_proto, "toUpperCase", str_to_upper)
  let str_to_lower = self.make_native("String.prototype.toLowerCase")
  self.set_function_length(str_to_lower, 0.0)
  let _ = js_set_prop(string_proto, "toLowerCase", str_to_lower)
  let str_to_locale_upper = self.make_native("String.prototype.toLocaleUpperCase")
  self.set_function_length(str_to_locale_upper, 0.0)
  let _ = js_set_prop(string_proto, "toLocaleUpperCase", str_to_locale_upper)
  let str_to_locale_lower = self.make_native("String.prototype.toLocaleLowerCase")
  self.set_function_length(str_to_locale_lower, 0.0)
  let _ = js_set_prop(string_proto, "toLocaleLowerCase", str_to_locale_lower)
  let str_repeat = self.make_native("String.prototype.repeat")
  self.set_function_length(str_repeat, 1.0)
  let _ = js_set_prop(string_proto, "repeat", str_repeat)
  let str_pad_start = self.make_native("String.prototype.padStart")
  self.set_function_length(str_pad_start, 1.0)
  let _ = js_set_prop(string_proto, "padStart", str_pad_start)
  let str_pad_end = self.make_native("String.prototype.padEnd")
  self.set_function_length(str_pad_end, 1.0)
  let _ = js_set_prop(string_proto, "padEnd", str_pad_end)
  let str_from_char_code = self.make_native("String.fromCharCode")
  self.set_function_length(str_from_char_code, 1.0)
  let _ = js_set_prop(string_ctor, "fromCharCode", str_from_char_code)
  let str_from_code_point = self.make_native("String.fromCodePoint")
  self.set_function_length(str_from_code_point, 1.0)
  let _ = js_set_prop(string_ctor, "fromCodePoint", str_from_code_point)
  self.global_env.define_var("String", string_ctor)
  let _ = js_set_prop(global_obj, "String", string_ctor)

  // RegExp (minimal)
  let regexp_proto = self.new_object()
  let regexp_ctor = self.make_native("RegExp")
  self.set_function_length(regexp_ctor, 2.0)
  self.set_function_name(regexp_ctor, "RegExp")
  let _ = js_define_data_prop(regexp_ctor, "prototype", regexp_proto, true, false, true)
  let _ = js_set_prop(regexp_proto, "constructor", regexp_ctor)
  let re_exec = self.make_native("RegExp.prototype.exec")
  self.set_function_length(re_exec, 1.0)
  let _ = js_set_prop(regexp_proto, "exec", re_exec)
  let re_test = self.make_native("RegExp.prototype.test")
  self.set_function_length(re_test, 1.0)
  let _ = js_set_prop(regexp_proto, "test", re_test)
  self.global_env.define_var("RegExp", regexp_ctor)
  let _ = js_set_prop(global_obj, "RegExp", regexp_ctor)

  // Array
  let array_proto = self.new_object()
  let array_ctor = self.make_native("Array")
  self.set_function_length(array_ctor, 1.0)
  self.set_function_name(array_ctor, "Array")
  let _ = js_define_data_prop(array_ctor, "prototype", array_proto, true, false, true)
  let _ = js_set_prop(array_proto, "constructor", array_ctor)
  js_set_default_array_proto(array_proto)
  let array_to_string = self.make_native("Array.prototype.toString")
  self.set_function_length(array_to_string, 0.0)
  let _ = js_set_prop(array_proto, "toString", array_to_string)
  let array_push = self.make_native("Array.prototype.push")
  self.set_function_length(array_push, 1.0)
  let _ = js_set_prop(array_proto, "push", array_push)
  let array_pop = self.make_native("Array.prototype.pop")
  self.set_function_length(array_pop, 0.0)
  let _ = js_set_prop(array_proto, "pop", array_pop)
  let array_shift = self.make_native("Array.prototype.shift")
  self.set_function_length(array_shift, 0.0)
  let _ = js_set_prop(array_proto, "shift", array_shift)
  let array_unshift = self.make_native("Array.prototype.unshift")
  self.set_function_length(array_unshift, 1.0)
  let _ = js_set_prop(array_proto, "unshift", array_unshift)
  let array_join = self.make_native("Array.prototype.join")
  self.set_function_length(array_join, 1.0)
  let _ = js_set_prop(array_proto, "join", array_join)
  let array_index_of = self.make_native("Array.prototype.indexOf")
  self.set_function_length(array_index_of, 1.0)
  let _ = js_set_prop(array_proto, "indexOf", array_index_of)
  let array_last_index_of = self.make_native("Array.prototype.lastIndexOf")
  self.set_function_length(array_last_index_of, 1.0)
  let _ = js_set_prop(array_proto, "lastIndexOf", array_last_index_of)
  let array_includes = self.make_native("Array.prototype.includes")
  self.set_function_length(array_includes, 1.0)
  let _ = js_set_prop(array_proto, "includes", array_includes)
  let array_map = self.make_native("Array.prototype.map")
  self.set_function_length(array_map, 1.0)
  let _ = js_set_prop(array_proto, "map", array_map)
  let array_filter = self.make_native("Array.prototype.filter")
  self.set_function_length(array_filter, 1.0)
  let _ = js_set_prop(array_proto, "filter", array_filter)
  let array_reduce = self.make_native("Array.prototype.reduce")
  self.set_function_length(array_reduce, 1.0)
  let _ = js_set_prop(array_proto, "reduce", array_reduce)
  let array_reduce_right = self.make_native("Array.prototype.reduceRight")
  self.set_function_length(array_reduce_right, 1.0)
  let _ = js_set_prop(array_proto, "reduceRight", array_reduce_right)
  let array_for_each = self.make_native("Array.prototype.forEach")
  self.set_function_length(array_for_each, 1.0)
  let _ = js_set_prop(array_proto, "forEach", array_for_each)
  let array_find = self.make_native("Array.prototype.find")
  self.set_function_length(array_find, 1.0)
  let _ = js_set_prop(array_proto, "find", array_find)
  let array_find_index = self.make_native("Array.prototype.findIndex")
  self.set_function_length(array_find_index, 1.0)
  let _ = js_set_prop(array_proto, "findIndex", array_find_index)
  let array_find_last = self.make_native("Array.prototype.findLast")
  self.set_function_length(array_find_last, 1.0)
  let _ = js_set_prop(array_proto, "findLast", array_find_last)
  let array_find_last_index = self.make_native("Array.prototype.findLastIndex")
  self.set_function_length(array_find_last_index, 1.0)
  let _ = js_set_prop(array_proto, "findLastIndex", array_find_last_index)
  let array_every = self.make_native("Array.prototype.every")
  self.set_function_length(array_every, 1.0)
  let _ = js_set_prop(array_proto, "every", array_every)
  let array_some = self.make_native("Array.prototype.some")
  self.set_function_length(array_some, 1.0)
  let _ = js_set_prop(array_proto, "some", array_some)
  let array_concat = self.make_native("Array.prototype.concat")
  self.set_function_length(array_concat, 1.0)
  let _ = js_set_prop(array_proto, "concat", array_concat)
  let array_slice = self.make_native("Array.prototype.slice")
  self.set_function_length(array_slice, 2.0)
  let _ = js_set_prop(array_proto, "slice", array_slice)
  let array_splice = self.make_native("Array.prototype.splice")
  self.set_function_length(array_splice, 2.0)
  let _ = js_set_prop(array_proto, "splice", array_splice)
  let array_sort = self.make_native("Array.prototype.sort")
  self.set_function_length(array_sort, 1.0)
  let _ = js_set_prop(array_proto, "sort", array_sort)
  let array_to_sorted = self.make_native("Array.prototype.toSorted")
  self.set_function_length(array_to_sorted, 1.0)
  let _ = js_set_prop(array_proto, "toSorted", array_to_sorted)
  let array_to_reversed = self.make_native("Array.prototype.toReversed")
  self.set_function_length(array_to_reversed, 0.0)
  let _ = js_set_prop(array_proto, "toReversed", array_to_reversed)
  let array_to_spliced = self.make_native("Array.prototype.toSpliced")
  self.set_function_length(array_to_spliced, 2.0)
  let _ = js_set_prop(array_proto, "toSpliced", array_to_spliced)
  let array_with = self.make_native("Array.prototype.with")
  self.set_function_length(array_with, 2.0)
  let _ = js_set_prop(array_proto, "with", array_with)
  let array_flat = self.make_native("Array.prototype.flat")
  self.set_function_length(array_flat, 0.0)
  let _ = js_set_prop(array_proto, "flat", array_flat)
  let array_flat_map = self.make_native("Array.prototype.flatMap")
  self.set_function_length(array_flat_map, 1.0)
  let _ = js_set_prop(array_proto, "flatMap", array_flat_map)
  let array_fill = self.make_native("Array.prototype.fill")
  self.set_function_length(array_fill, 1.0)
  let _ = js_set_prop(array_proto, "fill", array_fill)
  let array_copy_within = self.make_native("Array.prototype.copyWithin")
  self.set_function_length(array_copy_within, 2.0)
  let _ = js_set_prop(array_proto, "copyWithin", array_copy_within)
  let array_at = self.make_native("Array.prototype.at")
  self.set_function_length(array_at, 1.0)
  let _ = js_set_prop(array_proto, "at", array_at)
  let is_array_fn = self.make_native("Array.isArray")
  self.set_function_length(is_array_fn, 1.0)
  let _ = js_set_prop(array_ctor, "isArray", is_array_fn)
  self.global_env.define_var("Array", array_ctor)
  let _ = js_set_prop(global_obj, "Array", array_ctor)

  // Date
  let date_proto = self.new_object()
  let date_ctor = self.make_native("Date")
  self.set_function_length(date_ctor, 7.0)
  self.set_function_name(date_ctor, "Date")
  let _ = js_define_data_prop(date_ctor, "prototype", date_proto, true, false, true)
  let _ = js_set_prop(date_proto, "constructor", date_ctor)
  self.global_env.define_var("Date", date_ctor)
  let _ = js_set_prop(global_obj, "Date", date_ctor)

  // Errors (minimal)
  let syntax_ctor = self.make_native("SyntaxError")
  self.set_function_name(syntax_ctor, "SyntaxError")
  let _ = js_define_data_prop(syntax_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("SyntaxError", syntax_ctor)
  let _ = js_set_prop(global_obj, "SyntaxError", syntax_ctor)
  let type_ctor = self.make_native("TypeError")
  self.set_function_name(type_ctor, "TypeError")
  let _ = js_define_data_prop(type_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("TypeError", type_ctor)
  let _ = js_set_prop(global_obj, "TypeError", type_ctor)
  let ref_ctor = self.make_native("ReferenceError")
  self.set_function_name(ref_ctor, "ReferenceError")
  let _ = js_define_data_prop(ref_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("ReferenceError", ref_ctor)
  let _ = js_set_prop(global_obj, "ReferenceError", ref_ctor)
  let range_ctor = self.make_native("RangeError")
  self.set_function_name(range_ctor, "RangeError")
  let _ = js_define_data_prop(range_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("RangeError", range_ctor)
  let _ = js_set_prop(global_obj, "RangeError", range_ctor)
  let test262_ctor = self.make_native("Test262Error")
  self.set_function_name(test262_ctor, "Test262Error")
  let _ = js_define_data_prop(test262_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("Test262Error", test262_ctor)
  let _ = js_set_prop(global_obj, "Test262Error", test262_ctor)

  // assert (callable object)
  let assert_obj = self.new_object()
  let _ = js_set_prop(assert_obj, "$call", self.make_native("assert"))
  let _ = js_set_prop(
    assert_obj,
    "sameValue",
    self.make_native("assert.sameValue"),
  )
  let _ = js_set_prop(
    assert_obj,
    "notSameValue",
    self.make_native("assert.notSameValue"),
  )
  let _ = js_set_prop(
    assert_obj,
    "compareArray",
    self.make_native("assert.compareArray"),
  )
  let _ = js_set_prop(
    assert_obj,
    "throws",
    self.make_native("assert.throws"),
  )
  self.global_env.define_var("assert", assert_obj)
  let _ = js_set_prop(global_obj, "assert", assert_obj)

  // print
  let print_fn = self.make_native("print")
  self.global_env.define_var("print", print_fn)
  let _ = js_set_prop(global_obj, "print", print_fn)

  // eval
  let eval_fn = self.make_native("eval")
  self.set_function_length(eval_fn, 1.0)
  self.global_env.define_var("eval", eval_fn)
  let _ = js_set_prop(global_obj, "eval", eval_fn)

  // $DONOTEVALUATE
  let donotevaluate_fn = self.make_native("$DONOTEVALUATE")
  self.global_env.define_var("$DONOTEVALUATE", donotevaluate_fn)
  let _ = js_set_prop(global_obj, "$DONOTEVALUATE", donotevaluate_fn)

  // $ERROR / $DONE
  let error_fn = self.make_native("$ERROR")
  self.global_env.define_var("$ERROR", error_fn)
  let _ = js_set_prop(global_obj, "$ERROR", error_fn)
  let done_fn = self.make_native("$DONE")
  self.global_env.define_var("$DONE", done_fn)
  let _ = js_set_prop(global_obj, "$DONE", done_fn)

  // $262
  let t262 = self.new_object()
  let _ = js_set_prop(t262, "global", global_obj)
  let _ = js_set_prop(t262, "evalScript", self.make_native("$262.evalScript"))
  let _ = js_set_prop(t262, "createRealm", self.make_native("$262.createRealm"))
  self.global_env.define_var("$262", t262)
  let _ = js_set_prop(global_obj, "$262", t262)

  // globalThis / global
  self.global_env.define_var("globalThis", global_obj)
  self.global_env.define_var("global", global_obj)
  self.global_env.define_var("this", global_obj)
  self.global_env.define_var("undefined", Undefined)
  let _ = js_set_prop(global_obj, "undefined", Undefined)
  let nan = JSValue::Number(0.0 / 0.0)
  let inf = JSValue::Number(1.0 / 0.0)
  self.global_env.define_var("NaN", nan)
  self.global_env.define_var("Infinity", inf)
  let _ = js_set_prop(global_obj, "NaN", nan)
  let _ = js_set_prop(global_obj, "Infinity", inf)

  // Symbol
  let symbol_fn = self.make_native("Symbol")
  self.set_function_length(symbol_fn, 0.0)
  let _ = js_set_prop(symbol_fn, "hasInstance", String("@@hasInstance"))
  self.global_env.define_var("Symbol", symbol_fn)
  let _ = js_set_prop(global_obj, "Symbol", symbol_fn)

  // Reflect
  let reflect = self.new_object()
  let _ = js_set_prop(reflect, "construct", self.make_native("Reflect.construct"))
  self.global_env.define_var("Reflect", reflect)
  let _ = js_set_prop(global_obj, "Reflect", reflect)
}

///|
// / expression
pub fn JSInterpreter::eval_expr(
  self : JSInterpreter,
  expr : @parser.TsExpr,
  env : JSEnv,
) -> JSValue {
  self.tick()
  match expr {
    @parser.TsExpr::IntLit(n) => Number(n.to_double())
    @parser.TsExpr::NumberLit(n) => Number(n)
    @parser.TsExpr::BoolLit(b) => Bool(b)
    @parser.TsExpr::StringLit(s) => String(s)
    @parser.TsExpr::NullLit => Null
    @parser.TsExpr::Yield(_) => Undefined
    @parser.TsExpr::Var(name) =>
      if name == "super" && env.has("__super_proto") {
        env.get("__super_proto")
      } else if env.has(name) {
        env.get(name)
      } else {
        let global_obj = self.global_env.get("globalThis")
        if js_has_prop(global_obj, name) {
          js_get_prop(global_obj, name)
        } else {
          let _ = self.set_error_kind("ReferenceError", name + " is not defined")
          Undefined
        }
      }
    @parser.TsExpr::Seq(left, right) => {
      let _ = self.eval_expr(left, env)
      self.eval_expr(right, env)
    }
    @parser.TsExpr::BinOp(op, left, right) => {
      let lval = self.eval_expr(left, env)
      let rval = self.eval_expr(right, env)
      match op {
        @parser.TsBinOp::Add => {
          let lprim = self.to_primitive_for_add(lval)
          let rprim = self.to_primitive_for_add(rval)
          match (lprim, rprim) {
            (String(_), _) | (_, String(_)) =>
              String(lprim.to_js_string() + rprim.to_js_string())
            _ => js_add(lprim, rprim)
          }
        }
        @parser.TsBinOp::Sub => js_sub(lval, rval)
        @parser.TsBinOp::Mul => js_mul(lval, rval)
        @parser.TsBinOp::Div => js_div(lval, rval)
        @parser.TsBinOp::Mod => js_mod(lval, rval)
        @parser.TsBinOp::Pow => Number(@math.pow(lval.to_number(), rval.to_number()))
        @parser.TsBinOp::BitAnd => {
          let li = lval.to_number().to_int()
          let ri = rval.to_number().to_int()
          Number((li & ri).to_double())
        }
        @parser.TsBinOp::BitOr => {
          let li = lval.to_number().to_int()
          let ri = rval.to_number().to_int()
          Number((li | ri).to_double())
        }
        @parser.TsBinOp::BitXor => {
          let li = lval.to_number().to_int()
          let ri = rval.to_number().to_int()
          Number((li ^ ri).to_double())
        }
        @parser.TsBinOp::Shl => {
          let li = lval.to_number().to_int()
          let ri = rval.to_number().to_int()
          let shift = ri & 31
          Number((li << shift).to_double())
        }
        @parser.TsBinOp::Shr => {
          let li = lval.to_number().to_int()
          let ri = rval.to_number().to_int()
          let shift = ri & 31
          Number((li >> shift).to_double())
        }
        @parser.TsBinOp::UShr => {
          let li = lval.to_number()
          let ri = rval.to_number().to_int()
          let shift = ri & 31
          let u = if li < 0.0 { li + 4294967296.0 } else { li }
          let denom = @math.pow(2.0, shift.to_double())
          Number(@math.floor(u / denom))
        }
        @parser.TsBinOp::BinLt => js_lt(lval, rval)
        @parser.TsBinOp::BinLe => js_le(lval, rval)
        @parser.TsBinOp::BinGt => js_gt(lval, rval)
        @parser.TsBinOp::BinGe => js_ge(lval, rval)
        @parser.TsBinOp::BinEq => js_strict_eq(lval, rval) // === (strict equality)
        @parser.TsBinOp::BinNe => js_strict_ne(lval, rval) // !== (strict inequality)
        @parser.TsBinOp::AbstractEq => js_eq(lval, rval) // == (abstract equality)
        @parser.TsBinOp::AbstractNe => js_ne(lval, rval) // != (abstract inequality)
        @parser.TsBinOp::Instanceof => Bool(self.instanceof(lval, rval))
        @parser.TsBinOp::In => Bool(js_has_prop(rval, lval.to_js_string()))
        @parser.TsBinOp::And =>
          // : lvalfalsylval, rval
          if lval.to_boolean() {
            rval
          } else {
            lval
          }
        @parser.TsBinOp::Or =>
          // : lvaltruthylval, rval
          if lval.to_boolean() {
            lval
          } else {
            rval
          }
      }
    }
    @parser.TsExpr::UnaryOp(op, operand) =>
      match op {
        @parser.TsUnaryOp::PreInc =>
          // ++x:
          match operand {
            @parser.TsExpr::Var(name) => {
              let old_val = env.get(name)
              let new_val = js_add(old_val, Number(1.0))
              let _ = env.set(name, new_val)
              new_val
            }
            _ => {
              let val = self.eval_expr(operand, env)
              js_add(val, Number(1.0))
            }
          }
        @parser.TsUnaryOp::PreDec =>
          // --x:
          match operand {
            @parser.TsExpr::Var(name) => {
              let old_val = env.get(name)
              let new_val = js_sub(old_val, Number(1.0))
              let _ = env.set(name, new_val)
              new_val
            }
            _ => {
              let val = self.eval_expr(operand, env)
              js_sub(val, Number(1.0))
            }
          }
        @parser.TsUnaryOp::PostInc =>
          // x++:
          match operand {
            @parser.TsExpr::Var(name) => {
              let old_val = env.get(name)
              let new_val = js_add(old_val, Number(1.0))
              let _ = env.set(name, new_val)
              old_val
            }
            _ => {
              let val = self.eval_expr(operand, env)
              val
            }
          }
        @parser.TsUnaryOp::PostDec =>
          // x--:
          match operand {
            @parser.TsExpr::Var(name) => {
              let old_val = env.get(name)
              let new_val = js_sub(old_val, Number(1.0))
              let _ = env.set(name, new_val)
              old_val
            }
            _ => {
              let val = self.eval_expr(operand, env)
              val
            }
          }
        @parser.TsUnaryOp::Neg => js_neg(self.eval_expr(operand, env))
        @parser.TsUnaryOp::Not => js_not(self.eval_expr(operand, env))
        @parser.TsUnaryOp::Plus => js_pos(self.eval_expr(operand, env))
        @parser.TsUnaryOp::Typeof =>
          match operand {
            @parser.TsExpr::Var(name) =>
              if env.has(name) || js_has_prop(self.global_env.get("globalThis"), name) {
                js_typeof(self.eval_expr(operand, env))
              } else {
                String("undefined")
              }
            _ => js_typeof(self.eval_expr(operand, env))
          }
        @parser.TsUnaryOp::Delete =>
          match operand {
            @parser.TsExpr::PropAccess(obj_expr, prop) => {
              let obj = self.eval_expr(obj_expr, env)
              Bool(js_delete_prop(obj, prop))
            }
            @parser.TsExpr::IndexAccess(obj_expr, idx_expr) => {
              let obj = self.eval_expr(obj_expr, env)
              let idx = self.eval_expr(idx_expr, env)
              let key = idx.to_js_string()
              Bool(js_delete_prop(obj, key))
            }
            @parser.TsExpr::Var(name) =>
              if env.has(name) {
                Bool(false)
              } else {
                let global_obj = self.global_env.get("globalThis")
                let _ = js_delete_prop(global_obj, name)
                Bool(true)
              }
            _ => {
              let _ = self.eval_expr(operand, env)
              Bool(true)
            }
          }
        @parser.TsUnaryOp::Void => {
          let _ = self.eval_expr(operand, env)
          Undefined
        }
    }
    @parser.TsExpr::Call(name, args) => {
      if name == "eval" {
        let src = if args.length() > 0 {
          self.eval_expr(args[0], env).to_js_string()
        } else {
          ""
        }
        return self.direct_eval(src, env)
      }
      if name == "super" && env.has("__super_ctor") {
        let super_ctor = env.get("__super_ctor")
        let mut already_called = false
        match env.get("__super_called") {
          Bool(true) => already_called = true
          _ => ()
        }
        let _ = env.set("__super_called", Bool(true))
        let arg_values : Array[JSValue] = []
        for arg in args {
          arg_values.push(self.eval_expr(arg, env))
        }
        let _ = self.call_function(super_ctor, env.get("this"), arg_values)
        if already_called {
          let _ = self.set_error_kind("ReferenceError", "super already called")
          return Undefined
        }
        return Undefined
      }
      // functionget
      let func = env.get(name)
      let arg_values : Array[JSValue] = []
      for arg in args {
        arg_values.push(self.eval_expr(arg, env))
      }
      self.call_function(func, Undefined, arg_values)
    }
    @parser.TsExpr::CallExpr(callee, args) => {
      let arg_values : Array[JSValue] = []
      for arg in args {
        arg_values.push(self.eval_expr(arg, env))
      }
      match callee {
        @parser.TsExpr::IndexAccess(obj_expr, idx_expr) => {
          let obj = self.eval_expr(obj_expr, env)
          let idx = self.eval_expr(idx_expr, env)
          let key = idx.to_js_string()
          let func = self.get_prop_value(obj, key)
          self.call_function(func, obj, arg_values)
        }
        @parser.TsExpr::PropAccess(obj_expr, prop) => {
          let obj = self.eval_expr(obj_expr, env)
          let func = self.get_prop_value(obj, prop)
          self.call_function(func, obj, arg_values)
        }
        _ => {
          let func = self.eval_expr(callee, env)
          self.call_function(func, Undefined, arg_values)
        }
      }
    }
    @parser.TsExpr::MethodCall(obj_expr, method_name, args) => {
      match obj_expr {
        @parser.TsExpr::Var(name) if name == "super" && env.has("__super_proto") => {
          let super_proto = env.get("__super_proto")
          let super_this = if env.has("__super_this") { env.get("__super_this") } else { env.get("this") }
          let arg_values : Array[JSValue] = []
          for arg in args {
            arg_values.push(self.eval_expr(arg, env))
          }
          let func = self.get_prop_value(super_proto, method_name)
          return self.call_function(func, super_this, arg_values)
        }
        _ => ()
      }
      let obj = self.eval_expr(obj_expr, env)
      let arg_values : Array[JSValue] = []
      for arg in args {
        arg_values.push(self.eval_expr(arg, env))
      }
      self.call_method(obj, method_name, arg_values)
    }
    @parser.TsExpr::ArrayLit(elements) => {
      let items : Array[JSValue] = []
      for elem in elements {
        items.push(self.eval_expr(elem, env))
      }
      js_array_from(items)
    }
    @parser.TsExpr::ObjectLit(fields) => {
      let props : Array[JSProp] = []
      for field in fields {
        let (key, val_expr) = field
        props.push({
          key,
          value: self.eval_expr(val_expr, env),
          writable: true,
          enumerable: true,
          configurable: true,
          get: None,
          set: None,
        })
      }
      js_object_with_props(props, Some(self.object_proto))
    }
    @parser.TsExpr::IndexAccess(obj_expr, idx_expr) => {
      let obj = self.eval_expr(obj_expr, env)
      let idx = self.eval_expr(idx_expr, env)
      let key = idx.to_js_string()
      self.get_prop_value(obj, key)
    }
    @parser.TsExpr::PropAccess(obj_expr, prop) => {
      match obj_expr {
        @parser.TsExpr::Var(name) if name == "super" && env.has("__super_proto") => {
          let super_proto = env.get("__super_proto")
          self.get_prop_value(super_proto, prop)
        }
        _ => {
          let obj = self.eval_expr(obj_expr, env)
          self.get_prop_value(obj, prop)
        }
      }
    }
    @parser.TsExpr::CompoundAssignExpr(left, op, right) => {
      match left {
        @parser.TsExpr::Var(name) => {
          let current = env.get(name)
          let val = self.eval_expr(right, env)
          let new_val = apply_compound_op(op, current, val)
          if not(env.set(name, new_val)) {
            self.global_env.define_var(name, new_val)
            let global_obj = self.global_env.get("globalThis")
            let _ = js_set_prop(global_obj, name, new_val)
          }
          new_val
        }
        @parser.TsExpr::PropAccess(obj_expr, prop) => {
          let obj = self.eval_expr(obj_expr, env)
          let current = self.get_prop_value(obj, prop)
          let val = self.eval_expr(right, env)
          let new_val = apply_compound_op(op, current, val)
          let _ = js_set_prop(obj, prop, new_val)
          new_val
        }
        @parser.TsExpr::IndexAccess(obj_expr, idx_expr) => {
          let obj = self.eval_expr(obj_expr, env)
          let idx = self.eval_expr(idx_expr, env)
          let key = idx.to_js_string()
          let current = self.get_prop_value(obj, key)
          let val = self.eval_expr(right, env)
          let new_val = apply_compound_op(op, current, val)
          match obj {
            Array(_) | Object(_) => {
              let _ = js_set_prop(obj, key, new_val)
            }
            _ => ()
          }
          new_val
        }
        _ => self.eval_expr(right, env)
      }
    }
    @parser.TsExpr::AssignExpr(name, val_expr) => {
      let val = self.eval_expr(val_expr, env)
      if not(env.set(name, val)) {
        // variabledefine
        self.global_env.define_var(name, val)
        let global_obj = self.global_env.get("globalThis")
        let _ = js_set_prop(global_obj, name, val)
      }
      val
    }
    @parser.TsExpr::PropAssignExpr(obj_expr, prop, val_expr) => {
      let obj = self.eval_expr(obj_expr, env)
      let val = self.eval_expr(val_expr, env)
      let _ = js_set_prop(obj, prop, val)
      val
    }
    @parser.TsExpr::IndexAssignExpr(obj_expr, idx_expr, val_expr) => {
      let obj = self.eval_expr(obj_expr, env)
      let idx = self.eval_expr(idx_expr, env)
      let val = self.eval_expr(val_expr, env)
      match obj {
        Array(_) | Object(_) => {
          let key = idx.to_js_string()
          let _ = js_set_prop(obj, key, val)
        }
        _ => ()
      }
      val
    }
    @parser.TsExpr::Cond(cond, then_expr, else_expr) => {
      let cond_val = self.eval_expr(cond, env)
      if cond_val.to_boolean() {
        self.eval_expr(then_expr, env)
      } else {
        self.eval_expr(else_expr, env)
      }
    }
    @parser.TsExpr::New(class_name, args) => {
      let arg_values : Array[JSValue] = []
      for arg in args {
        arg_values.push(self.eval_expr(arg, env))
      }
      self.new_instance(class_name, arg_values, env)
    }
    @parser.TsExpr::NewExpr(callee_expr, args) => {
      let ctor = self.eval_expr(callee_expr, env)
      let arg_values : Array[JSValue] = []
      for arg in args {
        arg_values.push(self.eval_expr(arg, env))
      }
      match ctor {
        Function(_) => self.construct_with(ctor, ctor, arg_values)
        _ => self.new_object()
      }
    }
    @parser.TsExpr::ArrowFunc(params, body) => {
      let param_names : Array[String] = []
      for param in params {
        param_names.push(param.name)
      }
      let is_strict = match body {
        @parser.TsArrowBody::ArrowExpr(_) => env.has("__strict__")
        @parser.TsArrowBody::ArrowBlock(block) =>
          self.is_strict_body(block, env.has("__strict__"))
      }
      let closure = JSValue::Function({
        id: fresh_function_id(),
        params: param_names,
        body: match body {
          @parser.TsArrowBody::ArrowExpr(expr) =>
            Ast({
              name: "<arrow>",
              params,
              return_type: @parser.TsType::Any,
              body: { stmts: [@parser.TsStmt::Return(Some(expr))] },
              is_generator: false,
            })
          @parser.TsArrowBody::ArrowBlock(block) =>
            Ast({
              name: "<arrow>",
              params,
              return_type: @parser.TsType::Any,
              body: block,
              is_generator: false,
            })
        },
        env,
        is_arrow: true,
        is_strict,
        is_generator: false,
        props: [],
        object_proto: Some(self.function_proto),
      })
      self.set_function_length(closure, param_names.length().to_double())
      closure
    }
    @parser.TsExpr::FuncExpr(func) => {
      let param_names : Array[String] = []
      for param in func.params {
        param_names.push(param.name)
      }
      let closure = JSValue::Function({
        id: fresh_function_id(),
        params: param_names,
        body: Ast(func),
        env,
        is_arrow: false,
        is_strict: self.is_strict_body(func.body, env.has("__strict__")),
        is_generator: func.is_generator,
        props: [],
        object_proto: Some(self.function_proto),
      })
      self.set_function_length(closure, param_names.length().to_double())
      if func.name != "<anon>" {
        self.set_function_name(closure, func.name)
      }
      let proto = self.new_object()
      let _ = js_set_prop(proto, "constructor", closure)
      let _ = js_define_data_prop(closure, "prototype", proto, true, false, true)
      closure
    }
  }
}

///|
// / direct eval: expression/statementrun
fn JSInterpreter::direct_eval(self : JSInterpreter, source : String, env : JSEnv) -> JSValue {
  let parsed_expr = try { @parser.parse_expr_from_source(source) } catch { _ => None }
  match parsed_expr {
    Some(expr) => self.eval_expr(expr, env)
    None => {
      let block = try { @parser.parse_block_from_source(source) } catch {
        @parser.ParseError::ParseError(msg) => {
          let _ = self.set_error_kind("SyntaxError", msg)
          return JSValue::Undefined
        }
      }
      self.exec_eval_block(block, env)
    }
  }
}

///|
fn JSInterpreter::exec_eval_block(
  self : JSInterpreter,
  block : @parser.TsBlock,
  env : JSEnv,
) -> JSValue {
  let mut last = JSValue::Undefined
  for stmt in block.stmts {
    match stmt {
      @parser.TsStmt::Expr(expr) => {
        last = self.eval_expr(expr, env)
      }
      _ =>
        match self.exec_stmt(stmt, env) {
          Some(val) => return val
          None => ()
        }
    }
  }
  last
}

///|
fn apply_compound_op(
  op : @parser.TsCompoundOp,
  current : JSValue,
  val : JSValue,
) -> JSValue {
  match op {
    @parser.TsCompoundOp::AddAssign => js_add(current, val)
    @parser.TsCompoundOp::SubAssign => js_sub(current, val)
    @parser.TsCompoundOp::MulAssign => js_mul(current, val)
    @parser.TsCompoundOp::DivAssign => js_div(current, val)
    @parser.TsCompoundOp::ModAssign => js_mod(current, val)
    @parser.TsCompoundOp::BitAndAssign => {
      let li = current.to_number().to_int()
      let ri = val.to_number().to_int()
      Number((li & ri).to_double())
    }
    @parser.TsCompoundOp::BitOrAssign => {
      let li = current.to_number().to_int()
      let ri = val.to_number().to_int()
      Number((li | ri).to_double())
    }
    @parser.TsCompoundOp::BitXorAssign => {
      let li = current.to_number().to_int()
      let ri = val.to_number().to_int()
      Number((li ^ ri).to_double())
    }
    @parser.TsCompoundOp::ShlAssign => {
      let li = current.to_number().to_int()
      let ri = val.to_number().to_int()
      let shift = ri & 31
      Number((li << shift).to_double())
    }
    @parser.TsCompoundOp::ShrAssign => {
      let li = current.to_number().to_int()
      let ri = val.to_number().to_int()
      let shift = ri & 31
      Number((li >> shift).to_double())
    }
    @parser.TsCompoundOp::UShrAssign => {
      let li = current.to_number()
      let ri = val.to_number().to_int()
      let shift = ri & 31
      let u = if li < 0.0 { li + 4294967296.0 } else { li }
      let denom = @math.pow(2.0, shift.to_double())
      Number(@math.floor(u / denom))
    }
    @parser.TsCompoundOp::PowAssign => Number(@math.pow(current.to_number(), val.to_number()))
  }
}

///|
// / statementrun(return valueReturnSome)
pub fn JSInterpreter::exec_stmt(
  self : JSInterpreter,
  stmt : @parser.TsStmt,
  env : JSEnv,
) -> JSValue? {
  self.tick()
  match self.peek_error() {
    Some(err) => return Some(err)
    None => ()
  }
  match stmt {
    @parser.TsStmt::Let(name, _, init) | @parser.TsStmt::Const(name, _, init) => {
      let val = self.eval_expr(init, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      self.maybe_set_function_name(val, name)
      env.define_var(name, val)
      match env.parent {
        None => {
          let global_obj = self.global_env.get("globalThis")
          let _ = js_set_prop(global_obj, name, val)
        }
        Some(_) => ()
      }
      None
    }
    @parser.TsStmt::Expr(expr) => {
      let _ = self.eval_expr(expr, env)
      match self.peek_error() {
        Some(err) => Some(err)
        None => None
      }
    }
    Empty => None
    @parser.TsStmt::Block(block) => self.exec_block(block, env)
    @parser.TsStmt::Assign(name, val_expr) => {
      let val = self.eval_expr(val_expr, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      self.maybe_set_function_name(val, name)
      if not(env.set(name, val)) {
        self.global_env.define_var(name, val)
        let global_obj = self.global_env.get("globalThis")
        let _ = js_set_prop(global_obj, name, val)
      }
      None
    }
    @parser.TsStmt::Return(Some(expr)) => {
      let val = self.eval_expr(expr, env)
      match self.peek_error() {
        Some(err) => Some(err)
        None => Some(val)
      }
    }
    @parser.TsStmt::Return(None) => Some(Undefined)
    @parser.TsStmt::Throw(expr) => {
      let val = self.eval_expr(expr, env)
      self.last_error = Some(val)
      Some(val)
    }
    @parser.TsStmt::Try(try_block, catch_name, catch_block, finally_block) => {
      let mut result = self.exec_block(try_block, env)
      let mut pending_error : JSValue? = None
      match self.peek_error() {
        Some(_) =>
          match self.take_error() {
            Some(err) => {
              match catch_block {
                Some(block) => {
                  let name = match catch_name {
                    Some(n) => n
                    None => "error"
                  }
                  let catch_env = js_new_env(Some(env))
                  catch_env.define_var(name, err)
                  result = self.exec_block(block, catch_env)
                }
                None => pending_error = Some(err)
              }
            }
            None => ()
          }
        None => ()
      }
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      match finally_block {
        Some(block) => {
          let final_result = self.exec_block(block, env)
          match self.peek_error() {
            Some(err) => return Some(err)
            None => ()
          }
          match final_result {
            Some(val) => return Some(val)
            None => ()
          }
        }
        None => ()
      }
      match pending_error {
        Some(err) => {
          self.last_error = Some(err)
          Some(err)
        }
        None => result
      }
    }
    @parser.TsStmt::If(cond, then_block, else_block) => {
      let cond_val = self.eval_expr(cond, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      if cond_val.to_boolean() {
        self.exec_block(then_block, env)
      } else {
        match else_block {
          Some(block) => self.exec_block(block, env)
          None => None
        }
      }
    }
    @parser.TsStmt::While(cond, body) => {
      while self.eval_expr(cond, env).to_boolean() {
        match self.peek_error() {
          Some(err) => return Some(err)
          None => ()
        }
        match self.exec_block(body, env) {
          Some(BreakSignal) => break
          Some(ContinueSignal) => continue
          Some(val) => return Some(val)
          None => ()
        }
      }
      None
    }
    @parser.TsStmt::For(init, cond, update, body) => {
      // initialize
      match init {
        Some(init_stmt) => {
          match self.exec_stmt(init_stmt, env) {
            Some(val) => return Some(val)
            None => ()
          }

        }
        None => ()
      }
      // loop
      while (match cond {
              Some(c) => self.eval_expr(c, env).to_boolean()
              None => true
            }) {
        match self.peek_error() {
          Some(err) => return Some(err)
          None => ()
        }
        match self.exec_block(body, env) {
          Some(BreakSignal) => break
          Some(ContinueSignal) => {
            // updaterun
            match update {
              Some(u) => {
                match self.exec_stmt(u, env) {
                  Some(val) => return Some(val)
                  None => ()
                }

              }
              None => ()
            }
            continue
          }
          Some(val) => return Some(val)
          None => ()
        }
        // update
        match update {
          Some(u) => {
            match self.exec_stmt(u, env) {
              Some(val) => return Some(val)
              None => ()
            }

          }
          None => ()
        }
      }
      None
    }
    Break => Some(BreakSignal)
    Continue => Some(ContinueSignal)
    @parser.TsStmt::CompoundAssign(name, op, val_expr) => {
      let current = env.get(name)
      let val = self.eval_expr(val_expr, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      let new_val = apply_compound_op(op, current, val)
      let _ = env.set(name, new_val)
      None
    }
    @parser.TsStmt::IndexAssign(arr_expr, idx_expr, val_expr) => {
      let arr = self.eval_expr(arr_expr, env)
      let idx = self.eval_expr(idx_expr, env)
      let val = self.eval_expr(val_expr, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      match arr {
        Array(_) | Object(_) => {
          let key = idx.to_js_string()
          let _ = js_set_prop(arr, key, val)
        }
        _ => ()
      }
      None
    }
    @parser.TsStmt::PropAssign(obj_expr, prop, val_expr) => {
      let obj = self.eval_expr(obj_expr, env)
      let val = self.eval_expr(val_expr, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      let _ = js_set_prop(obj, prop, val)
      None
    }
    @parser.TsStmt::ForOf(var_name, _, iterable, body) => {
      let iter_val = self.eval_expr(iterable, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      match iter_val {
        Array(arr) => {
          let mut idx = 0
          while idx < arr.items.length() {
            let item = arr.items[idx]
            env.define_var(var_name, item)
            match self.exec_block(body, env) {
              Some(BreakSignal) => break
              Some(ContinueSignal) => {
                idx += 1
                continue
              }
              Some(val) => return Some(val)
              None => ()
            }
            idx += 1
          }
        }
        String(s) => {
          // string
          let mut idx = 0
          while idx < s.length() {
            let char_str = try { s[idx:idx + 1].to_string() } catch { _ => "" }
            env.define_var(var_name, String(char_str))
            match self.exec_block(body, env) {
              Some(BreakSignal) => break
              Some(ContinueSignal) => {
                idx += 1
                continue
              }
              Some(val) => return Some(val)
              None => ()
            }
            idx += 1
          }
        }
        _ => ()
      }
      None
    }
  }
}

///|
// / blockrun
pub fn JSInterpreter::exec_block(
  self : JSInterpreter,
  block : @parser.TsBlock,
  env : JSEnv,
) -> JSValue? {
  for stmt in block.stmts {
    match self.exec_stmt(stmt, env) {
      Some(val) => return Some(val)
      None => ()
    }
  }
  None
}

///|
// / get
fn JSInterpreter::get_proto(_self : JSInterpreter, value : JSValue) -> JSValue? {
  match value {
    Object(map) => map.prototype
    Function(closure) => closure.object_proto
    Array(arr) => arr.prototype
    _ => None
  }
}

///|
// / propertyget()
fn JSInterpreter::get_prop_value(self : JSInterpreter, obj : JSValue, key : String) -> JSValue {
  self.get_prop_value_with_receiver(obj, obj, key)
}

///|
// / propertyget
fn JSInterpreter::get_prop_value_with_receiver(
  self : JSInterpreter,
  target : JSValue,
  receiver : JSValue,
  key : String,
) -> JSValue {
  match target {
    Function(closure) => {
      for prop in closure.props {
        if prop.key == key {
          return self.eval_prop_value(receiver, prop)
        }
      }
      match closure.object_proto {
        Some(proto) => self.get_prop_value_with_receiver(proto, receiver, key)
        None => Undefined
      }
    }
    Object(map) => {
      for prop in map.props {
        if prop.key == key {
          return self.eval_prop_value(receiver, prop)
        }
      }
      match map.prototype {
        Some(proto) => self.get_prop_value_with_receiver(proto, receiver, key)
        None => Undefined
      }
    }
    Array(arr) =>
      if key == "length" {
        Number(arr.length.to_double())
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < arr.items.length() {
          arr.items[idx]
        } else {
          for prop in arr.props {
            if prop.key == key {
              return self.eval_prop_value(receiver, prop)
            }
          }
          if key == "constructor" {
            self.global_env.get("Array")
          } else {
            match arr.prototype {
              Some(proto) => self.get_prop_value_with_receiver(proto, receiver, key)
              None => Undefined
            }
          }
        }
      }
    String(s) =>
      if key == "length" {
        Number(s.length().to_double())
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < s.length() {
          String(try { s[idx:idx + 1].to_string() } catch { _ => "" })
        } else {
          Undefined
        }
      }
    _ => Undefined
  }
}

///|
// / property
fn JSInterpreter::eval_prop_value(
  self : JSInterpreter,
  receiver : JSValue,
  prop : JSProp,
) -> JSValue {
  match prop.get {
    Some(getter) => self.call_function(getter, receiver, [])
    None => prop.value
  }
}

///|
// / own property check
fn JSInterpreter::has_own_prop(_self : JSInterpreter, obj : JSValue, key : String) -> Bool {
  match obj {
    Function(closure) => {
      for prop in closure.props {
        if prop.key == key {
          return true
        }
      }
      false
    }
    Object(map) => {
      for prop in map.props {
        if prop.key == key {
          return true
        }
      }
      false
    }
    Array(arr) =>
      if key == "length" {
        true
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < arr.items.length() {
          true
        } else {
          let mut found = false
          for prop in arr.props {
            if prop.key == key {
              found = true
              break
            }
          }
          found
        }
      }
    String(s) =>
      if key == "length" {
        true
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        idx >= 0 && idx < s.length()
      }
    _ => false
  }
}

///|
// / enumerable check
fn JSInterpreter::is_enumerable(_self : JSInterpreter, obj : JSValue, key : String) -> Bool {
  match obj {
    Function(closure) => {
      for prop in closure.props {
        if prop.key == key {
          return prop.enumerable
        }
      }
      false
    }
    Object(map) => {
      for prop in map.props {
        if prop.key == key {
          return prop.enumerable
        }
      }
      false
    }
    Array(arr) =>
      if key == "length" {
        false
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < arr.items.length() {
          true
        } else {
          let mut found = false
          for prop in arr.props {
            if prop.key == key {
              found = prop.enumerable
              break
            }
          }
          found
        }
      }
    String(s) =>
      if key == "length" {
        false
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        idx >= 0 && idx < s.length()
      }
    _ => false
  }
}

///|
// / Instanceof check
fn JSInterpreter::ordinary_has_instance(
  self : JSInterpreter,
  ctor : JSValue,
  obj : JSValue,
) -> Bool {
  let target = match ctor {
    Function(closure) =>
      match closure.body {
        Bound(bound_target, _, _) => bound_target
        _ => ctor
      }
    _ => ctor
  }
  if not(self.is_callable(target)) {
    return false
  }
  match obj {
    Object(_) | Array(_) | Function(_) => ()
    _ => return false
  }
  let proto = js_get_prop(target, "prototype")
  match proto {
    Object(_) | Function(_) => ()
    _ => return false
  }
  let mut cur = self.get_proto(obj)
  while cur is Some(p) {
    match js_strict_eq(p, proto) {
      Bool(true) => return true
      _ => ()
    }
    cur = self.get_proto(p)
  }
  false
}

///|
// / new-target generate
fn JSInterpreter::construct_with(
  self : JSInterpreter,
  ctor : JSValue,
  new_target : JSValue,
  args : Array[JSValue],
) -> JSValue {
  if not(self.is_constructor(ctor)) || not(self.is_constructor(new_target)) {
    return self.set_error_kind("TypeError", "not a constructor")
  }
  match ctor {
    Function(closure) =>
      match closure.body {
        Bound(bound_target, _bound_this, bound_args) => {
          let merged : Array[JSValue] = []
          for item in bound_args {
            merged.push(item)
          }
          for item in args {
            merged.push(item)
          }
          let next_new_target = match js_strict_eq(new_target, ctor) {
            Bool(true) => bound_target
            _ => new_target
          }
          return self.construct_with(bound_target, next_new_target, merged)
        }
        _ => ()
      }
    _ => ()
  }
  let proto = js_get_prop(new_target, "prototype")
  let instance = match proto {
    Object(_) | Function(_) => js_new_object_with_proto(Some(proto))
    _ => self.new_object()
  }
  let result = self.call_function(ctor, instance, args, new_target=new_target)
  match result {
    Object(_) | Array(_) | Function(_) => result
    _ => instance
  }
}

///|
// / object
fn JSInterpreter::wrap_primitive(self : JSInterpreter, env : JSEnv, value : JSValue) -> JSValue {
  match value {
    Bool(_) => {
      let ctor = env.get("Boolean")
      let proto = js_get_prop(ctor, "prototype")
      let obj = match proto {
        Object(_) | Function(_) => js_new_object_with_proto(Some(proto))
        _ => self.new_object()
      }
      let _ = js_set_prop(obj, "value", value)
      obj
    }
    Number(_) => {
      let ctor = env.get("Number")
      let proto = js_get_prop(ctor, "prototype")
      let obj = match proto {
        Object(_) | Function(_) => js_new_object_with_proto(Some(proto))
        _ => self.new_object()
      }
      let _ = js_set_prop(obj, "value", value)
      obj
    }
    String(_) => {
      let ctor = env.get("String")
      let proto = js_get_prop(ctor, "prototype")
      let obj = match proto {
        Object(_) | Function(_) => js_new_object_with_proto(Some(proto))
        _ => self.new_object()
      }
      let _ = js_set_prop(obj, "value", value)
      obj
    }
    _ => value
  }
}

///|
// / ToPrimitive(+) (Object value / toString )
fn JSInterpreter::to_primitive_for_add(
  self : JSInterpreter,
  value : JSValue,
) -> JSValue {
  match value {
    Object(_) | Array(_) | Function(_) => {
      String(self.to_string_value(value))
    }
    _ => value
  }
}

///|
// / JS ToString (Object toString )
fn JSInterpreter::to_string_value(self : JSInterpreter, value : JSValue) -> String {
  match value {
    Object(_) | Array(_) | Function(_) => {
      let to_str = js_get_prop(value, "toString")
      if self.is_callable(to_str) {
        let res = self.call_function(to_str, value, [])
        match res {
          Object(_) | Array(_) | Function(_) => ()
          _ => return res.to_js_string()
        }
      }
      let value_of = js_get_prop(value, "valueOf")
      if self.is_callable(value_of) {
        let res = self.call_function(value_of, value, [])
        match res {
          Object(_) | Array(_) | Function(_) => ()
          _ => return res.to_js_string()
        }
      }
      value.to_js_string()
    }
    _ => value.to_js_string()
  }
}

///|
// / variablesimple
fn JSInterpreter::hoist_stmt(self : JSInterpreter, stmt : @parser.TsStmt, env : JSEnv) -> Unit {
  match stmt {
    @parser.TsStmt::Let(name, _, _) | @parser.TsStmt::Const(name, _, _) =>
      if not(env.has(name)) {
        env.define_var(name, Undefined)
        match env.parent {
          None => {
            let global_obj = self.global_env.get("globalThis")
            let _ = js_set_prop(global_obj, name, Undefined)
          }
          Some(_) => ()
        }
      }
    @parser.TsStmt::Block(block) => self.hoist_block(block, env)
    @parser.TsStmt::If(_, then_block, else_block) => {
      self.hoist_block(then_block, env)
      match else_block {
        Some(block) => self.hoist_block(block, env)
        None => ()
      }
    }
    @parser.TsStmt::While(_, body) => self.hoist_block(body, env)
    @parser.TsStmt::For(init, _, _, body) => {
      match init {
        Some(s) => self.hoist_stmt(s, env)
        None => ()
      }
      self.hoist_block(body, env)
    }
    @parser.TsStmt::ForOf(name, _, _, body) => {
      if not(env.has(name)) {
        env.define_var(name, Undefined)
        match env.parent {
          None => {
            let global_obj = self.global_env.get("globalThis")
            let _ = js_set_prop(global_obj, name, Undefined)
          }
          Some(_) => ()
        }
      }
      self.hoist_block(body, env)
    }
    @parser.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      self.hoist_block(try_block, env)
      match catch_block {
        Some(block) => self.hoist_block(block, env)
        None => ()
      }
      match finally_block {
        Some(block) => self.hoist_block(block, env)
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn JSInterpreter::hoist_block(self : JSInterpreter, block : @parser.TsBlock, env : JSEnv) -> Unit {
  for stmt in block.stmts {
    self.hoist_stmt(stmt, env)
  }
}

///|
// / check
fn JSInterpreter::is_callable(_self : JSInterpreter, value : JSValue) -> Bool {
  match value {
    Function(_) => true
    Object(map) =>
      match js_get_prop(Object(map), "$call") {
        Function(_) => true
        _ => false
      }
    _ => false
  }
}

///|
// / constructor check
fn JSInterpreter::is_constructor(self : JSInterpreter, value : JSValue) -> Bool {
  match value {
    Function(closure) =>
      match closure.body {
        Bound(target, _, _) => self.is_constructor(target)
        _ => self.has_own_prop(value, "prototype")
      }
    _ => false
  }
}

///|
fn JSInterpreter::make_generator(
  self : JSInterpreter,
  closure : JSClosure,
  this_arg : JSValue,
  args : Array[JSValue],
  new_target : JSValue,
) -> JSValue {
  let call_env = js_new_env(Some(closure.env))
  if closure.is_strict {
    call_env.define_var("__strict__", Bool(true))
  }
  let bound_this = if closure.is_strict {
    this_arg
  } else {
    match this_arg {
      Undefined | Null => closure.env.get("globalThis")
      Bool(_) | Number(_) | String(_) => self.wrap_primitive(closure.env, this_arg)
      _ => this_arg
    }
  }
  call_env.define_var("this", bound_this)
  let new_meta = self.new_object()
  let _ = js_set_prop(new_meta, "target", new_target)
  call_env.define_var("new", new_meta)
  let args_obj = js_array_from(args)
  call_env.define_var("arguments", args_obj)
  match closure.body {
    Ast(func_def) => {
      self.bind_params(func_def.params, args, call_env)
      let state : JSGeneratorState = {
        func: func_def,
        env: call_env,
        index: 0,
        done: false,
      }
      self.generators.push(state)
      let gen_id = self.generators.length() - 1
      let obj = self.new_object()
      let _ = js_set_prop(obj, "__class", String("Generator"))
      let _ = js_set_prop(obj, "__gen_id", Number(gen_id.to_double()))
      let _ = js_set_prop(obj, "next", self.make_native("Generator.prototype.next"))
      obj
    }
    _ => Undefined
  }
}

///|
fn contains_key(keys : Array[String], key : String) -> Bool {
  for item in keys {
    if item == key {
      return true
    }
  }
  false
}

///|
fn JSInterpreter::array_like_length(_self : JSInterpreter, value : JSValue) -> Int {
  match js_get_prop(value, "length") {
    Number(n) => n.to_int()
    _ => 0
  }
}

///|
fn JSInterpreter::array_like_get(_self : JSInterpreter, value : JSValue, index : Int) -> JSValue {
  js_get_prop(value, index.to_string())
}

///|
fn JSInterpreter::maybe_set_function_name_for_binding(
  self : JSInterpreter,
  binding : @parser.TsBinding,
  value : JSValue,
) -> Unit {
  match binding {
    @parser.TsBinding::Ident(name) => self.maybe_set_function_name(value, name)
    _ => ()
  }
}

///|
fn JSInterpreter::maybe_set_function_name(
  self : JSInterpreter,
  value : JSValue,
  name : String,
) -> Unit {
  if name == "<destruct>" {
    return
  }
  match value {
    Function(_) =>
      if not(self.has_own_prop(value, "name")) {
        self.set_function_name(value, name)
      } else {
        match js_get_prop(value, "name") {
          String(s) =>
            if s.length() == 0 || s == "<anon>" || s == "<arrow>" {
              self.set_function_name(value, name)
            }
          _ => ()
        }
      }
    _ => ()
  }
}

///|
fn JSInterpreter::bind_pattern(
  self : JSInterpreter,
  binding : @parser.TsBinding,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match binding {
    @parser.TsBinding::Ident(name) => env.define_var(name, value)
    @parser.TsBinding::Array(arr) => self.bind_array_pattern(arr, value, env)
    @parser.TsBinding::Object(obj) => self.bind_object_pattern(obj, value, env)
  }
}

///|
fn JSInterpreter::bind_array_pattern(
  self : JSInterpreter,
  pattern : @parser.TsArrayBinding,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match value {
    Undefined | Null => {
      let _ = self.set_error_kind(
        "TypeError",
        "Cannot destructure undefined or null",
      )
      return
    }
    _ => ()
  }
  match self.get_generator_id(value) {
    Some(gen_id) => {
      let mut done = false
      let next_value = fn() -> JSValue {
        if done {
          JSValue::Undefined
        } else {
          let result = self.generator_next(gen_id)
          let (is_done, val) = self.iter_result_value_done(result)
          done = is_done
          val
        }
      }
      for item in pattern.items {
        match item {
          None => {
            if not(done) {
              let _ = next_value()
            }
          }
          Some(elem) => {
            let mut val = if done { JSValue::Undefined } else { next_value() }
            let mut used_default = false
            match elem.default {
              Some(expr) =>
                if val is Undefined {
                  val = self.eval_expr(expr, env)
                  used_default = true
                }
              None => ()
            }
            if used_default {
              self.maybe_set_function_name_for_binding(elem.binding, val)
            }
            self.bind_pattern(elem.binding, val, env)
          }
        }
      }
      match pattern.rest {
        None => ()
        Some(rest_binding) => {
          let rest_items : Array[JSValue] = []
          while not(done) {
            let val = next_value()
            if done {
              break
            }
            rest_items.push(val)
          }
          let rest_val = js_array_from(rest_items)
          self.bind_pattern(rest_binding, rest_val, env)
        }
      }
    }
    None => {
      let len = self.array_like_length(value)
      let mut index = 0
      for item in pattern.items {
        match item {
          None => index = index + 1
          Some(elem) => {
            let mut val = if index < len {
              self.array_like_get(value, index)
            } else {
              Undefined
            }
            let mut used_default = false
            match elem.default {
              Some(expr) =>
                if val is Undefined {
                  val = self.eval_expr(expr, env)
                  used_default = true
                }
              None => ()
            }
            if used_default {
              self.maybe_set_function_name_for_binding(elem.binding, val)
            }
            self.bind_pattern(elem.binding, val, env)
            index = index + 1
          }
        }
      }
      match pattern.rest {
        None => ()
        Some(rest_binding) => {
          let rest_items : Array[JSValue] = []
          while index < len {
            rest_items.push(self.array_like_get(value, index))
            index = index + 1
          }
          let rest_val = js_array_from(rest_items)
          self.bind_pattern(rest_binding, rest_val, env)
        }
      }
    }
  }
}

///|
fn JSInterpreter::bind_object_pattern(
  self : JSInterpreter,
  pattern : @parser.TsObjectBinding,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match value {
    Undefined | Null => {
      let _ = self.set_error_kind(
        "TypeError",
        "Cannot destructure undefined or null",
      )
      return
    }
    _ => ()
  }
  let used_keys : Array[String] = []
  for prop in pattern.props {
    used_keys.push(prop.key)
    let mut val = js_get_prop(value, prop.key)
    let mut used_default = false
    match prop.default {
      Some(expr) =>
        if val is Undefined {
          val = self.eval_expr(expr, env)
          used_default = true
        }
      None => ()
    }
    if used_default {
      self.maybe_set_function_name_for_binding(prop.binding, val)
    }
    self.bind_pattern(prop.binding, val, env)
  }
  match pattern.rest {
    None => ()
    Some(rest_name) => {
      let rest_obj = self.new_object()
      match value {
        Object(map) => {
          for prop in map.props {
            if not(contains_key(used_keys, prop.key)) {
              let _ = js_set_prop(rest_obj, prop.key, prop.value)
            }
          }
        }
        Array(arr) => {
          for i, item in arr.items {
            let key = i.to_string()
            if not(contains_key(used_keys, key)) {
              let _ = js_set_prop(rest_obj, key, item)
            }
          }
          for prop in arr.props {
            if not(contains_key(used_keys, prop.key)) {
              let _ = js_set_prop(rest_obj, prop.key, prop.value)
            }
          }
        }
        Function(closure) => {
          for prop in closure.props {
            if not(contains_key(used_keys, prop.key)) {
              let _ = js_set_prop(rest_obj, prop.key, prop.value)
            }
          }
        }
        _ => ()
      }
      env.define_var(rest_name, rest_obj)
    }
  }
}

///|
fn JSInterpreter::bind_params(
  self : JSInterpreter,
  params : Array[@parser.TsParam],
  args : Array[JSValue],
  env : JSEnv,
) -> Unit {
  let mut arg_index = 0
  for param in params {
    let mut val = if param.is_rest {
      let rest_items : Array[JSValue] = []
      while arg_index < args.length() {
        rest_items.push(args[arg_index])
        arg_index = arg_index + 1
      }
      js_array_from(rest_items)
    } else {
      let v = if arg_index < args.length() { args[arg_index] } else { Undefined }
      arg_index = arg_index + 1
      v
    }
    let mut used_default = false
    match param.default {
      Some(expr) =>
        if val is Undefined {
          val = self.eval_expr(expr, env)
          used_default = true
        }
      None => ()
    }
    match param.binding {
      Some(binding) => {
        if used_default {
          self.maybe_set_function_name_for_binding(binding, val)
        }
        self.bind_pattern(binding, val, env)
      }
      None => {
        if used_default {
          self.maybe_set_function_name(val, param.name)
        }
        env.define_var(param.name, val)
      }
    }
  }
}

///|
fn JSInterpreter::make_iter_result(
  self : JSInterpreter,
  value : JSValue,
  done : Bool,
) -> JSValue {
  let obj = self.new_object()
  let _ = js_set_prop(obj, "value", value)
  let _ = js_set_prop(obj, "done", Bool(done))
  obj
}

///|
fn JSInterpreter::get_generator_id(_self : JSInterpreter, value : JSValue) -> Int? {
  match js_get_prop(value, "__gen_id") {
    Number(n) => Some(n.to_int())
    _ => None
  }
}

///|
fn JSInterpreter::generator_next(self : JSInterpreter, gen_id : Int) -> JSValue {
  if gen_id < 0 || gen_id >= self.generators.length() {
    return self.set_error_kind("TypeError", "Invalid generator")
  }
  let state = self.generators[gen_id]
  if state.done {
    return self.make_iter_result(Undefined, true)
  }
  let stmts = state.func.body.stmts
  while state.index < stmts.length() {
    let stmt = stmts[state.index]
    state.index = state.index + 1
    match self.exec_stmt_gen(stmt, state.env) {
      GenSignal::Continue => ()
      GenSignal::Yield(val) => {
        self.generators[gen_id] = state
        return self.make_iter_result(val, false)
      }
      GenSignal::Return(val) => {
        state.done = true
        self.generators[gen_id] = state
        return self.make_iter_result(val, true)
      }
    }
    match self.peek_error() {
      Some(err) => {
        state.done = true
        self.generators[gen_id] = state
        return err
      }
      None => ()
    }
  }
  state.done = true
  self.generators[gen_id] = state
  self.make_iter_result(Undefined, true)
}

///|
fn JSInterpreter::iter_result_value_done(
  _self : JSInterpreter,
  result : JSValue,
) -> (Bool, JSValue) {
  match result {
    Object(_) => {
      let done_val = js_get_prop(result, "done")
      let done = done_val.to_boolean()
      let val = js_get_prop(result, "value")
      (done, val)
    }
    _ => (true, Undefined)
  }
}

///|
fn JSInterpreter::exec_stmt_gen(
  self : JSInterpreter,
  stmt : @parser.TsStmt,
  env : JSEnv,
) -> GenSignal {
  self.tick()
  match self.peek_error() {
    Some(err) => return GenSignal::Return(err)
    None => ()
  }
  match stmt {
    @parser.TsStmt::Expr(expr) =>
      match expr {
        @parser.TsExpr::Yield(opt) => {
          let val = match opt {
            Some(e) => self.eval_expr(e, env)
            None => Undefined
          }
          GenSignal::Yield(val)
        }
        _ => {
          let _ = self.eval_expr(expr, env)
          match self.peek_error() {
            Some(err) => GenSignal::Return(err)
            None => GenSignal::Continue
          }
        }
      }
    @parser.TsStmt::Return(opt) => {
      let val = match opt {
        Some(e) => self.eval_expr(e, env)
        None => Undefined
      }
      GenSignal::Return(val)
    }
    @parser.TsStmt::Block(block) => {
      for inner in block.stmts {
        match self.exec_stmt_gen(inner, env) {
          GenSignal::Continue => ()
          other => return other
        }
      }
      GenSignal::Continue
    }
    _ =>
      match self.exec_stmt(stmt, env) {
        Some(BreakSignal) | Some(ContinueSignal) => GenSignal::Continue
        Some(val) => GenSignal::Return(val)
        None => GenSignal::Continue
      }
  }
}

///|
// / instanceof simplecheck
fn JSInterpreter::instanceof(self : JSInterpreter, left : JSValue, right : JSValue) -> Bool {
  self.ordinary_has_instance(right, left)
}

///|
// / function
pub fn JSInterpreter::call_function(
  self : JSInterpreter,
  func : JSValue,
  this_arg : JSValue,
  args : Array[JSValue],
  new_target? : JSValue = Undefined,
) -> JSValue {
  match func {
    Function(closure) => {
      if closure.is_generator {
        return self.make_generator(closure, this_arg, args, new_target)
      }
      // create
      let call_env = js_new_env(Some(closure.env))
      if closure.is_strict {
        call_env.define_var("__strict__", Bool(true))
      }
      if not(closure.is_arrow) {
        if closure.is_strict {
          call_env.define_var("this", this_arg)
        } else {
          let bound_this = match this_arg {
            Undefined | Null => closure.env.get("globalThis")
            Bool(_) | Number(_) | String(_) => self.wrap_primitive(closure.env, this_arg)
            _ => this_arg
          }
          call_env.define_var("this", bound_this)
        }
        let new_meta = self.new_object()
        let _ = js_set_prop(new_meta, "target", new_target)
        call_env.define_var("new", new_meta)

        let args_obj = js_array_from(args)
        call_env.define_var("arguments", args_obj)
      }

      let super_ctor = js_get_prop(func, "__super_ctor")
      match super_ctor {
        Undefined => ()
        _ => {
          call_env.define_var("__super_ctor", super_ctor)
          call_env.define_var("__super_called", Bool(false))
        }
      }
      let super_proto = js_get_prop(func, "__super_proto")
      match super_proto {
        Undefined => ()
        _ => {
          call_env.define_var("__super_proto", super_proto)
          call_env.define_var("__super_this", call_env.get("this"))
        }
      }

      // argument
      match closure.body {
        Ast(func_def) => self.bind_params(func_def.params, args, call_env)
        _ =>
          for i, param in closure.params {
            let val = if i < args.length() { args[i] } else { Undefined }
            call_env.define_var(param, val)
          }
      }

      // run
      match closure.body {
        Ast(func_def) =>
          match self.exec_block(func_def.body, call_env) {
            Some(val) => val
            None => Undefined
          }
        Native(name) => self.call_native(name, this_arg, args)
        Bound(target, bound_this, bound_args) => {
          let merged : Array[JSValue] = []
          for item in bound_args {
            merged.push(item)
          }
          for item in args {
            merged.push(item)
          }
          self.call_function(target, bound_this, merged)
        }
      }
    }
    Object(map) => {
      let callee = js_get_prop(Object(map), "$call")
      match callee {
        Function(_) => self.call_function(callee, this_arg, args)
        _ => Undefined
      }
    }
    _ => Undefined
  }
}

///|
// / method
pub fn JSInterpreter::call_method(
  self : JSInterpreter,
  obj : JSValue,
  method_name : String,
  args : Array[JSValue],
) -> JSValue {
  match obj {
    String(s) => self.string_method(s, method_name, args)
    Array(arr) => self.array_method(arr, method_name, args)
    Function(_) =>
      match method_name {
        "call" | "apply" | "bind" => self.function_method(obj, method_name, args)
        _ => {
          let func = self.get_prop_value(obj, method_name)
          self.call_function(func, obj, args)
        }
      }
    Object(map) => {
      // objectmethodlookup
      let func = self.get_prop_value(Object(map), method_name)
      self.call_function(func, obj, args)
    }
    _ => Undefined
  }
}

///|
// / functionmethod (call/apply/bind)
fn JSInterpreter::function_method(
  self : JSInterpreter,
  func : JSValue,
  method_name : String,
  args : Array[JSValue],
) -> JSValue {
  match method_name {
    "call" => {
      let this_arg = if args.length() > 0 { args[0] } else { Undefined }
      let call_args : Array[JSValue] = []
      for i in 1..<args.length() {
        call_args.push(args[i])
      }
      self.call_function(func, this_arg, call_args)
    }
    "apply" => {
      let this_arg = if args.length() > 0 { args[0] } else { Undefined }
      let call_args : Array[JSValue] = []
      if args.length() > 1 {
        match args[1] {
          Array(arr) => {
            for item in arr.items {
              call_args.push(item)
            }
          }
          _ => ()
        }
      }
      self.call_function(func, this_arg, call_args)
    }
    "bind" => {
      let this_arg = if args.length() > 0 { args[0] } else { Undefined }
      let bound_args : Array[JSValue] = []
      for i in 1..<args.length() {
        bound_args.push(args[i])
      }
      let bound = JSValue::Function({
        id: fresh_function_id(),
        params: [],
        body: Bound(func, this_arg, bound_args),
        env: self.global_env,
        is_arrow: false,
        is_strict: false,
        is_generator: false,
        props: [],
        object_proto: Some(self.function_proto),
      })
      let len = self.calc_bound_length(func, bound_args.length())
      self.set_function_length(bound, len)
      let target_name_val = self.get_prop_value(func, "name")
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      let target_name = match target_name_val {
        String(s) => s
        _ => ""
      }
      self.set_function_name(bound, "bound " + target_name)
      bound
    }
    _ => Undefined
  }
}

///|
// / stringmethod
fn JSInterpreter::string_method(
  _self : JSInterpreter,
  s : String,
  method_name : String,
  args : Array[JSValue],
) -> JSValue {
  match method_name {
    "length" => Number(s.length().to_double())
    "valueOf" => String(s)
    "toString" => String(s)
    "charAt" => {
      let idx = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      if idx >= 0 && idx < s.length() {
        String(try { s[idx:idx + 1].to_string() } catch { _ => "" })
      } else {
        String("")
      }
    }
    "charCodeAt" => {
      let idx = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      if idx >= 0 && idx < s.length() {
        Number(s[idx].to_int().to_double())
      } else {
        Number(0.0 / 0.0)
      }
    }
    "codePointAt" => {
      let idx = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      if idx < 0 || idx >= s.length() {
        Undefined
      } else {
        let cu1 = s[idx]
        if cu1.is_leading_surrogate() && idx + 1 < s.length() {
          let cu2 = s[idx + 1]
          if cu2.is_trailing_surrogate() {
            let hi = cu1.to_int() - 0xd800
            let lo = cu2.to_int() - 0xdc00
            let code = hi * 0x400 + lo + 0x10000
            Number(code.to_double())
          } else {
            Number(cu1.to_int().to_double())
          }
        } else {
          Number(cu1.to_int().to_double())
        }
      }
    }
    "indexOf" => {
      let search_str = if args.length() > 0 {
        args[0].to_js_string()
      } else {
        ""
      }
      let mut start_idx = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      if start_idx < 0 {
        start_idx = 0
      }
      if search_str.length() == 0 {
        return Number(start_idx.to_double())
      }
      let search_len = search_str.length()
      let mut idx = -1
      if start_idx < s.length() && start_idx + search_len <= s.length() {
        let end_idx = s.length() - search_len + 1
        let mut i = start_idx
        while i < end_idx && idx == -1 {
          if (try { s[i:i + search_len].to_string() } catch { _ => "" }) == search_str {
            idx = i
          }
          i = i + 1
        }
      }
      Number(idx.to_double())
    }
    "lastIndexOf" => {
      let search_str = if args.length() > 0 {
        args[0].to_js_string()
      } else {
        ""
      }
      let mut pos = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        s.length()
      }
      if pos > s.length() {
        pos = s.length()
      }
      if pos < 0 {
        pos = 0
      }
      if search_str.length() == 0 {
        return Number(pos.to_double())
      }
      let search_len = search_str.length()
      let mut idx = -1
      let mut i = pos - search_len
      if i < 0 {
        i = 0
      }
      while i >= 0 {
        if (try { s[i:i + search_len].to_string() } catch { _ => "" }) == search_str {
          idx = i
          break
        }
        if i == 0 {
          break
        }
        i = i - 1
      }
      Number(idx.to_double())
    }
    "includes" => {
      let search_str = if args.length() > 0 { args[0].to_js_string() } else { "" }
      let mut start_idx = if args.length() > 1 { args[1].to_number().to_int() } else { 0 }
      if start_idx < 0 {
        start_idx = 0
      }
      if search_str.length() == 0 {
        Bool(true)
      } else if start_idx + search_str.length() > s.length() {
        Bool(false)
      } else {
        let search_len = search_str.length()
        let end_idx = s.length() - search_len + 1
        let mut i = start_idx
        let mut found = false
        while i < end_idx && not(found) {
          if (try { s[i:i + search_len].to_string() } catch { _ => "" }) == search_str {
            found = true
          }
          i = i + 1
        }
        Bool(found)
      }
    }
    "startsWith" => {
      let search_str = if args.length() > 0 { args[0].to_js_string() } else { "" }
      let mut pos = if args.length() > 1 { args[1].to_number().to_int() } else { 0 }
      if pos < 0 {
        pos = 0
      }
      let search_len = search_str.length()
      if search_len == 0 {
        Bool(true)
      } else if pos + search_len > s.length() {
        Bool(false)
      } else {
        Bool(
          (try { s[pos:pos + search_len].to_string() } catch { _ => "" }) == search_str,
        )
      }
    }
    "endsWith" => {
      let search_str = if args.length() > 0 { args[0].to_js_string() } else { "" }
      let mut end_pos = if args.length() > 1 { args[1].to_number().to_int() } else { s.length() }
      if end_pos > s.length() {
        end_pos = s.length()
      }
      if end_pos < 0 {
        end_pos = 0
      }
      let search_len = search_str.length()
      if search_len == 0 {
        Bool(true)
      } else if search_len > end_pos {
        Bool(false)
      } else {
        let start = end_pos - search_len
        Bool(
          (try { s[start:end_pos].to_string() } catch { _ => "" }) == search_str,
        )
      }
    }
    "at" => {
      let mut idx = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      if idx < 0 {
        idx = s.length() + idx
      }
      if idx < 0 || idx >= s.length() {
        Undefined
      } else {
        String(try { s[idx:idx + 1].to_string() } catch { _ => "" })
      }
    }
    "split" => {
      let limit = if args.length() > 1 {
        let n = args[1].to_number()
        if n.is_nan() || n <= 0.0 {
          0
        } else {
          let two32 = 4294967296.0
          let mut m = n % two32
          if m < 0.0 {
            m = m + two32
          }
          let lim = m.floor()
          if lim > 2147483647.0 {
            2147483647
          } else {
            lim.to_int()
          }
        }
      } else {
        -1
      }
      if limit == 0 {
        return js_new_array()
      }
      let sep_val = if args.length() > 0 { args[0] } else { Undefined }
      if is_regexp(sep_val) {
        let pattern = regexp_source(sep_val)
        let flags = regexp_flags(sep_val)
        let result = regexp_split_simple(pattern, flags, s, limit)
        return js_array_from(result)
      }
      match sep_val {
        Undefined => {
          return js_array_from([String(s)])
        }
        _ => ()
      }
      let sep = sep_val.to_js_string()
      let result : Array[JSValue] = []
      if sep.length() == 0 {
        if s.length() == 0 {
          result.push(String(""))
        } else {
          for i in 0..<s.length() {
            if limit >= 0 && result.length() >= limit {
              break
            }
            result.push(String(try { s[i:i + 1].to_string() } catch { _ => "" }))
          }
        }
        return js_array_from(result)
      }
      let mut start = 0
      let sep_len = sep.length()
      while start <= s.length() {
        if limit >= 0 && result.length() >= limit {
          break
        }
        let mut found = false
        let mut pos = start
        if start + sep_len <= s.length() {
          let end_idx = s.length() - sep_len + 1
          while pos < end_idx && not(found) {
            if (try { s[pos:pos + sep_len].to_string() } catch { _ => "" }) == sep {
              found = true
            } else {
              pos = pos + 1
            }
          }
        }
        if found {
          result.push(String(try { s[start:pos].to_string() } catch { _ => "" }))
          start = pos + sep_len
        } else {
          result.push(String(try { s[start:s.length()].to_string() } catch { _ => "" }))
          break
        }
      }
      js_array_from(result)
    }
    "replace" => {
      if args.length() > 0 && is_regexp(args[0]) {
        let pattern = regexp_source(args[0])
        let flags = regexp_flags(args[0])
        let to = if args.length() > 1 { args[1].to_js_string() } else { "" }
        String(regexp_replace_simple(
          pattern,
          flags,
          s,
          to,
          regexp_has_global(flags),
        ))
      } else {
        let from = if args.length() > 0 { args[0].to_js_string() } else { "" }
        let to = if args.length() > 1 { args[1].to_js_string() } else { "" }
        String(s.replace(old=from, new=to))
      }
    }
    "replaceAll" => {
      let from = if args.length() > 0 { args[0].to_js_string() } else { "" }
      let to = if args.length() > 1 { args[1].to_js_string() } else { "" }
      String(s.replace_all(old=from, new=to))
    }
    "match" => {
      let pat = if args.length() > 0 { args[0] } else { Undefined }
      if is_regexp(pat) {
        let pattern = regexp_source(pat)
        let flags = regexp_flags(pat)
        regexp_match_simple(pattern, flags, s, regexp_has_global(flags))
      } else {
        let pattern = pat.to_js_string()
        regexp_match_simple(pattern, "", s, false)
      }
    }
    "search" => {
      let pat = if args.length() > 0 { args[0] } else { Undefined }
      if is_regexp(pat) {
        let pattern = regexp_source(pat)
        let flags = regexp_flags(pat)
        Number(regexp_search_simple(pattern, flags, s).to_double())
      } else {
        let pattern = pat.to_js_string()
        Number(regexp_search_simple(pattern, "", s).to_double())
      }
    }
    "trim" => String(trim_js_string(s, "both"))
    "trimStart" => String(trim_js_string(s, "start"))
    "trimEnd" => String(trim_js_string(s, "end"))
    "substring" => {
      let mut start = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      let mut end = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        s.length()
      }
      if start < 0 {
        start = 0
      }
      if end < 0 {
        end = 0
      }
      if start > end {
        let tmp = start
        start = end
        end = tmp
      }
      if start > s.length() {
        start = s.length()
      }
      if end > s.length() {
        end = s.length()
      }
      String(try { s[start:end].to_string() } catch { _ => "" })
    }
    "toUpperCase" => String(s.to_upper())
    "toLowerCase" => String(s.to_lower())
    "toLocaleUpperCase" => String(s.to_upper())
    "toLocaleLowerCase" => String(s.to_lower())
    "repeat" => {
      let count = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      if count <= 0 {
        String("")
      } else {
        let mut out = ""
        for _ in 0..<count {
          out = out + s
        }
        String(out)
      }
    }
    "padStart" => {
      let target_len = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      let pad = if args.length() > 1 { args[1].to_js_string() } else { " " }
      if target_len <= s.length() {
        String(s)
      } else {
        let needed = target_len - s.length()
        let mut pad_str = ""
        if pad.length() == 0 {
          pad_str = ""
        } else {
          while pad_str.length() < needed {
            pad_str = pad_str + pad
          }
          if pad_str.length() > needed {
            pad_str = (try { pad_str[:needed].to_string() } catch { _ => pad_str })
          }
        }
        String(pad_str + s)
      }
    }
    "padEnd" => {
      let target_len = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      let pad = if args.length() > 1 { args[1].to_js_string() } else { " " }
      if target_len <= s.length() {
        String(s)
      } else {
        let needed = target_len - s.length()
        let mut pad_str = ""
        if pad.length() == 0 {
          pad_str = ""
        } else {
          while pad_str.length() < needed {
            pad_str = pad_str + pad
          }
          if pad_str.length() > needed {
            pad_str = (try { pad_str[:needed].to_string() } catch { _ => pad_str })
          }
        }
        String(s + pad_str)
      }
    }
    "concat" => {
      let mut result = s
      for arg in args {
        result = result + arg.to_js_string()
      }
      String(result)
    }
    _ => Undefined
  }
}

///|
// / JS trim check
fn is_js_trim_whitespace(unit : UInt16) -> Bool {
  let code = unit.to_int()
  if code == 0x0009 { return true }
  if code == 0x000a { return true }
  if code == 0x000b { return true }
  if code == 0x000c { return true }
  if code == 0x000d { return true }
  if code == 0x0020 { return true }
  if code == 0x00a0 { return true }
  if code == 0x1680 { return true }
  if code >= 0x2000 && code <= 0x200a { return true }
  if code == 0x2028 { return true }
  if code == 0x2029 { return true }
  if code == 0x202f { return true }
  if code == 0x205f { return true }
  if code == 0x3000 { return true }
  if code == 0xfeff { return true }
  false
}

///|
// / JS trim implementation
fn trim_js_string(s : String, mode : String) -> String {
  let len = s.length()
  let mut start = 0
  let mut end = len
  if mode == "both" || mode == "start" {
    while start < end && is_js_trim_whitespace(s[start]) {
      start = start + 1
    }
  }
  if mode == "both" || mode == "end" {
    while end > start && is_js_trim_whitespace(s[end - 1]) {
      end = end - 1
    }
  }
  try { s[start:end].to_string() } catch { _ => "" }
}

///|
// / SameValueZero check
fn JSInterpreter::same_value_zero(
  _self : JSInterpreter,
  left : JSValue,
  right : JSValue,
) -> Bool {
  match js_strict_eq(left, right) {
    Bool(true) => true
    _ => {
      let left_nan = match left {
        Number(n) => n.is_nan()
        _ => false
      }
      let right_nan = match right {
        Number(n) => n.is_nan()
        _ => false
      }
      left_nan && right_nan
    }
  }
}

///|
// / array
fn JSInterpreter::flatten_array_items(
  self : JSInterpreter,
  items : Array[JSValue],
  depth : Int,
  out : Array[JSValue],
) -> Unit {
  if depth <= 0 {
    for item in items {
      out.push(item)
    }
  } else {
    for item in items {
      match item {
        Array(arr) => self.flatten_array_items(arr.items, depth - 1, out)
        _ => out.push(item)
      }
    }
  }
}

///|
// / arraymethod
fn JSInterpreter::array_method(
  self : JSInterpreter,
  arr : JSArray,
  method_name : String,
  args : Array[JSValue],
) -> JSValue {
  let len = arr.items.length()
  match method_name {
    "length" => JSValue::Number(arr.length.to_double())
    "push" => {
      for arg in args {
        arr.items.push(arg)
      }
      arr.length = arr.items.length()
      JSValue::Number(arr.length.to_double())
    }
    "pop" =>
      if arr.items.length() > 0 {
        let result = arr.items.pop().unwrap_or(Undefined)
        arr.length = arr.items.length()
        result
      } else {
        Undefined
      }
    "shift" =>
      if arr.items.length() > 0 {
        let first = arr.items[0]
        let new_arr : Array[JSValue] = []
        for i in 1..<arr.items.length() {
          new_arr.push(arr.items[i])
        }
        arr.items.clear()
        for item in new_arr {
          arr.items.push(item)
        }
        arr.length = arr.items.length()
        first
      } else {
        Undefined
      }
    "unshift" => {
      let new_arr : Array[JSValue] = []
      for arg in args {
        new_arr.push(arg)
      }
      for item in arr.items {
        new_arr.push(item)
      }
      arr.items.clear()
      for item in new_arr {
        arr.items.push(item)
      }
      arr.length = arr.items.length()
      JSValue::Number(arr.length.to_double())
    }
    "join" => {
      let sep = if args.length() > 0 { args[0].to_js_string() } else { "," }
      let parts : Array[String] = []
      for item in arr.items {
        parts.push(item.to_js_string())
      }
      JSValue::String(parts.join(sep))
    }
    "toString" => {
      let parts : Array[String] = []
      for item in arr.items {
        parts.push(item.to_js_string())
      }
      JSValue::String(parts.join(","))
    }
    "indexOf" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let mut start_idx = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      if start_idx < 0 {
        start_idx = len + start_idx
        if start_idx < 0 {
          start_idx = 0
        }
      }
      if start_idx >= len {
        return JSValue::Number(-1.0)
      }
      for i in start_idx..<len {
        match js_strict_eq(arr.items[i], target) {
          JSValue::Bool(true) => return JSValue::Number(i.to_double())
          _ => ()
        }
      }
      JSValue::Number(-1.0)
    }
    "lastIndexOf" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let mut from_idx = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        len - 1
      }
      if from_idx < 0 {
        from_idx = len + from_idx
      }
      if from_idx >= len {
        from_idx = len - 1
      }
      if from_idx < 0 {
        return JSValue::Number(-1.0)
      }
      let mut i = from_idx
      while i >= 0 {
        match js_strict_eq(arr.items[i], target) {
          JSValue::Bool(true) => return JSValue::Number(i.to_double())
          _ => ()
        }
        if i == 0 {
          break
        }
        i = i - 1
      }
      JSValue::Number(-1.0)
    }
    "includes" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let mut start_idx = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      if start_idx < 0 {
        start_idx = len + start_idx
        if start_idx < 0 {
          start_idx = 0
        }
      }
      for i in start_idx..<len {
        if self.same_value_zero(arr.items[i], target) {
          return Bool(true)
        }
      }
      Bool(false)
    }
    "map" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let result : Array[JSValue] = []
            let mut i = 0
            while i < len {
              let args_array = [
                arr.items[i],
                JSValue::Number(i.to_double()),
                JSValue::Array(arr),
              ]
              let mapped = self.call_function(
                JSValue::Function(closure),
                this_arg,
                args_array,
              )
              result.push(mapped)
              i += 1
            }
            js_array_from(result)
          }
          _ => js_new_array()
        }
      } else {
        js_new_array()
      }
    "filter" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let result : Array[JSValue] = []
            let mut i = 0
            while i < len {
              let item = arr.items[i]
              let args_array = [
                item,
                JSValue::Number(i.to_double()),
                JSValue::Array(arr),
              ]
              let filtered = self.call_function(
                JSValue::Function(closure),
                this_arg,
                args_array,
              )
              match filtered {
                Bool(true) => result.push(item)
                _ => ()
              }
              i += 1
            }
            js_array_from(result)
          }
          _ => js_new_array()
        }
      } else {
        js_new_array()
      }
    "reduce" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let has_init = args.length() > 1
            if len == 0 && not(has_init) {
              return self.set_error_kind(
                "TypeError",
                "Reduce of empty array with no initial value",
              )
            }
            let mut accumulator = if has_init { args[1] } else { arr.items[0] }
            let mut i = if has_init { 0 } else { 1 }
            while i < len {
              let args_array = [
                accumulator,
                arr.items[i],
                JSValue::Number(i.to_double()),
                JSValue::Array(arr),
              ]
              accumulator = self.call_function(
                JSValue::Function(closure),
                Undefined,
                args_array,
              )
              i += 1
            }
            accumulator
          }
          _ => Undefined
        }
      } else {
        Undefined
      }
    "reduceRight" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let has_init = args.length() > 1
            if len == 0 && not(has_init) {
              return self.set_error_kind(
                "TypeError",
                "Reduce of empty array with no initial value",
              )
            }
            let mut accumulator = if has_init {
              args[1]
            } else {
              arr.items[len - 1]
            }
            let mut i = if has_init { len - 1 } else { len - 2 }
            while i >= 0 {
              let args_array = [
                accumulator,
                arr.items[i],
                JSValue::Number(i.to_double()),
                JSValue::Array(arr),
              ]
              accumulator = self.call_function(
                JSValue::Function(closure),
                Undefined,
                args_array,
              )
              if i == 0 {
                break
              }
              i = i - 1
            }
            accumulator
          }
          _ => Undefined
        }
      } else {
        Undefined
      }
    "forEach" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let mut i = 0
            while i < len {
              let args_array = [
                arr.items[i],
                JSValue::Number(i.to_double()),
                JSValue::Array(arr),
              ]
              let _ = self.call_function(
                JSValue::Function(closure),
                this_arg,
                args_array,
              )
              i += 1
            }
            Undefined
          }
          _ => Undefined
        }
      } else {
        Undefined
      }
    "every" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let mut i = 0
            while i < len {
              let args_array = [
                arr.items[i],
                JSValue::Number(i.to_double()),
                JSValue::Array(arr),
              ]
              let ok = self.call_function(
                JSValue::Function(closure),
                this_arg,
                args_array,
              )
              match ok {
                Bool(true) => ()
                _ => return Bool(false)
              }
              i += 1
            }
            Bool(true)
          }
          _ => Bool(false)
        }
      } else {
        Bool(false)
      }
    "some" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let mut i = 0
            while i < len {
              let args_array = [
                arr.items[i],
                JSValue::Number(i.to_double()),
                JSValue::Array(arr),
              ]
              let ok = self.call_function(
                JSValue::Function(closure),
                this_arg,
                args_array,
              )
              match ok {
                Bool(true) => return Bool(true)
                _ => ()
              }
              i += 1
            }
            Bool(false)
          }
          _ => Bool(false)
        }
      } else {
        Bool(false)
      }
    "find" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let mut i = 0
            while i < len {
              let item = arr.items[i]
              let args_array = [
                item,
                JSValue::Number(i.to_double()),
                JSValue::Array(arr),
              ]
              let found = self.call_function(
                JSValue::Function(closure),
                this_arg,
                args_array,
              )
              match found {
                Bool(true) => return item
                _ => ()
              }
              i += 1
            }
            Undefined
          }
          _ => Undefined
        }
      } else {
        Undefined
      }
    "findIndex" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let mut i = 0
            while i < len {
              let item = arr.items[i]
              let args_array = [
                item,
                JSValue::Number(i.to_double()),
                JSValue::Array(arr),
              ]
              let found = self.call_function(
                JSValue::Function(closure),
                this_arg,
                args_array,
              )
              match found {
                Bool(true) => return Number(i.to_double())
                _ => ()
              }
              i += 1
            }
            Number(-1.0)
          }
          _ => Number(-1.0)
        }
      } else {
        Number(-1.0)
      }
    "findLast" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let mut i = len - 1
            while i >= 0 {
              let item = arr.items[i]
              let args_array = [
                item,
                JSValue::Number(i.to_double()),
                JSValue::Array(arr),
              ]
              let found = self.call_function(
                JSValue::Function(closure),
                this_arg,
                args_array,
              )
              match found {
                Bool(true) => return item
                _ => ()
              }
              if i == 0 {
                break
              }
              i = i - 1
            }
            Undefined
          }
          _ => Undefined
        }
      } else {
        Undefined
      }
    "findLastIndex" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let mut i = len - 1
            while i >= 0 {
              let item = arr.items[i]
              let args_array = [
                item,
                JSValue::Number(i.to_double()),
                JSValue::Array(arr),
              ]
              let found = self.call_function(
                JSValue::Function(closure),
                this_arg,
                args_array,
              )
              match found {
                Bool(true) => return Number(i.to_double())
                _ => ()
              }
              if i == 0 {
                break
              }
              i = i - 1
            }
            Number(-1.0)
          }
          _ => Number(-1.0)
        }
      } else {
        Number(-1.0)
      }
    "slice" => {
      let mut start = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      let mut end = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        len
      }
      if start < 0 {
        start = len + start
        if start < 0 {
          start = 0
        }
      }
      if end < 0 {
        end = len + end
        if end < 0 {
          end = 0
        }
      }
      if start > len {
        start = len
      }
      if end > len {
        end = len
      }
      if end < start {
        end = start
      }
      let result : Array[JSValue] = []
      for i in start..<end {
        result.push(arr.items[i])
      }
      js_array_from(result)
    }
    "concat" => {
      let result : Array[JSValue] = arr.items.copy()
      for arg in args {
        match arg {
          Array(other_arr) =>
            for item in other_arr.items {
              result.push(item)
            }
          _ => result.push(arg)
        }
      }
      js_array_from(result)
    }
    "splice" => {
      let mut start = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      if start < 0 {
        start = len + start
        if start < 0 {
          start = 0
        }
      }
      if start > len {
        start = len
      }
      let mut delete_count = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        len - start
      }
      if delete_count < 0 {
        delete_count = 0
      }
      if delete_count > len - start {
        delete_count = len - start
      }
      let removed : Array[JSValue] = []
      for i in 0..<delete_count {
        removed.push(arr.items[start + i])
      }
      let insert_items : Array[JSValue] = []
      if args.length() > 2 {
        for i in 2..<args.length() {
          insert_items.push(args[i])
        }
      }
      let new_items : Array[JSValue] = []
      for i in 0..<start {
        new_items.push(arr.items[i])
      }
      for item in insert_items {
        new_items.push(item)
      }
      for i in (start + delete_count)..<len {
        new_items.push(arr.items[i])
      }
      arr.items.clear()
      for item in new_items {
        arr.items.push(item)
      }
      arr.length = arr.items.length()
      js_array_from(removed)
    }
    "toSpliced" => {
      let mut start = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      if start < 0 {
        start = len + start
        if start < 0 {
          start = 0
        }
      }
      if start > len {
        start = len
      }
      let mut delete_count = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        len - start
      }
      if delete_count < 0 {
        delete_count = 0
      }
      if delete_count > len - start {
        delete_count = len - start
      }
      let insert_items : Array[JSValue] = []
      if args.length() > 2 {
        for i in 2..<args.length() {
          insert_items.push(args[i])
        }
      }
      let new_items : Array[JSValue] = []
      for i in 0..<start {
        new_items.push(arr.items[i])
      }
      for item in insert_items {
        new_items.push(item)
      }
      for i in (start + delete_count)..<len {
        new_items.push(arr.items[i])
      }
      js_array_from(new_items)
    }
    "sort" => {
      let compare_fn = if args.length() > 0 { args[0] } else { Undefined }
      let mut i = 0
      while i < len {
        let mut j = i + 1
        while j < len {
          let order = match compare_fn {
            Function(closure) => {
              let res = self.call_function(
                JSValue::Function(closure),
                Undefined,
                [arr.items[i], arr.items[j]],
              )
              let n = res.to_number()
              if n.is_nan() {
                0
              } else if n < 0.0 {
                -1
              } else if n > 0.0 {
                1
              } else {
                0
              }
            }
            _ => {
              let a = arr.items[i].to_js_string()
              let b = arr.items[j].to_js_string()
              a.compare(b)
            }
          }
          if order > 0 {
            let tmp = arr.items[i]
            arr.items[i] = arr.items[j]
            arr.items[j] = tmp
          }
          j += 1
        }
        i += 1
      }
      JSValue::Array(arr)
    }
    "toSorted" => {
      let compare_fn = if args.length() > 0 { args[0] } else { Undefined }
      let new_items : Array[JSValue] = arr.items.copy()
      let new_arr : JSArray = {
        id: fresh_array_id(),
        items: new_items,
        props: [],
        length: new_items.length(),
        prototype: arr.prototype,
      }
      let _ = self.array_method(new_arr, "sort", [compare_fn])
      JSValue::Array(new_arr)
    }
    "toReversed" => {
      let result : Array[JSValue] = []
      if len > 0 {
        let mut i = len - 1
        while i >= 0 {
          result.push(arr.items[i])
          if i == 0 {
            break
          }
          i = i - 1
        }
      }
      js_array_from(result)
    }
    "with" =>
      if args.length() >= 2 {
        let mut idx = args[0].to_number().to_int()
        if idx < 0 {
          idx = len + idx
        }
        if idx < 0 || idx >= len {
          self.set_error_kind("RangeError", "Invalid array index")
        } else {
          let result : Array[JSValue] = arr.items.copy()
          result[idx] = args[1]
          js_array_from(result)
        }
      } else {
        js_array_from(arr.items.copy())
      }
    "flat" => {
      let depth = if args.length() > 0 { args[0].to_number().to_int() } else { 1 }
      let result : Array[JSValue] = []
      if depth <= 0 {
        for item in arr.items {
          result.push(item)
        }
      } else {
        self.flatten_array_items(arr.items, depth, result)
      }
      js_array_from(result)
    }
    "flatMap" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let mapped : Array[JSValue] = []
            let mut i = 0
            while i < len {
              let args_array = [
                arr.items[i],
                JSValue::Number(i.to_double()),
                JSValue::Array(arr),
              ]
              let value = self.call_function(
                JSValue::Function(closure),
                this_arg,
                args_array,
              )
              mapped.push(value)
              i += 1
            }
            let result : Array[JSValue] = []
            self.flatten_array_items(mapped, 1, result)
            js_array_from(result)
          }
          _ => js_new_array()
        }
      } else {
        js_new_array()
      }
    "fill" => {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      let mut start = if args.length() > 1 { args[1].to_number().to_int() } else { 0 }
      let mut end = if args.length() > 2 { args[2].to_number().to_int() } else { len }
      if start < 0 {
        start = len + start
        if start < 0 {
          start = 0
        }
      }
      if end < 0 {
        end = len + end
        if end < 0 {
          end = 0
        }
      }
      if start > len {
        start = len
      }
      if end > len {
        end = len
      }
      for i in start..<end {
        arr.items[i] = value
      }
      arr.length = arr.items.length()
      JSValue::Array(arr)
    }
    "copyWithin" => {
      let mut target = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      let mut start = if args.length() > 1 { args[1].to_number().to_int() } else { 0 }
      let mut end = if args.length() > 2 { args[2].to_number().to_int() } else { len }
      if target < 0 {
        target = len + target
      }
      if start < 0 {
        start = len + start
      }
      if end < 0 {
        end = len + end
      }
      if target < 0 {
        target = 0
      }
      if start < 0 {
        start = 0
      }
      if end < 0 {
        end = 0
      }
      if target > len {
        target = len
      }
      if start > len {
        start = len
      }
      if end > len {
        end = len
      }
      let count = if end - start < len - target { end - start } else { len - target }
      if count > 0 {
        let temp : Array[JSValue] = []
        for i in 0..<count {
          temp.push(arr.items[start + i])
        }
        for i in 0..<count {
          arr.items[target + i] = temp[i]
        }
      }
      JSValue::Array(arr)
    }
    "at" => {
      let mut idx = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      if idx < 0 {
        idx = len + idx
      }
      if idx < 0 || idx >= len {
        Undefined
      } else {
        arr.items[idx]
      }
    }
    _ => Undefined
  }
}

///|
fn JSInterpreter::call_native(
  self : JSInterpreter,
  name : String,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  if name.has_prefix("Array.prototype.") {
    let method_name = (try { name[16:] } catch { _ => "" }).to_string()
    match this_arg {
      Array(arr) => return self.array_method(arr, method_name, args)
      _ =>
        return self.set_error_kind(
          "TypeError",
          "Array.prototype." + method_name + " called on non-array",
        )
    }
  }
  if name.has_prefix("String.prototype.") {
    let method_name = (try { name[17:] } catch { _ => "" }).to_string()
    match this_arg {
      Undefined | Null =>
        return self.set_error_kind(
          "TypeError",
          "String.prototype." + method_name + " called on null or undefined",
        )
      _ => {
        let s = self.to_string_value(this_arg)
        return self.string_method(s, method_name, args)
      }
    }
  }
  match name {
    "Object" =>
      if args.length() == 0 {
        self.new_object()
      } else {
        let val = args[0]
        match val {
          Object(_) | Function(_) | Array(_) => val
          _ => {
            let obj = self.new_object()
            let _ = js_set_prop(obj, "value", val)
            obj
          }
        }
      }
    "Object.create" => {
      let proto = if args.length() > 0 { args[0] } else { Undefined }
      match proto {
        Null => js_new_object_with_proto(None)
        Object(_) | Function(_) | Array(_) => js_new_object_with_proto(Some(proto))
        _ => self.new_object()
      }
    }
    "Object.getPrototypeOf" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      match target {
        Object(map) => match map.prototype {
          Some(p) => p
          None => Null
        }
        Function(closure) => match closure.object_proto {
          Some(p) => p
          None => Null
        }
        Array(arr) => match arr.prototype {
          Some(p) => p
          None => Null
        }
        _ => Undefined
      }
    }
    "Object.getOwnPropertyDescriptor" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let key = if args.length() > 1 { args[1].to_js_string() } else { "" }
      match target {
        Function(closure) => {
          for prop in closure.props {
            if prop.key == key {
              if prop.get is Some(_) || prop.set is Some(_) {
                return self.make_accessor_descriptor(
                  prop.get,
                  prop.set,
                  prop.enumerable,
                  prop.configurable,
                )
              } else {
                return self.make_data_descriptor(
                  prop.value,
                  prop.writable,
                  prop.enumerable,
                  prop.configurable,
                )
              }
            }
          }
          Undefined
        }
        Object(map) => {
          for prop in map.props {
            if prop.key == key {
              if prop.get is Some(_) || prop.set is Some(_) {
                return self.make_accessor_descriptor(
                  prop.get,
                  prop.set,
                  prop.enumerable,
                  prop.configurable,
                )
              } else {
                return self.make_data_descriptor(
                  prop.value,
                  prop.writable,
                  prop.enumerable,
                  prop.configurable,
                )
              }
            }
          }
          Undefined
        }
        Array(arr) =>
          if key == "length" {
            self.make_data_descriptor(
              Number(arr.length.to_double()),
              true,
              false,
              false,
            )
          } else {
            let idx = @strconv.parse_int(key) catch { _ => -1 }
            if idx >= 0 && idx < arr.items.length() {
              self.make_data_descriptor(arr.items[idx], true, true, true)
            } else {
              for prop in arr.props {
                if prop.key == key {
                  if prop.get is Some(_) || prop.set is Some(_) {
                    return self.make_accessor_descriptor(
                      prop.get,
                      prop.set,
                      prop.enumerable,
                      prop.configurable,
                    )
                  } else {
                    return self.make_data_descriptor(
                      prop.value,
                      prop.writable,
                      prop.enumerable,
                      prop.configurable,
                    )
                  }
                }
              }
              Undefined
            }
          }
        String(s) =>
          if key == "length" {
            self.make_data_descriptor(
              Number(s.length().to_double()),
              false,
              false,
              false,
            )
          } else {
            Undefined
          }
        _ => Undefined
      }
    }
    "Object.defineProperty" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let key = if args.length() > 1 { args[1].to_js_string() } else { "" }
      let desc = if args.length() > 2 { args[2] } else { Undefined }
      let is_obj = match desc {
        Object(_) | Function(_) => true
        _ => false
      }
      if not(is_obj) {
        return target
      }
      let has_get = self.has_own_prop(desc, "get")
      let has_set = self.has_own_prop(desc, "set")
      let enumerable = if self.has_own_prop(desc, "enumerable") {
        js_get_prop(desc, "enumerable").to_boolean()
      } else {
        false
      }
      let configurable = if self.has_own_prop(desc, "configurable") {
        js_get_prop(desc, "configurable").to_boolean()
      } else {
        false
      }
      if has_get || has_set {
        let get_val = if has_get { js_get_prop(desc, "get") } else { Undefined }
        let set_val = if has_set { js_get_prop(desc, "set") } else { Undefined }
        let getter = match get_val {
          Undefined => None
          _ => Some(get_val)
        }
        let setter = match set_val {
          Undefined => None
          _ => Some(set_val)
        }
        let _ = js_define_accessor_prop(target, key, getter, setter, enumerable, configurable)
        target
      } else {
        let value = if self.has_own_prop(desc, "value") { js_get_prop(desc, "value") } else { Undefined }
        let writable = if self.has_own_prop(desc, "writable") {
          js_get_prop(desc, "writable").to_boolean()
        } else {
          false
        }
        let _ = js_define_data_prop(target, key, value, writable, enumerable, configurable)
        target
      }
    }
    "Object.hasOwnProperty" => {
      let key = if args.length() > 0 { args[0].to_js_string() } else { "" }
      match this_arg {
        Object(map) => {
          for prop in map.props {
            if prop.key == key {
              return Bool(true)
            }
          }
          Bool(false)
        }
        Function(closure) => {
          for prop in closure.props {
            if prop.key == key {
              return Bool(true)
            }
          }
          Bool(false)
        }
        Array(arr) =>
          if key == "length" {
            Bool(true)
          } else {
            let idx = @strconv.parse_int(key) catch { _ => -1 }
            if idx >= 0 && idx < arr.items.length() {
              Bool(true)
            } else {
              let mut found = false
              for prop in arr.props {
                if prop.key == key {
                  found = true
                  break
                }
              }
              Bool(found)
            }
          }
        String(s) =>
          if key == "length" {
            Bool(true)
          } else {
            let idx = @strconv.parse_int(key) catch { _ => -1 }
            Bool(idx >= 0 && idx < s.length())
          }
        _ => Bool(false)
      }
    }
    "Object.prototype.propertyIsEnumerable" => {
      let key = if args.length() > 0 { args[0].to_js_string() } else { "" }
      if self.has_own_prop(this_arg, key) {
        Bool(self.is_enumerable(this_arg, key))
      } else {
        Bool(false)
      }
    }
    "Object.getOwnPropertyNames" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let names : Array[JSValue] = []
      match target {
        Function(closure) =>
          for prop in closure.props {
            names.push(String(prop.key))
          }
        Object(map) =>
          for prop in map.props {
            names.push(String(prop.key))
          }
        Array(arr) => {
          for i in 0..<arr.items.length() {
            names.push(String(i.to_string()))
          }
          for prop in arr.props {
            names.push(String(prop.key))
          }
          names.push(String("length"))
        }
        _ => ()
      }
      match target {
        Function(_) => {
          let others : Array[JSValue] = []
          let mut has_length = false
          let mut has_name = false
          for item in names {
            match item {
              String("length") => has_length = true
              String("name") => has_name = true
              _ => others.push(item)
            }
          }
          let reordered : Array[JSValue] = []
          if has_length {
            reordered.push(String("length"))
          }
          if has_name {
            reordered.push(String("name"))
          }
          for item in others {
            reordered.push(item)
          }
          return js_array_from(reordered)
        }
        _ => ()
      }
      js_array_from(names)
    }
    "Object.isExtensible" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      match target {
        Object(_) | Function(_) | Array(_) => Bool(true)
        _ => Bool(false)
      }
    }
    "Object.prototype.toString" => {
      let tag = match this_arg {
        Undefined => "Undefined"
        Null => "Null"
        Bool(_) => "Boolean"
        Number(_) => "Number"
        String(_) => "String"
        Array(_) => "Array"
        Function(_) => "Function"
        Object(_) => {
          let class_tag = js_get_prop(this_arg, "__class")
          match class_tag {
            String(tag_name) => tag_name
            _ => {
              let prim = js_get_prop(this_arg, "value")
              match prim {
                Bool(_) => "Boolean"
                Number(_) => "Number"
                String(_) => "String"
                _ => "Object"
              }
            }
          }
        }
        BreakSignal | ContinueSignal => "Object"
      }
      String("[object " + tag + "]")
    }
    "Object.prototype.isPrototypeOf" => {
      if args.length() == 0 {
        Bool(false)
      } else {
        let target = args[0]
        let mut cur = self.get_proto(target)
        while cur is Some(p) {
          match js_strict_eq(p, this_arg) {
            Bool(true) => return Bool(true)
            _ => ()
          }
          cur = self.get_proto(p)
        }
        Bool(false)
      }
    }
    "Object.prototype.valueOf" => this_arg
    "Boolean.prototype.valueOf" => js_get_prop(this_arg, "value")
    "Number.prototype.valueOf" => js_get_prop(this_arg, "value")
    "String.prototype.valueOf" => js_get_prop(this_arg, "value")
    "SyntaxError" => {
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "" }
      self.make_error_obj("SyntaxError", msg)
    }
    "TypeError" => {
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "" }
      self.make_error_obj("TypeError", msg)
    }
    "ReferenceError" => {
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "" }
      self.make_error_obj("ReferenceError", msg)
    }
    "RangeError" => {
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "" }
      self.make_error_obj("RangeError", msg)
    }
    "Test262Error" => {
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "" }
      self.make_error_obj("Test262Error", msg)
    }
    "Function" => {
      let mut params_src = ""
      let mut body_src = ""
      if args.length() > 0 {
        if args.length() > 1 {
          let parts : Array[String] = []
          for i in 0..<(args.length() - 1) {
            parts.push(self.to_string_value(args[i]))
            match self.peek_error() {
              Some(err) => return err
              None => ()
            }
          }
          params_src = parts.join(",")
        }
        body_src = self.to_string_value(args[args.length() - 1])
        match self.peek_error() {
          Some(err) => return err
          None => ()
        }
      }
      let source =
        "function __f__(" + params_src + ") {\n" + body_src + "\n}"
      let func_value = try {
        let parser = @parser.Parser::from_source(source)
        let module_ = parser.parse_module()
        if module_.funcs.length() == 0 {
          JSValue::Undefined
        } else {
          let func = module_.funcs[0]
          let param_names : Array[String] = []
          for param in func.params {
            param_names.push(param.name)
          }
          let closure = JSValue::Function({
            id: fresh_function_id(),
            params: param_names,
            body: Ast(func),
            env: self.global_env,
            is_arrow: false,
            is_strict: self.is_strict_body(func.body, false),
            is_generator: func.is_generator,
            props: [],
            object_proto: Some(self.function_proto),
          })
          self.set_function_length(closure, param_names.length().to_double())
          let proto = self.new_object()
          let _ = js_set_prop(proto, "constructor", closure)
          let _ = js_define_data_prop(closure, "prototype", proto, true, false, true)
          closure
        }
      } catch {
        @parser.ParseError::ParseError(msg) => {
          let _ = self.set_error_kind("SyntaxError", "Function parse error: " + msg)
          JSValue::Undefined
        }
      }
      func_value
    }
    "Function.prototype" => Undefined
    "Function.prototype[@@hasInstance]" => {
      if args.length() == 0 {
        Bool(false)
      } else {
        Bool(self.ordinary_has_instance(this_arg, args[0]))
      }
    }
    "Function.call" => {
      let target = this_arg
      if not(self.is_callable(target)) {
        return self.set_error_kind("TypeError", "Function.prototype.call called on non-callable")
      }
      let call_this = if args.length() > 0 { args[0] } else { Undefined }
      let call_args : Array[JSValue] = []
      for i in 1..<args.length() {
        call_args.push(args[i])
      }
      self.call_function(target, call_this, call_args)
    }
    "Function.apply" => {
      let target = this_arg
      if not(self.is_callable(target)) {
        return self.set_error_kind("TypeError", "Function.prototype.apply called on non-callable")
      }
      let call_this = if args.length() > 0 { args[0] } else { Undefined }
      let call_args : Array[JSValue] = []
      if args.length() > 1 {
        match args[1] {
          Array(arr) =>
            for item in arr.items {
              call_args.push(item)
            }
          _ => ()
        }
      }
      self.call_function(target, call_this, call_args)
    }
    "Function.bind" => {
      let target = this_arg
      if not(self.is_callable(target)) {
        return self.set_error_kind("TypeError", "Function.prototype.bind called on non-callable")
      }
      let bound_this = if args.length() > 0 { args[0] } else { Undefined }
      let bound_args : Array[JSValue] = []
      for i in 1..<args.length() {
        bound_args.push(args[i])
      }
      let bound = JSValue::Function({
        id: fresh_function_id(),
        params: [],
        body: Bound(target, bound_this, bound_args),
        env: self.global_env,
        is_arrow: false,
        is_strict: false,
        is_generator: false,
        props: [],
        object_proto: Some(self.function_proto),
      })
      let len = self.calc_bound_length(target, bound_args.length())
      self.set_function_length(bound, len)
      let target_name_val = self.get_prop_value(target, "name")
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      let target_name = match target_name_val {
        String(s) => s
        _ => ""
      }
      self.set_function_name(bound, "bound " + target_name)
      bound
    }
    "Generator.prototype.next" => {
      match self.get_generator_id(this_arg) {
        Some(gen_id) => self.generator_next(gen_id)
        None =>
          self.set_error_kind("TypeError", "Generator.prototype.next called on non-generator")
      }
    }
    "Array" => {
      if args.length() == 0 {
        js_new_array()
      } else if args.length() == 1 {
        match args[0] {
          Number(n) => {
            let len = n.to_int()
            let arr = js_new_array()
            if len > 0 {
              let _ = js_set_prop(arr, "length", Number(n))
            }
            arr
          }
          _ => js_array_from([args[0]])
        }
      } else {
        let items : Array[JSValue] = []
        for item in args {
          items.push(item)
        }
        js_array_from(items)
      }
    }
    "Array.isArray" =>
      if args.length() > 0 {
        match args[0] {
          Array(_) => Bool(true)
          _ => Bool(false)
        }
      } else {
        Bool(false)
      }
    "Date" => {
      match this_arg {
        Object(_) => {
          let _ = js_set_prop(this_arg, "__class", String("Date"))
          this_arg
        }
        _ => String("Date")
      }
    }
    "Symbol" => {
      if args.length() > 0 {
        String("Symbol(" + args[0].to_js_string() + ")")
      } else {
        String("Symbol()")
      }
    }
    "Boolean" =>
      if args.length() > 0 {
        let prim = JSValue::Bool(args[0].to_boolean())
        let bool_ctor = self.global_env.get("Boolean")
        let bool_proto = js_get_prop(bool_ctor, "prototype")
        let is_ctor = match self.get_proto(this_arg) {
          Some(p) =>
            match js_strict_eq(p, bool_proto) {
              Bool(true) => true
              _ => false
            }
          None => false
        }
        if is_ctor {
          let _ = js_set_prop(this_arg, "value", prim)
          this_arg
        } else {
          prim
        }
      } else {
        let prim = JSValue::Bool(false)
        let bool_ctor = self.global_env.get("Boolean")
        let bool_proto = js_get_prop(bool_ctor, "prototype")
        let is_ctor = match self.get_proto(this_arg) {
          Some(p) =>
            match js_strict_eq(p, bool_proto) {
              Bool(true) => true
              _ => false
            }
          None => false
        }
        if is_ctor {
          let _ = js_set_prop(this_arg, "value", prim)
          this_arg
        } else {
          prim
        }
      }
    "Number" =>
      if args.length() > 0 {
        let prim = JSValue::Number(args[0].to_number())
        let num_ctor = self.global_env.get("Number")
        let num_proto = js_get_prop(num_ctor, "prototype")
        let is_ctor = match self.get_proto(this_arg) {
          Some(p) =>
            match js_strict_eq(p, num_proto) {
              Bool(true) => true
              _ => false
            }
          None => false
        }
        if is_ctor {
          let _ = js_set_prop(this_arg, "value", prim)
          this_arg
        } else {
          prim
        }
      } else {
        let prim = JSValue::Number(0.0)
        let num_ctor = self.global_env.get("Number")
        let num_proto = js_get_prop(num_ctor, "prototype")
        let is_ctor = match self.get_proto(this_arg) {
          Some(p) =>
            match js_strict_eq(p, num_proto) {
              Bool(true) => true
              _ => false
            }
          None => false
        }
        if is_ctor {
          let _ = js_set_prop(this_arg, "value", prim)
          this_arg
        } else {
          prim
        }
      }
    "String" =>
      if args.length() > 0 {
        let prim = JSValue::String(args[0].to_js_string())
        let str_ctor = self.global_env.get("String")
        let str_proto = js_get_prop(str_ctor, "prototype")
        let is_ctor = match self.get_proto(this_arg) {
          Some(p) =>
            match js_strict_eq(p, str_proto) {
              Bool(true) => true
              _ => false
            }
          None => false
        }
        if is_ctor {
          let _ = js_set_prop(this_arg, "value", prim)
          this_arg
        } else {
          prim
        }
      } else {
        let prim = JSValue::String("")
        let str_ctor = self.global_env.get("String")
        let str_proto = js_get_prop(str_ctor, "prototype")
        let is_ctor = match self.get_proto(this_arg) {
          Some(p) =>
            match js_strict_eq(p, str_proto) {
              Bool(true) => true
              _ => false
            }
          None => false
        }
        if is_ctor {
          let _ = js_set_prop(this_arg, "value", prim)
          this_arg
        } else {
          prim
        }
      }
    "String.fromCharCode" => {
      let mut out = ""
      for arg in args {
        let code = arg.to_number().to_int()
        let unit = code.to_uint16()
        let ch = unit.unsafe_to_char()
        out = out + ch.to_string()
      }
      String(out)
    }
    "String.fromCodePoint" => {
      let mut out = ""
      for arg in args {
        let code = arg.to_number().to_int()
        if code < 0 || code > 0x10ffff {
          return self.set_error_kind("RangeError", "Invalid code point")
        }
        let ch = code.unsafe_to_char()
        out = out + ch.to_string()
      }
      String(out)
    }
    "RegExp" => {
      let pattern_val = if args.length() > 0 { args[0] } else { String("") }
      let flags = if args.length() > 1 { args[1].to_js_string() } else { "" }
      if is_regexp(pattern_val) && flags == "" {
        pattern_val
      } else {
        let pattern = pattern_val.to_js_string()
        self.make_regexp(pattern, flags)
      }
    }
    "RegExp.prototype.exec" => {
      if not(is_regexp(this_arg)) {
        return self.set_error_kind("TypeError", "RegExp.prototype.exec called on non-RegExp")
      }
      let input = if args.length() > 0 { self.to_string_value(args[0]) } else { "" }
      let pattern = regexp_source(this_arg)
      let flags = regexp_flags(this_arg)
      let mut last_index = 0
      if regexp_has_global(flags) {
        match js_get_prop(this_arg, "lastIndex") {
          Number(n) => last_index = n.to_int()
          _ => last_index = 0
        }
      }
      match regexp_exec_groups(pattern, flags, input, last_index) {
        None => {
          let _ = js_set_prop(this_arg, "lastIndex", Number(0.0))
          Null
        }
        Some((start, end, groups)) => {
          let arr = js_array_from(groups)
          let _ = js_set_prop(arr, "index", Number(start.to_double()))
          let _ = js_set_prop(arr, "input", String(input))
          let _ = js_set_prop(this_arg, "lastIndex", Number(end.to_double()))
          arr
        }
      }
    }
    "RegExp.prototype.test" => {
      if not(is_regexp(this_arg)) {
        return self.set_error_kind("TypeError", "RegExp.prototype.test called on non-RegExp")
      }
      let input = if args.length() > 0 { self.to_string_value(args[0]) } else { "" }
      let pattern = regexp_source(this_arg)
      let flags = regexp_flags(this_arg)
      let mut last_index = 0
      if regexp_has_global(flags) {
        match js_get_prop(this_arg, "lastIndex") {
          Number(n) => last_index = n.to_int()
          _ => last_index = 0
        }
      }
      match regexp_first_match(pattern, flags, input, last_index) {
        None => {
          let _ = js_set_prop(this_arg, "lastIndex", Number(0.0))
          Bool(false)
        }
        Some((_start, end)) => {
          let _ = js_set_prop(this_arg, "lastIndex", Number(end.to_double()))
          Bool(true)
        }
      }
    }
    "console.log" => {
      let parts : Array[String] = []
      for arg in args {
        parts.push(arg.to_js_string())
      }
      println(parts.join(" "))
      Undefined
    }
    "eval" => {
      let src = if args.length() > 0 { args[0].to_js_string() } else { "" }
      let wrapped = "function main() {\n" + src + "\n}"
      let result = try {
        let parser = @parser.Parser::from_source(wrapped)
        let module_ = parser.parse_module()
        self.run_module(module_)
      } catch {
        @parser.ParseError::ParseError(msg) => {
          let _ = self.set_error_kind("SyntaxError", msg)
          Undefined
        }
      }
      result
    }
    "Reflect.construct" => {
      if args.length() == 0 {
        Undefined
      } else {
        let target = args[0]
        let new_target = if args.length() > 2 { args[2] } else { target }
        let call_args : Array[JSValue] = []
        if args.length() > 1 {
          match args[1] {
            Array(arr) =>
              for item in arr.items {
                call_args.push(item)
              }
            _ => ()
          }
        }
        match target {
          Function(closure) =>
            match closure.body {
              Native("Function") => self.call_native("Function", Undefined, call_args)
              _ => self.construct_with(target, new_target, call_args)
            }
          _ => Undefined
        }
      }
    }
    "Math.floor" =>
      if args.length() > 0 {
        Number(args[0].to_number().floor())
      } else {
        Number(js_nan)
      }
    "Math.ceil" =>
      if args.length() > 0 {
        Number(args[0].to_number().ceil())
      } else {
        Number(js_nan)
      }
    "Math.abs" =>
      if args.length() > 0 {
        Number(args[0].to_number().abs())
      } else {
        Number(js_nan)
      }
    "Math.sqrt" =>
      if args.length() > 0 {
        Number(args[0].to_number().sqrt())
      } else {
        Number(js_nan)
      }
    "Math.cos" =>
      if args.length() > 0 {
        Number(@math.cos(args[0].to_number()))
      } else {
        Number(js_nan)
      }
    "Math.sin" =>
      if args.length() > 0 {
        Number(@math.sin(args[0].to_number()))
      } else {
        Number(js_nan)
      }
    "Math.tan" =>
      if args.length() > 0 {
        Number(@math.tan(args[0].to_number()))
      } else {
        Number(js_nan)
      }
    "Math.exp" =>
      if args.length() > 0 {
        Number(@math.exp(args[0].to_number()))
      } else {
        Number(js_nan)
      }
    "Math.log" =>
      if args.length() > 0 {
        Number(@math.ln(args[0].to_number()))
      } else {
        Number(js_nan)
      }
    "Math.min" =>
      if args.length() == 0 {
        Number(1.0 / 0.0)
      } else if args.length() == 1 {
        Number(args[0].to_number())
      } else {
        let mut min_val = args[0].to_number()
        if min_val.is_nan() {
          return Number(min_val)
        }
        for i in 1..<args.length() {
          let val = args[i].to_number()
          if val.is_nan() {
            return Number(val)
          }
          if val < min_val {
            min_val = val
          }
        }
        Number(min_val)
      }
    "Math.max" =>
      if args.length() == 0 {
        Number(-1.0 / 0.0)
      } else if args.length() == 1 {
        Number(args[0].to_number())
      } else {
        let mut max_val = args[0].to_number()
        if max_val.is_nan() {
          return Number(max_val)
        }
        for i in 1..<args.length() {
          let val = args[i].to_number()
          if val.is_nan() {
            return Number(val)
          }
          if val > max_val {
            max_val = val
          }
        }
        Number(max_val)
      }
    "Math.round" =>
      if args.length() > 0 {
        Number(args[0].to_number().round())
      } else {
        Number(js_nan)
      }
    "Math.random" =>
      // TODO: implementation
      Number(0.5)
    // test262 harness functions
    "print" => {
      let parts : Array[String] = []
      for arg in args {
        parts.push(arg.to_js_string())
      }
      println(parts.join(" "))
      Undefined
    }
    "assert" =>
      if args.length() > 0 {
        let condition = args[0].to_boolean()
        if condition {
          Undefined
        } else {
          let msg = if args.length() > 1 {
            args[1].to_js_string()
          } else {
            "Assertion failed"
          }
          self.set_error(msg)
        }
      } else {
        Undefined
      }
    "assert.sameValue" =>
      if args.length() >= 2 {
        let actual = args[0]
        let expected = args[1]
        let result = assert_same_value(
          actual,
          expected,
          if args.length() > 2 { Some(args[2].to_js_string()) } else { None },
        )
        match result {
          Success => Undefined
          Failure(msg) => self.set_error(msg)
        }
      } else {
        Undefined
      }
    "assert.notSameValue" =>
      if args.length() >= 2 {
        let actual = args[0]
        let unexpected = args[1]
        let result = assert_not_same_value(
          actual,
          unexpected,
          if args.length() > 2 { Some(args[2].to_js_string()) } else { None },
        )
        match result {
          Success => Undefined
          Failure(msg) => self.set_error(msg)
        }
      } else {
        Undefined
      }
    "assert.compareArray" =>
      if args.length() >= 2 {
        let actual = args[0]
        let expected = args[1]
        let result = compare_array(
          actual,
          expected,
          if args.length() > 2 { Some(args[2].to_js_string()) } else { None },
        )
        match result {
          Success => Undefined
          Failure(msg) => self.set_error(msg)
        }
      } else {
        Undefined
      }
    "assert.throws" => {
      if args.length() < 2 {
        return self.set_error("assert.throws requires 2 args")
      }
      let expected = args[0]
      let thunk = args[1]
      match thunk {
        Function(_) => ()
        _ => return self.set_error_kind("TypeError", "assert.throws requires a function")
      }
      let _ = self.take_error()
      let _ = self.call_function(thunk, Undefined, [])
      match self.take_error() {
        None => self.set_error("Expected an error to be thrown")
        Some(e) => {
          let expected_name = js_get_prop(expected, "name")
          let actual_name = js_get_prop(e, "name")
          match (expected_name, actual_name) {
            (String(en), String(an)) =>
              if en == an {
                Undefined
              } else {
                self.set_error("Expected " + en + " but got " + an)
              }
            _ => Undefined
          }
        }
      }
    }
    "$DONOTEVALUATE" => {
      // This function should never be called in a passing test
      self.set_error("$DONOTEVALUATE was called")
    }
    "$ERROR" => {
      let msg = if args.length() > 0 {
        args[0].to_js_string()
      } else {
        "$ERROR"
      }
      self.set_error(msg)
    }
    "$DONE" =>
      if args.length() > 0 {
        let err = args[0]
        if !err.is_undefined() {
          self.set_error("Async test failed: " + err.to_js_string())
        } else {
          Undefined
        }
      } else {
        Undefined
      }
    "$262.evalScript" =>
      if args.length() > 0 {
        let code = args[0].to_js_string()
        self.run(code) catch {
          _ => {
            let wrapped = "function main() {\n" + code + "\n}"
            self.run(wrapped) catch {
              e2 => {
                let _ = self.set_error("$262.evalScript parse error: \{e2}")
                Undefined
              }
            }
          }
        }
      } else {
        Undefined
      }
    "$262.createRealm" => {
      let realm = self.new_object()
      let global_obj = self.global_env.get("globalThis")
      let _ = js_set_prop(realm, "global", global_obj)
      realm
    }
    _ => Undefined
  }
}

///|
// / newcreate
fn JSInterpreter::new_instance(
  self : JSInterpreter,
  class_name : String,
  args : Array[JSValue],
  env : JSEnv,
) -> JSValue {
  match class_name {
    "Test262Error" => {
      let msg = if args.length() > 0 {
        args[0].to_js_string()
      } else {
        ""
      }
      let obj = self.new_object()
      let _ = js_set_prop(obj, "name", JSValue::String("Test262Error"))
      let _ = js_set_prop(obj, "message", JSValue::String(msg))
      obj
    }
    "Function" => self.call_native("Function", Undefined, args)
    "Boolean" => {
      let val =
        if args.length() > 0 {
          JSValue::Bool(args[0].to_boolean())
        } else {
          JSValue::Bool(false)
        }
      let ctor = env.get("Boolean")
      let proto = js_get_prop(ctor, "prototype")
      let obj = match proto {
        Object(_) | Function(_) => js_new_object_with_proto(Some(proto))
        _ => self.new_object()
      }
      let _ = js_set_prop(obj, "value", val)
      obj
    }
    "Number" => {
      let val =
        if args.length() > 0 {
          JSValue::Number(args[0].to_number())
        } else {
          JSValue::Number(0.0)
        }
      let ctor = env.get("Number")
      let proto = js_get_prop(ctor, "prototype")
      let obj = match proto {
        Object(_) | Function(_) => js_new_object_with_proto(Some(proto))
        _ => self.new_object()
      }
      let _ = js_set_prop(obj, "value", val)
      obj
    }
    "String" => {
      let val =
        if args.length() > 0 {
          JSValue::String(args[0].to_js_string())
        } else {
          JSValue::String("")
        }
      let ctor = env.get("String")
      let proto = js_get_prop(ctor, "prototype")
      let obj = match proto {
        Object(_) | Function(_) => js_new_object_with_proto(Some(proto))
        _ => self.new_object()
      }
      let _ = js_set_prop(obj, "value", val)
      obj
    }
    "Array" =>
      if args.length() == 1 {
        match args[0] {
          Number(n) => {
            let len = n.to_int()
            let arr : Array[JSValue] = []
            for _ in 0..<len {
              arr.push(Undefined)
            }
            js_array_from(arr)
          }
          _ => js_array_from(args.copy())
        }
      } else {
        js_array_from(args.copy())
      }
    "RegExp" => {
      let pattern_val = if args.length() > 0 { args[0] } else { String("") }
      let flags = if args.length() > 1 { args[1].to_js_string() } else { "" }
      if is_regexp(pattern_val) && flags == "" {
        pattern_val
      } else {
        let pattern = pattern_val.to_js_string()
        self.make_regexp(pattern, flags)
      }
    }
    "Object" => self.new_object()
    _ => {
      // lookup
      let ctor = env.get(class_name)
      match ctor {
        Function(_) => self.construct_with(ctor, ctor, args)
        _ => self.new_object()
      }
    }
  }
}

///|
// / run
pub fn JSInterpreter::run_module(
  self : JSInterpreter,
  module_ : @parser.TsModule,
) -> JSValue {
  // function
  for func in module_.funcs {
    let param_names : Array[String] = []
    for param in func.params {
      param_names.push(param.name)
    }
    let closure = JSValue::Function({
      id: fresh_function_id(),
      params: param_names,
      body: Ast(func),
      env: self.global_env,
      is_arrow: false,
      is_strict: self.is_strict_body(func.body, false),
      is_generator: func.is_generator,
      props: [],
      object_proto: Some(self.function_proto),
    })
    self.set_function_length(closure, param_names.length().to_double())
    self.set_function_name(closure, func.name)
    let proto = self.new_object()
    let _ = js_set_prop(proto, "constructor", closure)
    let _ = js_define_data_prop(closure, "prototype", proto, true, false, true)
    self.global_env.define_var(func.name, closure)
  }

  // mainfunctionrun
  let main_func = self.global_env.get("main")
  match main_func {
    Function(closure) =>
      match closure.body {
        Ast(func_def) => {
          if closure.is_strict && not(self.global_env.has("__strict__")) {
            self.global_env.define_var("__strict__", Bool(true))
          }
          self.hoist_block(func_def.body, self.global_env)
          match self.exec_block(func_def.body, self.global_env) {
            Some(val) => val
            None => Undefined
          }
        }
        _ => self.call_function(main_func, self.global_env.get("globalThis"), [])
      }
    _ => Undefined
  }
}

///|
// / run
pub fn JSInterpreter::run(
  self : JSInterpreter,
  source : String,
) -> JSValue raise @parser.ParseError {
  let parser = @parser.Parser::from_source(source)
  let module_ = parser.parse_module()
  self.run_module(module_)
}
