// JSValue インタプリタ
// ASTを直接解釈実行する

///|
/// インタプリタ
pub struct JSInterpreter {
  global_env : JSEnv
  mut last_error : JSValue?
  mut steps : Int
  step_limit : Int
  object_proto : JSValue
  function_proto : JSValue
}

///|
/// インタプリタを作成
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
  }
  interp.install_builtins()
  interp
}

///|
/// ネイティブ関数を作成
fn JSInterpreter::make_native(self : JSInterpreter, name : String) -> JSValue {
  JSValue::Function({
    id: fresh_function_id(),
    params: [],
    body: Native(name),
    env: self.global_env,
    is_arrow: false,
    is_strict: false,
    props: [],
    object_proto: Some(self.function_proto),
  })
}

///|
/// 関数の length プロパティを設定
fn JSInterpreter::set_function_length(
  _self : JSInterpreter,
  func : JSValue,
  len : Double,
) -> Unit {
  let _ = js_define_data_prop(func, "length", Number(len), false, false, true)
}

///|
/// 関数の name プロパティを設定
fn JSInterpreter::set_function_name(
  _self : JSInterpreter,
  func : JSValue,
  name : String,
) -> Unit {
  let _ = js_define_data_prop(func, "name", String(name), false, false, true)
}

///|
/// データディスクリプタを作成
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
/// アクセサディスクリプタを作成
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
/// bound 関数の length 計算
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
/// strict mode 判定
fn JSInterpreter::is_strict_body(
  self : JSInterpreter,
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
/// エラーオブジェクトを作成して保持
fn JSInterpreter::set_error(self : JSInterpreter, message : String) -> JSValue {
  self.set_error_kind("Error", message)
}

///|
/// エラー種別付きのエラーオブジェクトを作成して保持
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
/// エラーオブジェクトを作成
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
/// 実行ステップをカウントして暴走を抑制
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
/// エラーを取得してクリア
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
/// エラーを覗く（クリアしない）
fn JSInterpreter::peek_error(self : JSInterpreter) -> JSValue? {
  self.last_error
}

///|
/// Object.prototype を持つオブジェクトを作成
fn JSInterpreter::new_object(self : JSInterpreter) -> JSValue {
  js_new_object_with_proto(Some(self.object_proto))
}

///|
/// グローバル組み込みをセットアップ
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
  self.global_env.define("Object", object_ctor)
  let _ = js_set_prop(global_obj, "Object", object_ctor)

  // console
  let console = self.new_object()
  let _ = js_set_prop(console, "log", self.make_native("console.log"))
  self.global_env.define("console", console)
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
  self.global_env.define("Math", math)
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
  self.global_env.define("Function", function_ctor)
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
  self.global_env.define("Boolean", boolean_ctor)
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
  self.global_env.define("Number", number_ctor)
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
  self.global_env.define("String", string_ctor)
  let _ = js_set_prop(global_obj, "String", string_ctor)

  // Array
  let array_proto = self.new_object()
  let array_ctor = self.make_native("Array")
  self.set_function_length(array_ctor, 1.0)
  self.set_function_name(array_ctor, "Array")
  let _ = js_define_data_prop(array_ctor, "prototype", array_proto, true, false, true)
  let _ = js_set_prop(array_proto, "constructor", array_ctor)
  let is_array_fn = self.make_native("Array.isArray")
  self.set_function_length(is_array_fn, 1.0)
  let _ = js_set_prop(array_ctor, "isArray", is_array_fn)
  self.global_env.define("Array", array_ctor)
  let _ = js_set_prop(global_obj, "Array", array_ctor)

  // Date
  let date_proto = self.new_object()
  let date_ctor = self.make_native("Date")
  self.set_function_length(date_ctor, 7.0)
  self.set_function_name(date_ctor, "Date")
  let _ = js_define_data_prop(date_ctor, "prototype", date_proto, true, false, true)
  let _ = js_set_prop(date_proto, "constructor", date_ctor)
  self.global_env.define("Date", date_ctor)
  let _ = js_set_prop(global_obj, "Date", date_ctor)

  // Errors (minimal)
  let syntax_ctor = self.make_native("SyntaxError")
  self.set_function_name(syntax_ctor, "SyntaxError")
  let _ = js_define_data_prop(syntax_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define("SyntaxError", syntax_ctor)
  let _ = js_set_prop(global_obj, "SyntaxError", syntax_ctor)
  let type_ctor = self.make_native("TypeError")
  self.set_function_name(type_ctor, "TypeError")
  let _ = js_define_data_prop(type_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define("TypeError", type_ctor)
  let _ = js_set_prop(global_obj, "TypeError", type_ctor)
  let ref_ctor = self.make_native("ReferenceError")
  self.set_function_name(ref_ctor, "ReferenceError")
  let _ = js_define_data_prop(ref_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define("ReferenceError", ref_ctor)
  let _ = js_set_prop(global_obj, "ReferenceError", ref_ctor)
  let test262_ctor = self.make_native("Test262Error")
  self.set_function_name(test262_ctor, "Test262Error")
  let _ = js_define_data_prop(test262_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define("Test262Error", test262_ctor)
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
  self.global_env.define("assert", assert_obj)
  let _ = js_set_prop(global_obj, "assert", assert_obj)

  // print
  let print_fn = self.make_native("print")
  self.global_env.define("print", print_fn)
  let _ = js_set_prop(global_obj, "print", print_fn)

  // eval
  let eval_fn = self.make_native("eval")
  self.set_function_length(eval_fn, 1.0)
  self.global_env.define("eval", eval_fn)
  let _ = js_set_prop(global_obj, "eval", eval_fn)

  // $DONOTEVALUATE
  let donotevaluate_fn = self.make_native("$DONOTEVALUATE")
  self.global_env.define("$DONOTEVALUATE", donotevaluate_fn)
  let _ = js_set_prop(global_obj, "$DONOTEVALUATE", donotevaluate_fn)

  // $ERROR / $DONE
  let error_fn = self.make_native("$ERROR")
  self.global_env.define("$ERROR", error_fn)
  let _ = js_set_prop(global_obj, "$ERROR", error_fn)
  let done_fn = self.make_native("$DONE")
  self.global_env.define("$DONE", done_fn)
  let _ = js_set_prop(global_obj, "$DONE", done_fn)

  // $262
  let t262 = self.new_object()
  let _ = js_set_prop(t262, "global", global_obj)
  let _ = js_set_prop(t262, "evalScript", self.make_native("$262.evalScript"))
  let _ = js_set_prop(t262, "createRealm", self.make_native("$262.createRealm"))
  self.global_env.define("$262", t262)
  let _ = js_set_prop(global_obj, "$262", t262)

  // globalThis / global
  self.global_env.define("globalThis", global_obj)
  self.global_env.define("global", global_obj)
  self.global_env.define("this", global_obj)
  self.global_env.define("undefined", Undefined)
  let _ = js_set_prop(global_obj, "undefined", Undefined)
  let nan = JSValue::Number(0.0 / 0.0)
  let inf = JSValue::Number(1.0 / 0.0)
  self.global_env.define("NaN", nan)
  self.global_env.define("Infinity", inf)
  let _ = js_set_prop(global_obj, "NaN", nan)
  let _ = js_set_prop(global_obj, "Infinity", inf)

  // Symbol
  let symbol_fn = self.make_native("Symbol")
  self.set_function_length(symbol_fn, 0.0)
  let _ = js_set_prop(symbol_fn, "hasInstance", String("@@hasInstance"))
  self.global_env.define("Symbol", symbol_fn)
  let _ = js_set_prop(global_obj, "Symbol", symbol_fn)

  // Reflect
  let reflect = self.new_object()
  let _ = js_set_prop(reflect, "construct", self.make_native("Reflect.construct"))
  self.global_env.define("Reflect", reflect)
  let _ = js_set_prop(global_obj, "Reflect", reflect)
}

///|
/// 式を評価
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
    @parser.TsExpr::Var(name) =>
      if env.has(name) {
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
          // 短絡評価: lvalがfalsyならlval、そうでなければrval
          if lval.to_boolean() {
            rval
          } else {
            lval
          }
        @parser.TsBinOp::Or =>
          // 短絡評価: lvalがtruthyならlval、そうでなければrval
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
          // ++x: インクリメントして新しい値を返す
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
          // --x: デクリメントして新しい値を返す
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
          // x++: 古い値を返してからインクリメント
          match operand {
            @parser.TsExpr::Var(name) => {
              let old_val = env.get(name)
              let new_val = js_add(old_val, Number(1.0))
              let _ = env.set(name, new_val)
              old_val
            }
            _ => {
              let val = self.eval_expr(operand, env)
              val // 副作用なし
            }
          }
        @parser.TsUnaryOp::PostDec =>
          // x--: 古い値を返してからデクリメント
          match operand {
            @parser.TsExpr::Var(name) => {
              let old_val = env.get(name)
              let new_val = js_sub(old_val, Number(1.0))
              let _ = env.set(name, new_val)
              old_val
            }
            _ => {
              let val = self.eval_expr(operand, env)
              val // 副作用なし
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
      // 関数を環境から取得
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
      let obj = self.eval_expr(obj_expr, env)
      self.get_prop_value(obj, prop)
    }
    @parser.TsExpr::AssignExpr(name, val_expr) => {
      let val = self.eval_expr(val_expr, env)
      if not(env.set(name, val)) {
        // 変数が見つからない場合はグローバルに定義
        self.global_env.define(name, val)
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
            })
          @parser.TsArrowBody::ArrowBlock(block) =>
            Ast({
              name: "<arrow>",
              params,
              return_type: @parser.TsType::Any,
              body: block,
            })
        },
        env,
        is_arrow: true,
        is_strict: false,
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
        props: [],
        object_proto: Some(self.function_proto),
      })
      self.set_function_length(closure, param_names.length().to_double())
      let proto = self.new_object()
      let _ = js_set_prop(proto, "constructor", closure)
      let _ = js_define_data_prop(closure, "prototype", proto, true, false, true)
      closure
    }
  }
}

///|
/// 文を実行（戻り値はReturnの場合のみSome）
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
      env.define(name, val)
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
      if not(env.set(name, val)) {
        self.global_env.define(name, val)
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
                  catch_env.define(name, err)
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
      // 初期化
      match init {
        Some(init_stmt) => {
          match self.exec_stmt(init_stmt, env) {
            Some(val) => return Some(val)
            None => ()
          }

        }
        None => ()
      }
      // ループ
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
            // 更新を実行してから次のイテレーションへ
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
        // 更新
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
      let new_val = match op {
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
            env.define(var_name, item)
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
          // 文字列のイテレーション
          let mut idx = 0
          while idx < s.length() {
            let char_str = try { s[idx:idx + 1].to_string() } catch { _ => "" }
            env.define(var_name, String(char_str))
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
        _ => () // イテレート不可
      }
      None
    }
  }
}

///|
/// ブロックを実行
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
/// this バインディングの正規化
fn JSInterpreter::normalize_this(self : JSInterpreter, value : JSValue) -> JSValue {
  match value {
    Undefined | Null => self.global_env.get("globalThis")
    Bool(_) | Number(_) | String(_) => {
      let obj = self.new_object()
      let _ = js_set_prop(obj, "value", value)
      obj
    }
    _ => value
  }
}

///|
/// プロトタイプを取得
fn JSInterpreter::get_proto(self : JSInterpreter, value : JSValue) -> JSValue? {
  match value {
    Object(map) => map.prototype
    Function(closure) => closure.object_proto
    _ => None
  }
}

///|
/// プロパティ値を取得（アクセサ対応）
fn JSInterpreter::get_prop_value(self : JSInterpreter, obj : JSValue, key : String) -> JSValue {
  self.get_prop_value_with_receiver(obj, obj, key)
}

///|
/// レシーバ付きプロパティ取得
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
            Undefined
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
/// プロパティ値評価
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
/// own property 判定
fn JSInterpreter::has_own_prop(self : JSInterpreter, obj : JSValue, key : String) -> Bool {
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
/// enumerable 判定
fn JSInterpreter::is_enumerable(self : JSInterpreter, obj : JSValue, key : String) -> Bool {
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
/// Instanceof 判定
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
/// new-target を使ったインスタンス生成
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
/// プリミティブをラッパーオブジェクト化
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
/// ToPrimitive(+) 相当（Object は value / toString を試す）
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
/// JS の ToString 相当（Object は toString を呼ぶ）
fn JSInterpreter::to_string_value(self : JSInterpreter, value : JSValue) -> String {
  match value {
    Object(_) | Array(_) | Function(_) => {
      let prim = js_get_prop(value, "value")
      match prim {
        Undefined => ()
        _ => return prim.to_js_string()
      }
      let to_str = js_get_prop(value, "toString")
      match to_str {
        Function(_) => self.call_function(to_str, value, []).to_js_string()
        _ => value.to_js_string()
      }
    }
    _ => value.to_js_string()
  }
}

///|
/// 変数宣言の簡易ホイスト
fn JSInterpreter::hoist_stmt(self : JSInterpreter, stmt : @parser.TsStmt, env : JSEnv) -> Unit {
  match stmt {
    @parser.TsStmt::Let(name, _, _) | @parser.TsStmt::Const(name, _, _) =>
      if not(env.has(name)) {
        env.define(name, Undefined)
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
        env.define(name, Undefined)
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
/// 呼び出し可能かを判定
fn JSInterpreter::is_callable(self : JSInterpreter, value : JSValue) -> Bool {
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
/// constructor 判定
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
/// instanceof の簡易判定
fn JSInterpreter::instanceof(self : JSInterpreter, left : JSValue, right : JSValue) -> Bool {
  self.ordinary_has_instance(right, left)
}

///|
/// 関数を呼び出す
pub fn JSInterpreter::call_function(
  self : JSInterpreter,
  func : JSValue,
  this_arg : JSValue,
  args : Array[JSValue],
  new_target? : JSValue = Undefined,
) -> JSValue {
  match func {
    Function(closure) => {
      // 新しい環境を作成
      let call_env = js_new_env(Some(closure.env))
      if closure.is_strict {
        call_env.define("__strict__", Bool(true))
      }
      if not(closure.is_arrow) {
        if closure.is_strict {
          call_env.define("this", this_arg)
        } else {
          let bound_this = match this_arg {
            Undefined | Null => closure.env.get("globalThis")
            Bool(_) | Number(_) | String(_) => self.wrap_primitive(closure.env, this_arg)
            _ => this_arg
          }
          call_env.define("this", bound_this)
        }
      }

      let new_meta = self.new_object()
      let _ = js_set_prop(new_meta, "target", new_target)
      call_env.define("new", new_meta)

      let args_obj = js_array_from(args)
      call_env.define("arguments", args_obj)

      // 引数をバインド
      for i, param in closure.params {
        let val = if i < args.length() { args[i] } else { Undefined }
        call_env.define(param, val)
      }

      // 本体を実行
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
        Compiled(_) => Undefined // TODO
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
/// メソッドを呼び出す
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
      // オブジェクトのメソッドを検索
      let func = self.get_prop_value(Object(map), method_name)
      self.call_function(func, obj, args)
    }
    _ => Undefined
  }
}

///|
/// 関数メソッド (call/apply/bind)
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
/// 文字列メソッド
fn JSInterpreter::string_method(
  _self : JSInterpreter,
  s : String,
  method_name : String,
  args : Array[JSValue],
) -> JSValue {
  match method_name {
    "length" => Number(s.length().to_double())
    "charAt" => {
      let idx = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      if idx >= 0 && idx < s.length() {
        String(try { s[idx:idx + 1].to_string() } catch { _ => "" })
      } else {
        String("")
      }
    }
    "indexOf" => {
      let search_str = if args.length() > 0 {
        args[0].to_js_string()
      } else {
        ""
      }
      let start_idx = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      // 手動実装: s.index_of() は存在しないのでループで検索
      let mut idx = -1
      if start_idx < s.length() && search_str.length() > 0 {
        let search_len = search_str.length()
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
    "split" => {
      let sep = if args.length() > 0 { args[0].to_js_string() } else { "" }
      let parts = s.split(sep)
      let result : Array[JSValue] = []
      for part in parts {
        result.push(String(part.to_string()))
      }
      js_array_from(result)
    }
    "replace" => {
      let from = if args.length() > 0 { args[0].to_js_string() } else { "" }
      let to = if args.length() > 1 { args[1].to_js_string() } else { "" }
      String(s.replace(old=from, new=to))
    }
    "trim" => {
      let trim_result = s.trim()
      String(trim_result.to_string())
    }
    "substring" => {
      let start = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      let end = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        s.length()
      }
      String(try { s[start:end].to_string() } catch { _ => "" })
    }
    "toUpperCase" => String(s.to_upper())
    "toLowerCase" => String(s.to_lower())
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
/// 配列メソッド
fn JSInterpreter::array_method(
  self : JSInterpreter,
  arr : JSArray,
  method_name : String,
  args : Array[JSValue],
) -> JSValue {
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
        // Remove first element by creating new array
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
    "join" => {
      let sep = if args.length() > 0 { args[0].to_js_string() } else { "," }
      let parts : Array[String] = []
      for item in arr.items {
        parts.push(item.to_js_string())
      }
      JSValue::String(parts.join(sep))
    }
    "indexOf" => {
      if args.length() > 0 {
        let target = args[0]
        for i, item in arr.items {
          match js_strict_eq(item, target) {
            JSValue::Bool(true) => return JSValue::Number(i.to_double())
            _ => ()
          }
        }
      }
      JSValue::Number(-1.0)
    }
    "includes" => {
      if args.length() > 0 {
        let target = args[0]
        for _, item in arr.items {
          match js_strict_eq(item, target) {
            Bool(true) => return JSValue::Bool(true)
            _ => ()
          }
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
            let len = arr.items.length()
            let mut i = 0
            while i < len {
              if i < arr.items.length() {
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
    "filter" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let result : Array[JSValue] = []
            let len = arr.items.length()
            let mut i = 0
            while i < len {
              if i < arr.items.length() {
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
            let initial_value = if args.length() > 1 {
              args[1]
            } else {
              Undefined
            }
            let mut accumulator = initial_value
            let mut start_index = 0
            let len = arr.items.length()
            let eq_result = js_strict_eq(initial_value, Undefined)
            let is_undefined = match eq_result {
              JSValue::Bool(true) => true
              JSValue::Bool(false) => false
              _ => false
            }
            if is_undefined && len > 0 {
              accumulator = arr.items[0]
              start_index = 1
            }
            let mut i = start_index
            while i < len {
              if i < arr.items.length() {
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
              }
              i += 1
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
            let len = arr.items.length()
            let mut i = 0
            while i < len {
              if i < arr.items.length() {
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
    "find" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let len = arr.items.length()
            let mut i = 0
            while i < len {
              if i < arr.items.length() {
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
    "slice" =>
      if args.length() > 0 {
        match args[0] {
          Array(arr) => {
            let mut start = if args.length() > 1 {
              match args[1] {
                JSValue::Number(n) => {
                  let si = n.to_int()
                  if si < 0 {
                    let len = arr.items.length()
                    if -si > len {
                      0
                    } else {
                      len + si
                    }
                  } else {
                    si
                  }
                }
                _ => 0
              }
            } else {
              0
            }
            let mut end = if args.length() > 2 {
              match args[2] {
                JSValue::Number(n) => {
                  let ei = n.to_int()
                  if ei < 0 {
                    let len = arr.items.length()
                    if -ei > len {
                      0
                    } else {
                      len + ei
                    }
                  } else {
                    ei
                  }
                }
                _ => arr.items.length()
              }
            } else {
              arr.items.length()
            }
            let len = arr.items.length()
            if start < 0 {
              start = 0
            }
            if end < 0 {
              end = 0
            }
            if start > len {
              start = len
            }
            if end > len {
              end = len
            }
            if start > end {
              let temp = start
              start = end
              end = temp
            }
            let result : Array[JSValue] = []
            for i in start..<end {
              result.push(arr.items[i])
            }
            js_array_from(result)
          }
          _ => js_new_array()
        }
      } else {
        js_new_array()
      }
    "concat" =>
      if args.length() > 0 {
        match args[0] {
          Array(arr) => {
            let result : Array[JSValue] = arr.items.copy()
            if args.length() > 1 {
              match args[1] {
                Array(other_arr) =>
                  for item in other_arr.items {
                    result.push(item)
                  }
                _ => result.push(args[1])
              }
            }
            js_array_from(result)
          }
          _ => js_new_array()
        }
      } else {
        js_new_array()
      }
    "unshift" =>
      if args.length() > 0 {
        match args[0] {
          Array(arr) => {
            let new_arr : Array[JSValue] = []
            for i in 1..<args.length() {
              new_arr.push(args[i])
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
          _ => JSValue::Number(0)
        }
      } else {
        JSValue::Number(0)
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
        _ => {
          let _ = self.set_error_kind("SyntaxError", "Function parse error")
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
        _ => {
          let _ = self.set_error_kind("SyntaxError", "eval parse error")
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
    "Math.min" =>
      if args.length() == 0 {
        Number(1.0e308) // Infinity
      } else if args.length() == 1 {
        args[0]
      } else {
        let mut min_val = args[0].to_number()
        for i in 1..<args.length() {
          let val = args[i].to_number()
          if val < min_val {
            min_val = val
          }
        }
        Number(min_val)
      }
    "Math.max" =>
      if args.length() == 0 {
        Number(-1.0e308) // -Infinity
      } else if args.length() == 1 {
        args[0]
      } else {
        let mut max_val = args[0].to_number()
        for i in 1..<args.length() {
          let val = args[i].to_number()
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
      // TODO: 適切なランダム実装
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
/// newでインスタンスを作成
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
    "Object" => self.new_object()
    _ => {
      // カスタムクラスのコンストラクタを検索
      let ctor = env.get(class_name)
      match ctor {
        Function(_) => self.construct_with(ctor, ctor, args)
        _ => self.new_object()
      }
    }
  }
}

///|
/// モジュールを実行
pub fn JSInterpreter::run_module(
  self : JSInterpreter,
  module_ : @parser.TsModule,
) -> JSValue {
  // 関数を登録
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
      props: [],
      object_proto: Some(self.function_proto),
    })
    self.set_function_length(closure, param_names.length().to_double())
    let proto = self.new_object()
    let _ = js_set_prop(proto, "constructor", closure)
    let _ = js_define_data_prop(closure, "prototype", proto, true, false, true)
    self.global_env.define(func.name, closure)
  }

  // main関数があれば実行
  let main_func = self.global_env.get("main")
  match main_func {
    Function(closure) =>
      match closure.body {
        Ast(func_def) => {
          if closure.is_strict && not(self.global_env.has("__strict__")) {
            self.global_env.define("__strict__", Bool(true))
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
/// ソースコードを直接実行
pub fn JSInterpreter::run(
  self : JSInterpreter,
  source : String,
) -> JSValue raise @parser.ParseError {
  let parser = @parser.Parser::from_source(source)
  let module_ = parser.parse_module()
  self.run_module(module_)
}
