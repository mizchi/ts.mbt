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
    @parser.TsExpr::ArrayHole => Undefined
    @parser.TsExpr::Yield(_) => Undefined
    @parser.TsExpr::YieldStar(_) => Undefined
    @parser.TsExpr::Var(name) =>
      if name == "super" && env.has("__super_proto") {
        env.get("__super_proto")
      } else if env.is_uninitialized(name) {
        let _ = self.set_error_kind("ReferenceError", name + " is not defined")
        Undefined
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
      match op {
        @parser.TsBinOp::And => {
          let lval = self.eval_expr(left, env)
          if lval.to_boolean() {
            self.eval_expr(right, env)
          } else {
            lval
          }
        }
        @parser.TsBinOp::Or => {
          let lval = self.eval_expr(left, env)
          if lval.to_boolean() {
            lval
          } else {
            self.eval_expr(right, env)
          }
        }
        _ => {
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
          // handled above for short-circuit
          Undefined
        @parser.TsBinOp::Or =>
          // handled above for short-circuit
          Undefined
          }
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
              self.assign_ident(name, new_val, env)
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
              self.assign_ident(name, new_val, env)
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
              self.assign_ident(name, new_val, env)
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
              self.assign_ident(name, new_val, env)
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
        if args.length() == 1 {
          match args[0] {
            @parser.TsExpr::Var(rest_name) if rest_name == "__super_args__" => {
              let rest_val = self.eval_expr(args[0], env)
              match rest_val {
                Array(arr) => {
                  let mut i = 0
                  while i < arr.items.length() {
                    if i < arr.present.length() && arr.present[i] {
                      arg_values.push(arr.items[i])
                    }
                    i = i + 1
                  }
                }
                _ => arg_values.push(rest_val)
              }
            }
            _ =>
              for arg in args {
                arg_values.push(self.eval_expr(arg, env))
              }
          }
        } else {
          for arg in args {
            arg_values.push(self.eval_expr(arg, env))
          }
        }
        let new_target =
          match env.get("new") {
            Object(_) | Function(_) | Array(_) => js_get_prop(env.get("new"), "target")
            _ => Undefined
          }
        let _ = self.call_function(
          super_ctor,
          env.get("this"),
          arg_values,
          new_target=new_target,
        )
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
      let arr = js_new_array()
      let _ = js_set_prop(arr, "length", Number(elements.length().to_double()))
      for i, elem in elements {
        match elem {
          @parser.TsExpr::ArrayHole => ()
          _ => {
            let value = self.eval_expr(elem, env)
            let _ = js_set_prop(arr, i.to_string(), value)
          }
        }
      }
      arr
    }
    @parser.TsExpr::ObjectLit(fields) => {
      let props : Array[JSProp] = []
      fn find_prop_index(props : Array[JSProp], key : String) -> Int? {
        for i, prop in props {
          if prop.key == key {
            return Some(i)
          }
        }
        None
      }
      for field in fields {
        let (key, val_expr) = field
        if key.has_prefix("@@get:") || key.has_prefix("@@set:") {
          let is_get = key.has_prefix("@@get:")
          let real_key = (try { key[6:] } catch { _ => "" }).to_string()
          let func_val = self.eval_expr(val_expr, env)
          match find_prop_index(props, real_key) {
            Some(i) => {
              let existing = props[i]
              let next_get = if is_get { Some(func_val) } else { existing.get }
              let next_set = if is_get { existing.set } else { Some(func_val) }
              props[i] = {
                key: real_key,
                value: existing.value,
                writable: existing.writable,
                enumerable: existing.enumerable,
                configurable: existing.configurable,
                get: next_get,
                set: next_set,
              }
            }
            None => {
              props.push({
                key: real_key,
                value: Undefined,
                writable: true,
                enumerable: true,
                configurable: true,
                get: if is_get { Some(func_val) } else { None },
                set: if is_get { None } else { Some(func_val) },
              })
            }
          }
        } else {
          let value = self.eval_expr(val_expr, env)
          match find_prop_index(props, key) {
            Some(i) =>
              props[i] = {
                key,
                value,
                writable: true,
                enumerable: true,
                configurable: true,
                get: None,
                set: None,
              }
            None =>
              props.push({
                key,
                value,
                writable: true,
                enumerable: true,
                configurable: true,
                get: None,
                set: None,
              })
          }
        }
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
          self.assign_ident(name, new_val, env)
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
      self.assign_ident(name, val, env)
      val
    }
    @parser.TsExpr::AssignPattern(binding, val_expr) => {
      let val = self.eval_expr(val_expr, env)
      self.assign_pattern(binding, val, env)
      val
    }
    @parser.TsExpr::PropAssignExpr(obj_expr, prop, val_expr) => {
      let obj = self.eval_expr(obj_expr, env)
      let val = self.eval_expr(val_expr, env)
      self.set_prop_value(obj, prop, val)
      val
    }
    @parser.TsExpr::IndexAssignExpr(obj_expr, idx_expr, val_expr) => {
      let obj = self.eval_expr(obj_expr, env)
      let idx = self.eval_expr(idx_expr, env)
      let val = self.eval_expr(val_expr, env)
      match obj {
        Array(_) | Object(_) | Function(_) => {
          let key = idx.to_js_string()
          self.set_prop_value(obj, key, val)
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
fn JSInterpreter::eval_expr_gen(
  self : JSInterpreter,
  expr : @parser.TsExpr,
  env : JSEnv,
) -> GenValue {
  if not(expr_has_yield(expr)) {
    return GenValue::Value(self.eval_expr(expr, env))
  }
  match expr {
    @parser.TsExpr::Yield(opt) =>
      match opt {
        Some(inner) =>
          gen_bind(self.eval_expr_gen(inner, env), (yielded) =>
            GenValue::Yield(yielded, (sent) => GenValue::Value(sent))
          )
        None => GenValue::Yield(JSValue::Undefined, (sent) => GenValue::Value(sent))
      }
    @parser.TsExpr::YieldStar(inner) => self.eval_yield_star(inner, env)
    @parser.TsExpr::Seq(left, right) =>
      gen_bind(self.eval_expr_gen(left, env), (_unused) =>
        self.eval_expr_gen(right, env)
      )
    @parser.TsExpr::AssignExpr(name, value) =>
      gen_bind(self.eval_expr_gen(value, env), (val) => {
        self.assign_ident(name, val, env)
        GenValue::Value(val)
      })
    @parser.TsExpr::AssignPattern(binding, value) =>
      gen_bind(self.eval_expr_gen(value, env), (val) =>
        gen_bind(self.assign_pattern_gen(binding, val, env), (_unused) =>
          GenValue::Value(val)
        )
      )
    @parser.TsExpr::PropAccess(obj_expr, prop) =>
      gen_bind(self.eval_expr_gen(obj_expr, env), (obj) =>
        GenValue::Value(self.get_prop_value(obj, prop))
      )
    @parser.TsExpr::IndexAccess(obj_expr, idx_expr) =>
      gen_bind(self.eval_expr_gen(obj_expr, env), (obj) =>
        gen_bind(self.eval_expr_gen(idx_expr, env), (idx) => {
          let key = idx.to_js_string()
          GenValue::Value(self.get_prop_value(obj, key))
        })
      )
    @parser.TsExpr::PropAssignExpr(obj_expr, prop, value_expr) =>
      gen_bind(self.eval_expr_gen(obj_expr, env), (obj) =>
        gen_bind(self.eval_expr_gen(value_expr, env), (val) => {
          self.set_prop_value(obj, prop, val)
          GenValue::Value(val)
        })
      )
    @parser.TsExpr::IndexAssignExpr(obj_expr, idx_expr, value_expr) =>
      gen_bind(self.eval_expr_gen(obj_expr, env), (obj) =>
        gen_bind(self.eval_expr_gen(idx_expr, env), (idx) =>
          gen_bind(self.eval_expr_gen(value_expr, env), (val) => {
            let key = idx.to_js_string()
            self.set_prop_value(obj, key, val)
            GenValue::Value(val)
          })
        )
      )
    _ => GenValue::Value(self.eval_expr(expr, env))
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
      if self.eval_has_decl_conflict(block, env) {
        return JSValue::Undefined
      }
      self.exec_eval_block(block, env)
    }
  }
}

///|
fn env_has_local_binding(env : JSEnv, name : String) -> Bool {
  let len = env.bindings.length()
  let mut i = len - 1
  while i >= 0 {
    if env.bindings[i].name == name {
      return true
    }
    i -= 1
  }
  false
}

///|
fn get_local_param_names(env : JSEnv) -> Array[String] {
  let names : Array[String] = []
  for binding in env.bindings {
    if binding.name != "__param_names__" {
      continue
    }
    match binding.value {
      Array(arr) =>
        for item in arr.items {
          match item {
            String(s) => names.push(s)
            _ => ()
          }
        }
      _ => ()
    }
    break
  }
  names
}

///|
fn collect_decl_names_from_stmt(
  stmt : @parser.TsStmt,
  names : Array[String],
) -> Unit {
  match stmt {
    @parser.TsStmt::Let(name, _, _) | @parser.TsStmt::Const(name, _, _) =>
      names.push(name)
    @parser.TsStmt::Block(block) =>
      for inner in block.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    @parser.TsStmt::Label(_, inner) => collect_decl_names_from_stmt(inner, names)
    @parser.TsStmt::If(_, then_block, else_block) => {
      for inner in then_block.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
      match else_block {
        Some(block) =>
          for inner in block.stmts {
            collect_decl_names_from_stmt(inner, names)
          }
        None => ()
      }
    }
    @parser.TsStmt::While(_, body) =>
      for inner in body.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    @parser.TsStmt::For(init, _, _, body) => {
      match init {
        Some(inner) => collect_decl_names_from_stmt(inner, names)
        None => ()
      }
      for inner in body.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    }
    @parser.TsStmt::Switch(_, cases) => {
      for case_ in cases {
        for inner in case_.body.stmts {
          collect_decl_names_from_stmt(inner, names)
        }
      }
    }
    @parser.TsStmt::ForOf(kind, binding, _, _, body) => {
      if kind != @parser.TsForOfKind::Assign {
        collect_binding_names(binding, names)
      }
      for inner in body.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    }
    @parser.TsStmt::ForIn(kind, binding, _, _, body) => {
      if kind != @parser.TsForOfKind::Assign {
        collect_binding_names(binding, names)
      }
      for inner in body.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    }
    @parser.TsStmt::With(_, body) =>
      for inner in body.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    @parser.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      for inner in try_block.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
      match catch_block {
        Some(block) =>
          for inner in block.stmts {
            collect_decl_names_from_stmt(inner, names)
          }
        None => ()
      }
      match finally_block {
        Some(block) =>
          for inner in block.stmts {
            collect_decl_names_from_stmt(inner, names)
          }
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn JSInterpreter::eval_has_decl_conflict(
  self : JSInterpreter,
  block : @parser.TsBlock,
  env : JSEnv,
) -> Bool {
  let names : Array[String] = []
  for stmt in block.stmts {
    collect_decl_names_from_stmt(stmt, names)
  }
  if names.length() == 0 {
    return false
  }
  let param_names = get_local_param_names(env)
  for name in names {
    if env_has_local_binding(env, name) || contains_key(param_names, name) {
      let _ = self.set_error_kind("SyntaxError", "Identifier already declared")
      return true
    }
  }
  false
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
fn JSInterpreter::apply_for_of_binding(
  self : JSInterpreter,
  kind : @parser.TsForOfKind,
  binding : @parser.TsBinding,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match kind {
    @parser.TsForOfKind::Assign => self.assign_pattern(binding, value, env)
    @parser.TsForOfKind::Var =>
      match binding {
        @parser.TsBinding::Ident(name) => {
          if not(env.set(name, value)) {
            env.define_var(name, value)
          }
        }
        _ => self.bind_pattern(binding, value, env)
      }
    @parser.TsForOfKind::Let => self.init_pattern(binding, value, env, false)
    @parser.TsForOfKind::Const => self.init_pattern(binding, value, env, true)
  }
}

///|
fn JSInterpreter::collect_for_in_keys(
  self : JSInterpreter,
  original : JSValue,
  target : JSValue,
) -> Array[String] {
  let keys : Array[String] = []
  let seen : Array[String] = []
  fn push_key(keys : Array[String], seen : Array[String], key : String) -> Unit {
    if not(contains_key(seen, key)) {
      keys.push(key)
      seen.push(key)
    }
  }
  match original {
    String(s) =>
      for i in 0..<s.length() {
        push_key(keys, seen, i.to_string())
      }
    _ => ()
  }
  let mut current : JSValue? = Some(target)
  while current is Some(obj) {
    match obj {
      Array(arr) => {
        for i in 0..<arr.items.length() {
          if arr.present[i] {
            push_key(keys, seen, i.to_string())
          }
        }
        for prop in arr.props {
          if prop.enumerable {
            push_key(keys, seen, prop.key)
          }
        }
      }
      Object(map) =>
        for prop in map.props {
          if prop.enumerable {
            push_key(keys, seen, prop.key)
          }
        }
      Function(closure) =>
        for prop in closure.props {
          if prop.enumerable {
            push_key(keys, seen, prop.key)
          }
        }
      String(s) =>
        for i in 0..<s.length() {
          push_key(keys, seen, i.to_string())
        }
      _ => ()
    }
    current = self.get_proto(obj)
  }
  keys
}

///|
fn loop_label_matches(loop_label : String?, signal_label : String?) -> Bool {
  match signal_label {
    None => true
    Some(lbl) =>
      match loop_label {
        Some(loop_lbl) => loop_lbl == lbl
        None => false
      }
  }
}

///|
fn JSInterpreter::exec_while_loop(
  self : JSInterpreter,
  cond : @parser.TsExpr,
  body : @parser.TsBlock,
  env : JSEnv,
  loop_label : String?,
) -> JSValue? {
  while self.eval_expr(cond, env).to_boolean() {
    match self.peek_error() {
      Some(err) => return Some(err)
      None => ()
    }
    self.tick()
    match self.peek_error() {
      Some(err) => return Some(err)
      None => ()
    }
    match self.exec_block(body, env) {
      Some(BreakSignal(label)) =>
        if loop_label_matches(loop_label, label) {
          break
        } else {
          return Some(BreakSignal(label))
        }
      Some(ContinueSignal(label)) =>
        if loop_label_matches(loop_label, label) {
          continue
        } else {
          return Some(ContinueSignal(label))
        }
      Some(val) => return Some(val)
      None => ()
    }
  }
  None
}

///|
fn JSInterpreter::exec_for_loop(
  self : JSInterpreter,
  init : @parser.TsStmt?,
  cond : @parser.TsExpr?,
  update : @parser.TsStmt?,
  body : @parser.TsBlock,
  env : JSEnv,
  loop_label : String?,
) -> JSValue? {
  // initialize
  match init {
    Some(init_stmt) =>
      match self.exec_stmt(init_stmt, env) {
        Some(val) => return Some(val)
        None => ()
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
    self.tick()
    match self.peek_error() {
      Some(err) => return Some(err)
      None => ()
    }
    match self.exec_block(body, env) {
      Some(BreakSignal(label)) =>
        if loop_label_matches(loop_label, label) {
          break
        } else {
          return Some(BreakSignal(label))
        }
      Some(ContinueSignal(label)) =>
        if loop_label_matches(loop_label, label) {
          match update {
            Some(u) =>
              match self.exec_stmt(u, env) {
                Some(val) => return Some(val)
                None => ()
              }
            None => ()
          }
          continue
        } else {
          return Some(ContinueSignal(label))
        }
      Some(val) => return Some(val)
      None => ()
    }
    match update {
      Some(u) =>
        match self.exec_stmt(u, env) {
          Some(val) => return Some(val)
          None => ()
        }
      None => ()
    }
  }
  None
}

///|
fn JSInterpreter::exec_for_of_loop(
  self : JSInterpreter,
  kind : @parser.TsForOfKind,
  binding : @parser.TsBinding,
  iterable : @parser.TsExpr,
  body : @parser.TsBlock,
  env : JSEnv,
  loop_label : String?,
) -> JSValue? {
  let iter_val = self.eval_expr(iterable, env)
  match self.peek_error() {
    Some(err) => return Some(err)
    None => ()
  }
  match self.get_iterator(iter_val) {
    Some(iterator) => {
      while true {
        self.tick()
        match self.peek_error() {
          Some(err) => return Some(err)
          None => ()
        }
        let next_method = self.get_prop_value(iterator, "next")
        match self.peek_error() {
          Some(err) => return Some(err)
          None => ()
        }
        let next_val = self.call_function(next_method, iterator, [])
        match self.peek_error() {
          Some(err) => return Some(err)
          None => ()
        }
        let done = self.get_prop_value(next_val, "done").to_boolean()
        if done {
          break
        }
        let value = self.get_prop_value(next_val, "value")
        self.apply_for_of_binding(kind, binding, value, env)
        match self.peek_error() {
          Some(err) => {
            self.iterator_close_on_error(iterator)
            return Some(err)
          }
          None => ()
        }
        match self.exec_block(body, env) {
          Some(BreakSignal(label)) =>
            if loop_label_matches(loop_label, label) {
              self.iterator_close(iterator)
              break
            } else {
              self.iterator_close(iterator)
              return Some(BreakSignal(label))
            }
          Some(ContinueSignal(label)) =>
            if loop_label_matches(loop_label, label) {
              continue
            } else {
              self.iterator_close(iterator)
              return Some(ContinueSignal(label))
            }
          Some(val) => {
            match self.peek_error() {
              Some(_) => self.iterator_close_on_error(iterator)
              None => self.iterator_close(iterator)
            }
            return Some(val)
          }
          None => ()
        }
      }
    }
    None =>
      match iter_val {
        Array(arr) => {
          let arr_val = JSValue::Array(arr)
          let mut idx = 0
          while idx < arr.length {
            self.tick()
            match self.peek_error() {
              Some(err) => return Some(err)
              None => ()
            }
            let item = self.get_prop_value(arr_val, idx.to_string())
            self.apply_for_of_binding(kind, binding, item, env)
            match self.peek_error() {
              Some(err) => return Some(err)
              None => ()
            }
            match self.exec_block(body, env) {
              Some(BreakSignal(label)) =>
                if loop_label_matches(loop_label, label) {
                  break
                } else {
                  return Some(BreakSignal(label))
                }
              Some(ContinueSignal(label)) =>
                if loop_label_matches(loop_label, label) {
                  idx += 1
                  continue
                } else {
                  return Some(ContinueSignal(label))
                }
              Some(val) => return Some(val)
              None => ()
            }
            idx += 1
          }
        }
        String(s) => {
          let mut idx = 0
          while idx < s.length() {
            self.tick()
            match self.peek_error() {
              Some(err) => return Some(err)
              None => ()
            }
            let char_str = try { s[idx:idx + 1].to_string() } catch { _ => "" }
            self.apply_for_of_binding(kind, binding, String(char_str), env)
            match self.peek_error() {
              Some(err) => return Some(err)
              None => ()
            }
            match self.exec_block(body, env) {
              Some(BreakSignal(label)) =>
                if loop_label_matches(loop_label, label) {
                  break
                } else {
                  return Some(BreakSignal(label))
                }
              Some(ContinueSignal(label)) =>
                if loop_label_matches(loop_label, label) {
                  idx += 1
                  continue
                } else {
                  return Some(ContinueSignal(label))
                }
              Some(val) => return Some(val)
              None => ()
            }
            idx += 1
          }
        }
        _ => ()
      }
  }
  None
}

///|
fn JSInterpreter::exec_for_in_loop(
  self : JSInterpreter,
  kind : @parser.TsForOfKind,
  binding : @parser.TsBinding,
  iterable : @parser.TsExpr,
  body : @parser.TsBlock,
  env : JSEnv,
  loop_label : String?,
) -> JSValue? {
  let iter_val = self.eval_expr(iterable, env)
  match self.peek_error() {
    Some(err) => return Some(err)
    None => ()
  }
  let target = match iter_val {
    Undefined | Null => {
      let err = self.set_error_kind(
        "TypeError",
        "Cannot convert undefined or null to object",
      )
      return Some(err)
    }
    Bool(_) | Number(_) | String(_) => self.wrap_primitive(env, iter_val)
    _ => iter_val
  }
  let keys = self.collect_for_in_keys(iter_val, target)
  for key in keys {
    self.tick()
    match self.peek_error() {
      Some(err) => return Some(err)
      None => ()
    }
    self.apply_for_of_binding(kind, binding, String(key), env)
    match self.peek_error() {
      Some(err) => return Some(err)
      None => ()
    }
    match self.exec_block(body, env) {
      Some(BreakSignal(label)) =>
        if loop_label_matches(loop_label, label) {
          break
        } else {
          return Some(BreakSignal(label))
        }
      Some(ContinueSignal(label)) =>
        if loop_label_matches(loop_label, label) {
          continue
        } else {
          return Some(ContinueSignal(label))
        }
      Some(val) => return Some(val)
      None => ()
    }
  }
  None
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
      self.maybe_set_default_name(val, name, Some(init))
      let is_const = match stmt {
        @parser.TsStmt::Const(_, _, _) => true
        _ => false
      }
      env.initialize(name, val, is_const)
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
    @parser.TsStmt::Label(name, inner) => {
      match inner {
        @parser.TsStmt::While(cond, body) =>
          self.exec_while_loop(cond, body, env, Some(name))
        @parser.TsStmt::For(init, cond, update, body) =>
          self.exec_for_loop(init, cond, update, body, env, Some(name))
        @parser.TsStmt::ForOf(kind, binding, _, iterable, body) =>
          self.exec_for_of_loop(kind, binding, iterable, body, env, Some(name))
        @parser.TsStmt::ForIn(kind, binding, _, iterable, body) =>
          self.exec_for_in_loop(kind, binding, iterable, body, env, Some(name))
        _ =>
          match self.exec_stmt(inner, env) {
            Some(BreakSignal(label)) =>
              match label {
                Some(lbl) if lbl == name => None
                _ => Some(BreakSignal(label))
              }
            Some(ContinueSignal(label)) =>
              match label {
                Some(lbl) if lbl == name =>
                  Some(self.set_error_kind("SyntaxError", "Illegal continue statement"))
                _ => Some(ContinueSignal(label))
              }
            Some(val) => Some(val)
            None => None
          }
      }
    }
    @parser.TsStmt::Assign(name, val_expr) => {
      let val = self.eval_expr(val_expr, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      self.maybe_set_default_name(val, name, Some(val_expr))
      self.assign_ident(name, val, env)
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
    @parser.TsStmt::While(cond, body) => self.exec_while_loop(cond, body, env, None)
    @parser.TsStmt::Switch(expr, cases) => {
      let discr = self.eval_expr(expr, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      let mut matched = false
      for case_ in cases {
        if not(matched) {
          match case_.test_expr {
            None => matched = true
            Some(test_expr) => {
              let test_val = self.eval_expr(test_expr, env)
              match self.peek_error() {
                Some(err) => return Some(err)
                None => ()
              }
              match js_strict_eq(discr, test_val) {
                Bool(true) => matched = true
                _ => ()
              }
            }
          }
        }
        if matched {
          match self.exec_block(case_.body, env) {
            Some(BreakSignal(label)) =>
              match label {
                None => return None
                Some(_) => return Some(BreakSignal(label))
              }
            Some(ContinueSignal(label)) => return Some(ContinueSignal(label))
            Some(val) => return Some(val)
            None => ()
          }
        }
      }
      None
    }
    @parser.TsStmt::For(init, cond, update, body) =>
      self.exec_for_loop(init, cond, update, body, env, None)
    Break(label) => Some(BreakSignal(label))
    Continue(label) => Some(ContinueSignal(label))
    @parser.TsStmt::CompoundAssign(name, op, val_expr) => {
      let current = env.get(name)
      let val = self.eval_expr(val_expr, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      let new_val = apply_compound_op(op, current, val)
      self.assign_ident(name, new_val, env)
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
        Array(_) | Object(_) | Function(_) => {
          let key = idx.to_js_string()
          self.set_prop_value(arr, key, val)
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
      if prop.has_prefix("@@get:") || prop.has_prefix("@@set:") {
        fn find_accessor(obj : JSValue, key : String) -> (JSValue?, JSValue?) {
          match obj {
            Function(closure) =>
              for prop in closure.props {
                if prop.key == key {
                  return (prop.get, prop.set)
                }
              }
            Object(map) =>
              for prop in map.props {
                if prop.key == key {
                  return (prop.get, prop.set)
                }
              }
            Array(arr) =>
              for prop in arr.props {
                if prop.key == key {
                  return (prop.get, prop.set)
                }
              }
            _ => ()
          }
          (None, None)
        }
        let is_get = prop.has_prefix("@@get:")
        let real_key = (try { prop[6:] } catch { _ => "" }).to_string()
        let (prev_get, prev_set) = find_accessor(obj, real_key)
        let getter = if is_get { Some(val) } else { prev_get }
        let setter = if is_get { prev_set } else { Some(val) }
        let _ = js_define_accessor_prop(obj, real_key, getter, setter, false, true)
      } else {
        self.set_prop_value(obj, prop, val)
      }
      None
    }
    @parser.TsStmt::ForOf(kind, binding, _, iterable, body) =>
      self.exec_for_of_loop(kind, binding, iterable, body, env, None)
    @parser.TsStmt::ForIn(kind, binding, _, iterable, body) =>
      self.exec_for_in_loop(kind, binding, iterable, body, env, None)
    @parser.TsStmt::With(obj_expr, body) => {
      if env.has("__strict__") {
        return Some(self.set_error_kind("SyntaxError", "Strict mode code may not include a with statement"))
      }
      let obj_val = self.eval_expr(obj_expr, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      let target = match obj_val {
        Undefined | Null => {
          let err = self.set_error_kind(
            "TypeError",
            "Cannot convert undefined or null to object",
          )
          return Some(err)
        }
        Bool(_) | Number(_) | String(_) => self.wrap_primitive(env, obj_val)
        _ => obj_val
      }
      let with_env = js_new_env(Some(env))
      with_env.define_var("__with_obj__", target)
      match self.exec_block(body, with_env) {
        Some(val) => Some(val)
        None => None
      }
    }
    @parser.TsStmt::Debugger => None
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
// / variablesimple
fn JSInterpreter::hoist_stmt(self : JSInterpreter, stmt : @parser.TsStmt, env : JSEnv) -> Unit {
  match stmt {
    @parser.TsStmt::Let(name, _, _) | @parser.TsStmt::Const(name, _, _) =>
      if not(env.has(name)) {
        let is_const = match stmt {
          @parser.TsStmt::Const(_, _, _) => true
          _ => false
        }
        env.define_uninitialized(name, is_const)
        match env.parent {
          None => {
            let global_obj = self.global_env.get("globalThis")
            let _ = js_set_prop(global_obj, name, Undefined)
          }
          Some(_) => ()
        }
      }
    @parser.TsStmt::Block(block) => self.hoist_block(block, env)
    @parser.TsStmt::Label(_, inner) => self.hoist_stmt(inner, env)
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
    @parser.TsStmt::Switch(_, cases) =>
      for case_ in cases {
        self.hoist_block(case_.body, env)
      }
    @parser.TsStmt::ForIn(kind, binding, _, _, body) => {
      if kind != @parser.TsForOfKind::Assign {
        let names : Array[String] = []
        collect_binding_names(binding, names)
        let is_const = kind == @parser.TsForOfKind::Const
        for name in names {
          if not(env.has(name)) {
            match kind {
              @parser.TsForOfKind::Var => env.define_var(name, Undefined)
              @parser.TsForOfKind::Let | @parser.TsForOfKind::Const =>
                env.define_uninitialized(name, is_const)
              @parser.TsForOfKind::Assign => ()
            }
            match env.parent {
              None => {
                let global_obj = self.global_env.get("globalThis")
                let _ = js_set_prop(global_obj, name, Undefined)
              }
              Some(_) => ()
            }
          }
        }
      }
      self.hoist_block(body, env)
    }
    @parser.TsStmt::With(_, body) => self.hoist_block(body, env)
    @parser.TsStmt::ForOf(kind, binding, _, _, body) => {
      if kind != @parser.TsForOfKind::Assign {
        let names : Array[String] = []
        collect_binding_names(binding, names)
        let is_const = kind == @parser.TsForOfKind::Const
        for name in names {
          if not(env.has(name)) {
            match kind {
              @parser.TsForOfKind::Var => env.define_var(name, Undefined)
              @parser.TsForOfKind::Let | @parser.TsForOfKind::Const =>
                env.define_uninitialized(name, is_const)
              @parser.TsForOfKind::Assign => ()
            }
            match env.parent {
              None => {
                let global_obj = self.global_env.get("globalThis")
                let _ = js_set_prop(global_obj, name, Undefined)
              }
              Some(_) => ()
            }
          }
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
pub fn JSInterpreter::hoist_block(self : JSInterpreter, block : @parser.TsBlock, env : JSEnv) -> Unit {
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
        Native(name) if name == "Symbol" => false
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
      let has_param_expr = has_param_expressions(func_def.params)
      if has_param_expr {
        let param_names = collect_param_names(func_def.params)
        if param_names.length() > 0 {
          call_env.define_var("__param_names__", js_array_from(string_array_to_js(param_names)))
        }
      }
      self.bind_params(func_def.params, args, call_env)
      let body_env = if has_param_expr {
        js_new_env(Some(call_env))
      } else {
        call_env
      }
      let state : JSGeneratorState = {
        func: func_def,
        env: body_env,
        index: 0,
        done: false,
        cont: None,
        active_iterators: [],
      }
      self.generators.push(state)
      let gen_id = self.generators.length() - 1
      let obj = self.new_object()
      let _ = js_set_prop(obj, "__class", String("Generator"))
      let _ = js_set_prop(obj, "__gen_id", Number(gen_id.to_double()))
      let _ = js_set_prop(obj, "next", self.make_native("Generator.prototype.next"))
      let _ = js_set_prop(obj, "return", self.make_native("Generator.prototype.return"))
      let _ = js_set_prop(obj, "throw", self.make_native("Generator.prototype.throw"))
      let _ = js_set_prop(obj, "@@iterator", self.make_native("Iterator.prototype[@@iterator]"))
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
fn string_array_to_js(items : Array[String]) -> Array[JSValue] {
  let out : Array[JSValue] = []
  for item in items {
    out.push(String(item))
  }
  out
}

///|
fn collect_binding_names(binding : @parser.TsBinding, names : Array[String]) -> Unit {
  match binding {
    @parser.TsBinding::Ident(name) => names.push(name)
    @parser.TsBinding::Array(arr) => {
      for item in arr.items {
        match item {
          Some(elem) => collect_binding_names(elem.binding, names)
          None => ()
        }
      }
      match arr.rest {
        Some(rest_binding) => collect_binding_names(rest_binding, names)
        None => ()
      }
    }
    @parser.TsBinding::Object(obj) => {
      for prop in obj.props {
        collect_binding_names(prop.binding, names)
      }
      match obj.rest {
        Some(rest_name) => names.push(rest_name)
        None => ()
      }
    }
    @parser.TsBinding::Target(_) => ()
  }
}

///|
fn collect_param_names(params : Array[@parser.TsParam]) -> Array[String] {
  let names : Array[String] = []
  for param in params {
    match param.binding {
      Some(binding) => collect_binding_names(binding, names)
      None => names.push(param.name)
    }
  }
  names
}

///|
fn has_param_expressions(params : Array[@parser.TsParam]) -> Bool {
  for param in params {
    if param.default is Some(_) {
      return true
    }
    match param.binding {
      Some(_) => return true
      None => ()
    }
  }
  false
}

///|
fn JSInterpreter::array_like_length(self : JSInterpreter, value : JSValue) -> Int {
  let str_value = self.array_like_string_value(value)
  let mut len_val = JSValue::Undefined
  if js_has_prop(value, "length") {
    len_val = self.get_prop_value(value, "length")
  } else {
    match str_value {
      Some(s) => len_val = Number(s.length().to_double())
      None => ()
    }
  }
  match self.peek_error() {
    Some(_) => return 0
    None => ()
  }
  let len_num = self.to_number_value(len_val)
  if len_num.is_nan() || len_num <= 0.0 {
    return 0
  }
  if len_num.is_inf() {
    return self.step_limit
  }
  let mut len = len_num.floor()
  if len < 0.0 {
    return 0
  }
  let cap = self.step_limit.to_double()
  if len > cap {
    len = cap
  }
  len.to_int()
}

///|
fn JSInterpreter::array_like_get(self : JSInterpreter, value : JSValue, index : Int) -> JSValue {
  let key = index.to_string()
  if js_has_prop(value, key) {
    return self.get_prop_value(value, key)
  }
  match self.array_like_string_value(value) {
    Some(s) =>
      if index >= 0 && index < s.length() {
        String(try { s[index:index + 1].to_string() } catch { _ => "" })
      } else {
        self.get_prop_value(value, key)
      }
    None => self.get_prop_value(value, key)
  }
}

///|
fn JSInterpreter::get_iterator(self : JSInterpreter, value : JSValue) -> JSValue? {
  let iter_method = self.get_prop_value(value, "@@iterator")
  match self.peek_error() {
    Some(_) => return None
    None => ()
  }
  match iter_method {
    Undefined | Null => None
    _ => {
      let iterator = self.call_function(iter_method, value, [])
      match self.peek_error() {
        Some(_) => None
        None => Some(iterator)
      }
    }
  }
}

///|
fn JSInterpreter::iterator_close(self : JSInterpreter, iterator : JSValue) -> Unit {
  let ret = self.get_prop_value(iterator, "return")
  match ret {
    Undefined | Null => ()
    _ => {
      let result = self.call_function(ret, iterator, [])
      match self.peek_error() {
        Some(_) => return
        None => ()
      }
      match result {
        Object(_) => ()
        _ => {
          let _ = self.set_error_kind(
            "TypeError",
            "Iterator return is not an object",
          )
        }
      }
    }
  }
}

///|
fn JSInterpreter::iterator_close_on_error(
  self : JSInterpreter,
  iterator : JSValue,
) -> Unit {
  let saved = self.peek_error()
  match saved {
    None => self.iterator_close(iterator)
    Some(err) => {
      self.last_error = None
      self.iterator_close(iterator)
      self.last_error = Some(err)
    }
  }
}

///|
fn JSInterpreter::push_active_iterator(self : JSInterpreter, iterator : JSValue) -> Unit {
  match self.current_gen_id {
    Some(gen_id) => {
      let state = self.generators[gen_id]
      state.active_iterators.push(iterator)
      self.generators[gen_id] = state
    }
    None => ()
  }
}

///|
fn JSInterpreter::pop_active_iterator(self : JSInterpreter) -> Unit {
  match self.current_gen_id {
    Some(gen_id) => {
      let state = self.generators[gen_id]
      if state.active_iterators.length() > 0 {
        let _ = state.active_iterators.pop()
        self.generators[gen_id] = state
      }
    }
    None => ()
  }
}

///|
priv enum GenValue {
  Value(JSValue)
  Yield(JSValue, (JSValue) -> GenValue)
}

///|
fn gen_bind(value : GenValue, cont : (JSValue) -> GenValue) -> GenValue {
  match value {
    GenValue::Value(v) => cont(v)
    GenValue::Yield(yielded, cont_fn) =>
      GenValue::Yield(yielded, (sent) => gen_bind(cont_fn(sent), cont))
  }
}

///|
fn gen_to_signal(value : GenValue, cont : (JSValue) -> GenSignal) -> GenSignal {
  match value {
    GenValue::Value(v) => cont(v)
    GenValue::Yield(yielded, cont_fn) =>
      GenSignal::Suspend(
        yielded,
        (sent) => gen_to_signal(cont_fn(sent), cont),
      )
  }
}

///|
fn JSInterpreter::yield_star_next(
  self : JSInterpreter,
  iterator : JSValue,
  sent : JSValue?,
  has_sent : Bool,
) -> GenValue {
  let args : Array[JSValue] = []
  if has_sent {
    match sent {
      Some(val) => args.push(val)
      None => args.push(Undefined)
    }
  }
  let result = self.call_method(iterator, "next", args)
  match self.peek_error() {
    Some(err) => {
      self.iterator_close_on_error(iterator)
      self.pop_active_iterator()
      return GenValue::Value(err)
    }
    None => ()
  }
  match result {
    Object(_) | Function(_) | Array(_) => ()
    _ => {
      let err = self.set_error_kind("TypeError", "Iterator result is not an object")
      self.pop_active_iterator()
      return GenValue::Value(err)
    }
  }
  let done = self.get_prop_value(result, "done").to_boolean()
  let value = self.get_prop_value(result, "value")
  if done {
    self.pop_active_iterator()
    return GenValue::Value(value)
  }
  GenValue::Yield(
    value,
    (sent_val) => self.yield_star_next(iterator, Some(sent_val), true),
  )
}

///|
fn JSInterpreter::eval_yield_star(
  self : JSInterpreter,
  expr : @parser.TsExpr,
  env : JSEnv,
) -> GenValue {
  gen_bind(self.eval_expr_gen(expr, env), (iter_val) => {
    let iterator =
      match self.get_iterator(iter_val) {
        Some(it) => it
        None => {
          let err =
            match self.peek_error() {
              Some(e) => e
              None => self.set_error_kind("TypeError", "yield* value is not iterable")
            }
          return GenValue::Value(err)
        }
      }
    self.push_active_iterator(iterator)
    self.yield_star_next(iterator, None, false)
  })
}

///|
fn expr_has_yield(expr : @parser.TsExpr) -> Bool {
  match expr {
    @parser.TsExpr::Yield(_) => true
    @parser.TsExpr::YieldStar(_) => true
    @parser.TsExpr::AssignExpr(_, value) => expr_has_yield(value)
    @parser.TsExpr::AssignPattern(binding, value) =>
      binding_has_yield(binding) || expr_has_yield(value)
    @parser.TsExpr::CompoundAssignExpr(left, _, right) =>
      expr_has_yield(left) || expr_has_yield(right)
    @parser.TsExpr::PropAssignExpr(obj, _, value) =>
      expr_has_yield(obj) || expr_has_yield(value)
    @parser.TsExpr::IndexAssignExpr(obj, index, value) =>
      expr_has_yield(obj) || expr_has_yield(index) || expr_has_yield(value)
    @parser.TsExpr::Seq(left, right) =>
      expr_has_yield(left) || expr_has_yield(right)
    @parser.TsExpr::BinOp(_, left, right) =>
      expr_has_yield(left) || expr_has_yield(right)
    @parser.TsExpr::UnaryOp(_, operand) => expr_has_yield(operand)
    @parser.TsExpr::Cond(cond, then_expr, else_expr) =>
      expr_has_yield(cond) || expr_has_yield(then_expr) || expr_has_yield(else_expr)
    @parser.TsExpr::CallExpr(callee, args) => {
      if expr_has_yield(callee) {
        true
      } else {
        for arg in args {
          if expr_has_yield(arg) {
            return true
          }
        }
        false
      }
    }
    @parser.TsExpr::Call(_, args) => {
      for arg in args {
        if expr_has_yield(arg) {
          return true
        }
      }
      false
    }
    @parser.TsExpr::MethodCall(receiver, _, args) => {
      if expr_has_yield(receiver) {
        true
      } else {
        for arg in args {
          if expr_has_yield(arg) {
            return true
          }
        }
        false
      }
    }
    @parser.TsExpr::IndexAccess(obj, index) =>
      expr_has_yield(obj) || expr_has_yield(index)
    @parser.TsExpr::PropAccess(obj, _) => expr_has_yield(obj)
    @parser.TsExpr::New(_, args) => {
      for arg in args {
        if expr_has_yield(arg) {
          return true
        }
      }
      false
    }
    @parser.TsExpr::NewExpr(expr, args) => {
      if expr_has_yield(expr) {
        true
      } else {
        for arg in args {
          if expr_has_yield(arg) {
            return true
          }
        }
        false
      }
    }
    @parser.TsExpr::ArrayLit(elements) => {
      for elem in elements {
        if expr_has_yield(elem) {
          return true
        }
      }
      false
    }
    @parser.TsExpr::ObjectLit(fields) => {
      for field in fields {
        let (_, value) = field
        if expr_has_yield(value) {
          return true
        }
      }
      false
    }
    @parser.TsExpr::ArrowFunc(_, _) => false
    @parser.TsExpr::FuncExpr(_) => false
    _ => false
  }
}

///|
fn binding_has_yield(binding : @parser.TsBinding) -> Bool {
  match binding {
    @parser.TsBinding::Ident(_) => false
    @parser.TsBinding::Target(expr) => expr_has_yield(expr)
    @parser.TsBinding::Array(arr) => {
      for item in arr.items {
        match item {
          None => ()
          Some(elem) => {
            if binding_has_yield(elem.binding) {
              return true
            }
            match elem.default {
              Some(expr) =>
                if expr_has_yield(expr) {
                  return true
                }
              None => ()
            }
          }
        }
      }
      match arr.rest {
        Some(rest_binding) => binding_has_yield(rest_binding)
        None => false
      }
    }
    @parser.TsBinding::Object(obj) => {
      for prop in obj.props {
        if binding_has_yield(prop.binding) {
          return true
        }
        match prop.default {
          Some(expr) =>
            if expr_has_yield(expr) {
              return true
            }
          None => ()
        }
      }
      false
    }
  }
}

///|
fn JSInterpreter::eval_object_binding_key(
  self : JSInterpreter,
  prop : @parser.TsObjectBindingProp,
  env : JSEnv,
) -> String {
  match prop.key_expr {
    Some(expr) => self.eval_expr(expr, env).to_js_string()
    None => prop.key
  }
}

///|
fn JSInterpreter::maybe_set_function_name_for_binding(
  self : JSInterpreter,
  binding : @parser.TsBinding,
  value : JSValue,
) -> Unit {
  match binding {
    @parser.TsBinding::Ident(name) => self.maybe_set_function_name(value, name)
    @parser.TsBinding::Target(_) => ()
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
    Object(_) =>
      match js_get_prop(value, "__class_name") {
        String(class_name) =>
          if class_name.length() > 0 {
            if not(self.has_own_prop(value, "name")) {
              let _ = js_set_prop(value, "name", String(class_name))
            }
          } else {
            let has_name_prop =
              match js_get_prop(value, "__class_has_name_prop") {
                Bool(b) => b
                _ => false
              }
            if not(has_name_prop) && not(self.has_own_prop(value, "name")) {
              let _ = js_set_prop(value, "name", String(name))
            }
          }
        _ => ()
      }
    _ => ()
  }
}

///|
fn JSInterpreter::is_anonymous_function_definition(
  _self : JSInterpreter,
  expr : @parser.TsExpr,
) -> Bool {
  match expr {
    @parser.TsExpr::FuncExpr(func) => func.name == "<anon>"
    @parser.TsExpr::ArrowFunc(_, _) => true
    @parser.TsExpr::ObjectLit(fields) => {
      for field in fields {
        let (key, value) = field
        if key == "__class_name" {
          match value {
            @parser.TsExpr::StringLit(s) => return s.length() == 0
            _ => return false
          }
        }
      }
      false
    }
    _ => false
  }
}

///|
fn JSInterpreter::maybe_set_default_name_for_binding(
  self : JSInterpreter,
  binding : @parser.TsBinding,
  value : JSValue,
  default_expr : @parser.TsExpr?,
) -> Unit {
  match default_expr {
    Some(expr) =>
      if self.is_anonymous_function_definition(expr) {
        self.maybe_set_function_name_for_binding(binding, value)
      }
    None => ()
  }
}

///|
fn JSInterpreter::maybe_set_default_name(
  self : JSInterpreter,
  value : JSValue,
  name : String,
  default_expr : @parser.TsExpr?,
) -> Unit {
  match default_expr {
    Some(expr) =>
      if self.is_anonymous_function_definition(expr) {
        self.maybe_set_function_name(value, name)
      }
    None => ()
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
    @parser.TsBinding::Target(_) => {
      let _ = self.set_error_kind("TypeError", "Invalid binding target")
    }
  }
}

///|
fn JSInterpreter::init_pattern(
  self : JSInterpreter,
  binding : @parser.TsBinding,
  value : JSValue,
  env : JSEnv,
  is_const : Bool,
) -> Unit {
  match binding {
    @parser.TsBinding::Ident(name) => env.initialize(name, value, is_const)
    @parser.TsBinding::Array(arr) =>
      self.init_array_pattern(arr, value, env, is_const)
    @parser.TsBinding::Object(obj) =>
      self.init_object_pattern(obj, value, env, is_const)
    @parser.TsBinding::Target(_) => {
      let _ = self.set_error_kind("TypeError", "Invalid binding target")
    }
  }
}

///|
fn JSInterpreter::assign_ident(
  self : JSInterpreter,
  name : String,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  if env.is_uninitialized(name) {
    let _ = self.set_error_kind("ReferenceError", name + " is not defined")
    return
  }
  if env.is_const(name) {
    let _ = self.set_error_kind("TypeError", "Assignment to constant variable")
    return
  }
  if not(env.set(name, value)) {
    if env.has("__strict__") {
      let _ = self.set_error_kind("ReferenceError", name + " is not defined")
    } else {
      self.global_env.define_var(name, value)
      let global_obj = self.global_env.get("globalThis")
      let _ = js_set_prop(global_obj, name, value)
    }
  }
}

///|
fn JSInterpreter::assign_pattern(
  self : JSInterpreter,
  binding : @parser.TsBinding,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match binding {
    @parser.TsBinding::Ident(name) => self.assign_ident(name, value, env)
    @parser.TsBinding::Array(arr) => self.assign_array_pattern(arr, value, env)
    @parser.TsBinding::Object(obj) => self.assign_object_pattern(obj, value, env)
    @parser.TsBinding::Target(target) => self.assign_target_expr(target, value, env)
  }
}

///|
priv enum AssignTarget {
  Ident(String)
  Prop(JSValue, String)
  Index(JSValue, String)
}

///|
fn JSInterpreter::prepare_assignment_target(
  self : JSInterpreter,
  target : @parser.TsExpr,
  env : JSEnv,
) -> AssignTarget? {
  match target {
    @parser.TsExpr::Var(name) => Some(AssignTarget::Ident(name))
    @parser.TsExpr::PropAccess(obj_expr, prop) => {
      let obj = self.eval_expr(obj_expr, env)
      match self.peek_error() {
        Some(_) => None
        None =>
          match obj {
            Undefined | Null => {
              let _ = self.set_error_kind(
                "TypeError",
                "Cannot read properties of null or undefined",
              )
              None
            }
            _ => Some(AssignTarget::Prop(obj, prop))
          }
      }
    }
    @parser.TsExpr::IndexAccess(obj_expr, idx_expr) => {
      let obj = self.eval_expr(obj_expr, env)
      match self.peek_error() {
        Some(_) => None
        None =>
          match obj {
            Undefined | Null => {
              let _ = self.set_error_kind(
                "TypeError",
                "Cannot read properties of null or undefined",
              )
              None
            }
            _ => {
              let idx = self.eval_expr(idx_expr, env)
              match self.peek_error() {
                Some(_) => None
                None => {
                  let key = idx.to_js_string()
                  Some(AssignTarget::Index(obj, key))
                }
              }
            }
          }
      }
    }
    _ => {
      let _ = self.set_error_kind("TypeError", "Invalid assignment target")
      None
    }
  }
}

///|
fn JSInterpreter::assign_prepared_target(
  self : JSInterpreter,
  target : AssignTarget,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match target {
    AssignTarget::Ident(name) => self.assign_ident(name, value, env)
    AssignTarget::Prop(obj, prop) => self.set_prop_value(obj, prop, value)
    AssignTarget::Index(obj, key) =>
      match obj {
        Array(_) | Object(_) => {
          self.set_prop_value(obj, key, value)
        }
        _ => ()
      }
  }
}

///|
fn JSInterpreter::assign_target_expr(
  self : JSInterpreter,
  target : @parser.TsExpr,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match self.prepare_assignment_target(target, env) {
    Some(prepared) => self.assign_prepared_target(prepared, value, env)
    None => ()
  }
}

///|
fn JSInterpreter::assign_pattern_gen(
  self : JSInterpreter,
  binding : @parser.TsBinding,
  value : JSValue,
  env : JSEnv,
) -> GenValue {
  match binding {
    @parser.TsBinding::Ident(name) => {
      self.assign_ident(name, value, env)
      GenValue::Value(value)
    }
    @parser.TsBinding::Array(arr) => self.assign_array_pattern_gen(arr, value, env)
    @parser.TsBinding::Object(obj) => self.assign_object_pattern_gen(obj, value, env)
    @parser.TsBinding::Target(target) =>
      self.assign_target_expr_gen(target, value, env)
  }
}

///|
fn JSInterpreter::assign_target_expr_gen(
  self : JSInterpreter,
  target : @parser.TsExpr,
  value : JSValue,
  env : JSEnv,
) -> GenValue {
  self.eval_assignment_target_gen(target, env, (prepared) => {
    self.assign_prepared_target(prepared, value, env)
    GenValue::Value(value)
  })
}

///|
fn JSInterpreter::eval_assignment_target_gen(
  self : JSInterpreter,
  target : @parser.TsExpr,
  env : JSEnv,
  cont : (AssignTarget) -> GenValue,
) -> GenValue {
  match target {
    @parser.TsExpr::Var(name) => cont(AssignTarget::Ident(name))
    @parser.TsExpr::PropAccess(obj_expr, prop) =>
      gen_bind(self.eval_expr_gen(obj_expr, env), (obj) => {
        if self.peek_error() is Some(_) {
          return GenValue::Value(Undefined)
        }
        match obj {
          Undefined | Null => {
            let _ = self.set_error_kind(
              "TypeError",
              "Cannot read properties of null or undefined",
            )
            GenValue::Value(Undefined)
          }
          _ => cont(AssignTarget::Prop(obj, prop))
        }
      })
    @parser.TsExpr::IndexAccess(obj_expr, idx_expr) =>
      gen_bind(self.eval_expr_gen(obj_expr, env), (obj) => {
        if self.peek_error() is Some(_) {
          return GenValue::Value(Undefined)
        }
        match obj {
          Undefined | Null => {
            let _ = self.set_error_kind(
              "TypeError",
              "Cannot read properties of null or undefined",
            )
            GenValue::Value(Undefined)
          }
          _ =>
            gen_bind(self.eval_expr_gen(idx_expr, env), (idx) => {
              if self.peek_error() is Some(_) {
                return GenValue::Value(Undefined)
              }
              let key = idx.to_js_string()
              cont(AssignTarget::Index(obj, key))
            })
        }
      })
    _ => {
      let _ = self.set_error_kind("TypeError", "Invalid assignment target")
      GenValue::Value(Undefined)
    }
  }
}

///|
fn JSInterpreter::assign_array_pattern_gen(
  self : JSInterpreter,
  pattern : @parser.TsArrayBinding,
  value : JSValue,
  env : JSEnv,
) -> GenValue {
  match value {
    Undefined | Null => {
      let _ = self.set_error_kind(
        "TypeError",
        "Cannot destructure undefined or null",
      )
      return GenValue::Value(Undefined)
    }
    _ => ()
  }
  match self.get_iterator(value) {
    Some(iterator) => {
      self.push_active_iterator(iterator)
      let mut done = false
      let next_value = fn() -> JSValue {
        if done {
          JSValue::Undefined
        } else {
          let result = self.call_method(iterator, "next", [])
          let (is_done, val) = self.iter_result_value_done(result)
          done = is_done
          val
        }
      }
      fn process_index(index : Int) -> GenValue {
        if self.peek_error() is Some(_) {
          return GenValue::Value(Undefined)
        }
        if index >= pattern.items.length() {
          match pattern.rest {
            None => {
              self.pop_active_iterator()
              GenValue::Value(Undefined)
            }
            Some(rest_binding) =>
              match rest_binding {
                @parser.TsBinding::Target(target_expr) =>
                  self.eval_assignment_target_gen(target_expr, env, (prepared) => {
                    if self.peek_error() is Some(_) {
                      if not(done) {
                        self.iterator_close_on_error(iterator)
                      }
                      self.pop_active_iterator()
                      GenValue::Value(Undefined)
                    } else {
                      let rest_items : Array[JSValue] = []
                      while not(done) {
                        let val = next_value()
                        if done {
                          break
                        }
                        rest_items.push(val)
                        if self.peek_error() is Some(_) {
                          break
                        }
                      }
                      if self.peek_error() is Some(_) {
                        self.pop_active_iterator()
                        GenValue::Value(Undefined)
                      } else {
                        let rest_val = js_array_from(rest_items)
                        self.assign_prepared_target(prepared, rest_val, env)
                        if self.peek_error() is Some(_) {
                          if not(done) {
                            self.iterator_close_on_error(iterator)
                          }
                          self.pop_active_iterator()
                          GenValue::Value(Undefined)
                        } else {
                          self.pop_active_iterator()
                          GenValue::Value(Undefined)
                        }
                      }
                    }
                  })
                _ => {
                  let rest_items : Array[JSValue] = []
                  while not(done) {
                    let val = next_value()
                    if done {
                      break
                    }
                    rest_items.push(val)
                    if self.peek_error() is Some(_) {
                      break
                    }
                  }
                  if self.peek_error() is Some(_) {
                    self.pop_active_iterator()
                    GenValue::Value(Undefined)
                  } else {
                    let rest_val = js_array_from(rest_items)
                    gen_bind(self.assign_pattern_gen(rest_binding, rest_val, env), (_unused) => {
                      if self.peek_error() is Some(_) {
                        if not(done) {
                          self.iterator_close_on_error(iterator)
                        }
                        self.pop_active_iterator()
                        GenValue::Value(Undefined)
                      } else {
                        self.pop_active_iterator()
                        GenValue::Value(Undefined)
                      }
                    })
                  }
                }
              }
          }
        } else {
          match pattern.items[index] {
            None => {
              if not(done) {
                let _ = next_value()
              }
              process_index(index + 1)
            }
            Some(elem) => {
              let val = if done { JSValue::Undefined } else { next_value() }
              if self.peek_error() is Some(_) {
                return GenValue::Value(Undefined)
              }
              let mut used_default = false
              let default_expr = elem.default
              let with_default =
                match elem.default {
                  Some(expr) =>
                    if val is Undefined {
                      used_default = true
                      Some(self.eval_expr_gen(expr, env))
                    } else {
                      None
                    }
                  None => None
                }
              let assign_elem = fn(v : JSValue) -> GenValue {
                if used_default {
                  self.maybe_set_default_name_for_binding(
                    elem.binding,
                    v,
                    default_expr,
                  )
                }
                gen_bind(self.assign_pattern_gen(elem.binding, v, env), (_unused) => {
                  if self.peek_error() is Some(_) {
                    if not(done) {
                      self.iterator_close_on_error(iterator)
                    }
                    self.pop_active_iterator()
                    GenValue::Value(Undefined)
                  } else {
                    process_index(index + 1)
                  }
                })
              }
              match with_default {
                Some(default_signal) =>
                  gen_bind(default_signal, (default_val) => assign_elem(default_val))
                None => assign_elem(val)
              }
            }
          }
        }
      }
      process_index(0)
    }
    None => {
      let len = self.array_like_length(value)
      fn process_index(
        self : JSInterpreter,
        pattern : @parser.TsArrayBinding,
        env : JSEnv,
        value : JSValue,
        len : Int,
        index : Int,
      ) -> GenValue {
        if self.peek_error() is Some(_) {
          return GenValue::Value(Undefined)
        }
        if index >= pattern.items.length() {
          match pattern.rest {
            None => GenValue::Value(Undefined)
            Some(rest_binding) => {
              let rest_items : Array[JSValue] = []
              let mut i = index
              while i < len {
                rest_items.push(self.array_like_get(value, i))
                i = i + 1
              }
              let rest_val = js_array_from(rest_items)
              self.assign_pattern_gen(rest_binding, rest_val, env)
            }
          }
        } else {
          match pattern.items[index] {
            None => process_index(self, pattern, env, value, len, index + 1)
            Some(elem) => {
              let val = if index < len {
                self.array_like_get(value, index)
              } else {
                Undefined
              }
              let mut used_default = false
              let default_expr = elem.default
              let with_default =
                match elem.default {
                  Some(expr) =>
                    if val is Undefined {
                      used_default = true
                      Some(self.eval_expr_gen(expr, env))
                    } else {
                      None
                    }
                  None => None
                }
              let assign_elem = fn(v : JSValue) -> GenValue {
                if used_default {
                  self.maybe_set_default_name_for_binding(
                    elem.binding,
                    v,
                    default_expr,
                  )
                }
                gen_bind(self.assign_pattern_gen(elem.binding, v, env), (_unused) =>
                  process_index(self, pattern, env, value, len, index + 1)
                )
              }
              match with_default {
                Some(default_signal) =>
                  gen_bind(default_signal, (default_val) => assign_elem(default_val))
                None => assign_elem(val)
              }
            }
          }
        }
      }
      process_index(self, pattern, env, value, len, 0)
    }
  }
}

///|
fn JSInterpreter::assign_object_pattern_gen(
  self : JSInterpreter,
  pattern : @parser.TsObjectBinding,
  value : JSValue,
  env : JSEnv,
) -> GenValue {
  match value {
    Undefined | Null => {
      let _ = self.set_error_kind(
        "TypeError",
        "Cannot destructure undefined or null",
      )
      return GenValue::Value(Undefined)
    }
    _ => ()
  }
  let used_keys : Array[String] = []
  fn process_prop(
    self : JSInterpreter,
    pattern : @parser.TsObjectBinding,
    env : JSEnv,
    value : JSValue,
    used_keys : Array[String],
    index : Int,
  ) -> GenValue {
    if self.peek_error() is Some(_) {
      return GenValue::Value(Undefined)
    }
    if index >= pattern.props.length() {
      match pattern.rest {
        None => GenValue::Value(Undefined)
        Some(rest_name) => {
          let rest_obj = self.new_object()
          match value {
            Object(map) => {
              for prop in map.props {
                if not(prop.enumerable) {
                  continue
                }
                if not(contains_key(used_keys, prop.key)) {
                  let val = self.eval_prop_value(JSValue::Object(map), prop)
                  let _ = js_set_prop(rest_obj, prop.key, val)
                }
              }
            }
            Array(arr) => {
              for i, item in arr.items {
                let key = i.to_string()
                if not(contains_key(used_keys, key)) && arr.present[i] {
                  let _ = js_set_prop(rest_obj, key, item)
                }
              }
              for prop in arr.props {
                if not(contains_key(used_keys, prop.key)) {
                  if not(prop.enumerable) {
                    continue
                  }
                  let val = self.eval_prop_value(JSValue::Array(arr), prop)
                  let _ = js_set_prop(rest_obj, prop.key, val)
                }
              }
            }
            Function(closure) => {
              for prop in closure.props {
                if not(contains_key(used_keys, prop.key)) {
                  if not(prop.enumerable) {
                    continue
                  }
                  let val = self.eval_prop_value(JSValue::Function(closure), prop)
                  let _ = js_set_prop(rest_obj, prop.key, val)
                }
              }
            }
            _ => ()
          }
          self.assign_ident(rest_name, rest_obj, env)
          GenValue::Value(Undefined)
        }
      }
    } else {
      let prop = pattern.props[index]
      let key_signal =
        match prop.key_expr {
          Some(expr) => self.eval_expr_gen(expr, env)
          None => GenValue::Value(JSValue::String(prop.key))
        }
      gen_bind(key_signal, (key_val) => {
        let key = key_val.to_js_string()
        used_keys.push(key)
        let val = self.get_prop_value(value, key)
        let mut used_default = false
        let default_expr = prop.default
        let with_default =
          match prop.default {
            Some(expr) =>
              if val is Undefined {
                used_default = true
                Some(self.eval_expr_gen(expr, env))
              } else {
                None
              }
            None => None
          }
        let assign_prop = fn(v : JSValue) -> GenValue {
          if used_default {
            self.maybe_set_default_name_for_binding(
              prop.binding,
              v,
              default_expr,
            )
          }
          gen_bind(self.assign_pattern_gen(prop.binding, v, env), (_unused) =>
            process_prop(self, pattern, env, value, used_keys, index + 1)
          )
        }
        match with_default {
          Some(default_signal) =>
            gen_bind(default_signal, (default_val) => assign_prop(default_val))
          None => assign_prop(val)
        }
      })
    }
  }
  process_prop(self, pattern, env, value, used_keys, 0)
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
          let result = self.generator_next(gen_id, Undefined)
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
            let default_expr = elem.default
            match elem.default {
              Some(expr) =>
                if val is Undefined {
                  val = self.eval_expr(expr, env)
                  used_default = true
                }
              None => ()
            }
            if used_default {
              self.maybe_set_default_name_for_binding(
                elem.binding,
                val,
                default_expr,
              )
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
      if not(done) {
        let _ = self.generator_return(gen_id, Undefined)
      }
    }
    None =>
      match self.get_iterator(value) {
        Some(iterator) => {
          let mut done = false
          let next_value = fn() -> JSValue {
            if done {
              JSValue::Undefined
            } else {
              let result = self.call_method(iterator, "next", [])
              match self.peek_error() {
                Some(_) => {
                  done = true
                  return JSValue::Undefined
                }
                None => ()
              }
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
                match self.peek_error() {
                  Some(_) => return
                  None => ()
                }
              }
              Some(elem) => {
            let mut val = if done { JSValue::Undefined } else { next_value() }
            match self.peek_error() {
              Some(_) => return
              None => ()
            }
            let mut used_default = false
            let default_expr = elem.default
            match elem.default {
              Some(expr) =>
                if val is Undefined {
                  val = self.eval_expr(expr, env)
                  used_default = true
                }
              None => ()
            }
            if used_default {
              self.maybe_set_default_name_for_binding(
                elem.binding,
                val,
                default_expr,
              )
            }
            self.bind_pattern(elem.binding, val, env)
            match self.peek_error() {
              Some(_) => {
                if not(done) {
                      self.iterator_close(iterator)
                    }
                    return
                  }
                  None => ()
                }
              }
            }
          }
          match pattern.rest {
            None => ()
            Some(rest_binding) => {
              let rest_items : Array[JSValue] = []
              while not(done) {
                let val = next_value()
                match self.peek_error() {
                  Some(_) => return
                  None => ()
                }
                if done {
                  break
                }
                rest_items.push(val)
              }
              let rest_val = js_array_from(rest_items)
              self.bind_pattern(rest_binding, rest_val, env)
              match self.peek_error() {
                Some(_) => {
                  if not(done) {
                    self.iterator_close(iterator)
                  }
                  return
                }
                None => ()
              }
            }
          }
          if not(done) {
            self.iterator_close(iterator)
            match self.peek_error() {
              Some(_) => return
              None => ()
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
              let default_expr = elem.default
              match elem.default {
                Some(expr) =>
                  if val is Undefined {
                    val = self.eval_expr(expr, env)
                    used_default = true
                  }
                None => ()
              }
              if used_default {
                self.maybe_set_default_name_for_binding(
                  elem.binding,
                  val,
                  default_expr,
                )
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
}

///|
fn JSInterpreter::init_array_pattern(
  self : JSInterpreter,
  pattern : @parser.TsArrayBinding,
  value : JSValue,
  env : JSEnv,
  is_const : Bool,
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
          let result = self.generator_next(gen_id, Undefined)
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
            let default_expr = elem.default
            match elem.default {
              Some(expr) =>
                if val is Undefined {
                  val = self.eval_expr(expr, env)
                  used_default = true
                }
              None => ()
            }
            if used_default {
              self.maybe_set_default_name_for_binding(
                elem.binding,
                val,
                default_expr,
              )
            }
            self.init_pattern(elem.binding, val, env, is_const)
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
          self.init_pattern(rest_binding, rest_val, env, is_const)
        }
      }
      if not(done) {
        let _ = self.generator_return(gen_id, Undefined)
      }
    }
    None =>
      match self.get_iterator(value) {
        Some(iterator) => {
          let mut done = false
          let next_value = fn() -> JSValue {
            if done {
              JSValue::Undefined
            } else {
              let result = self.call_method(iterator, "next", [])
              match self.peek_error() {
                Some(_) => {
                  done = true
                  return JSValue::Undefined
                }
                None => ()
              }
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
                match self.peek_error() {
                  Some(_) => return
                  None => ()
                }
              }
              Some(elem) => {
                let mut val = if done { JSValue::Undefined } else { next_value() }
                match self.peek_error() {
                  Some(_) => return
                  None => ()
                }
                let mut used_default = false
                let default_expr = elem.default
                match elem.default {
                  Some(expr) =>
                    if val is Undefined {
                      val = self.eval_expr(expr, env)
                      used_default = true
                    }
                  None => ()
                }
                if used_default {
                  self.maybe_set_default_name_for_binding(
                    elem.binding,
                    val,
                    default_expr,
                  )
                }
                self.init_pattern(elem.binding, val, env, is_const)
                match self.peek_error() {
                  Some(_) => {
                    if not(done) {
                      self.iterator_close(iterator)
                    }
                    return
                  }
                  None => ()
                }
              }
            }
          }
          match pattern.rest {
            None => ()
            Some(rest_binding) => {
              let rest_items : Array[JSValue] = []
              while not(done) {
                let val = next_value()
                match self.peek_error() {
                  Some(_) => return
                  None => ()
                }
                if done {
                  break
                }
                rest_items.push(val)
              }
              let rest_val = js_array_from(rest_items)
              self.init_pattern(rest_binding, rest_val, env, is_const)
              match self.peek_error() {
                Some(_) => {
                  if not(done) {
                    self.iterator_close(iterator)
                  }
                  return
                }
                None => ()
              }
            }
          }
          if not(done) {
            self.iterator_close(iterator)
            match self.peek_error() {
              Some(_) => return
              None => ()
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
                let default_expr = elem.default
                match elem.default {
                  Some(expr) =>
                    if val is Undefined {
                      val = self.eval_expr(expr, env)
                      used_default = true
                    }
                  None => ()
                }
                if used_default {
                  self.maybe_set_default_name_for_binding(
                    elem.binding,
                    val,
                    default_expr,
                  )
                }
                self.init_pattern(elem.binding, val, env, is_const)
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
              self.init_pattern(rest_binding, rest_val, env, is_const)
            }
          }
        }
      }
  }
}

///|
fn JSInterpreter::assign_array_pattern(
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
          let result = self.generator_next(gen_id, Undefined)
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
            let default_expr = elem.default
            match elem.default {
              Some(expr) =>
                if val is Undefined {
                  val = self.eval_expr(expr, env)
                  used_default = true
                }
              None => ()
            }
            if used_default {
              self.maybe_set_default_name_for_binding(
                elem.binding,
                val,
                default_expr,
              )
            }
            self.assign_pattern(elem.binding, val, env)
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
          self.assign_pattern(rest_binding, rest_val, env)
        }
      }
    }
    None =>
      match self.get_iterator(value) {
        Some(iterator) => {
          let mut done = false
          let next_value = fn() -> JSValue {
            if done {
              JSValue::Undefined
            } else {
              let result = self.call_method(iterator, "next", [])
              match self.peek_error() {
                Some(_) => {
                  done = true
                  return JSValue::Undefined
                }
                None => ()
              }
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
                match self.peek_error() {
                  Some(_) => return
                  None => ()
                }
              }
              Some(elem) => {
                let mut val = if done { JSValue::Undefined } else { next_value() }
                match self.peek_error() {
                  Some(_) => return
                  None => ()
                }
                let mut used_default = false
                let default_expr = elem.default
                match elem.default {
                  Some(expr) =>
                    if val is Undefined {
                      val = self.eval_expr(expr, env)
                      used_default = true
                    }
                  None => ()
                }
                if used_default {
                  self.maybe_set_default_name_for_binding(
                    elem.binding,
                    val,
                    default_expr,
                  )
                }
                self.assign_pattern(elem.binding, val, env)
                match self.peek_error() {
                  Some(_) => {
                    if not(done) {
                      self.iterator_close_on_error(iterator)
                    }
                    return
                  }
                  None => ()
                }
              }
            }
          }
          match pattern.rest {
            None => ()
            Some(rest_binding) =>
              match rest_binding {
                @parser.TsBinding::Target(target_expr) => {
                  let prepared = self.prepare_assignment_target(target_expr, env)
                  if self.peek_error() is Some(_) {
                    if not(done) {
                      self.iterator_close_on_error(iterator)
                    }
                    return
                  }
                  match prepared {
                    Some(target) => {
                      let rest_items : Array[JSValue] = []
                      while not(done) {
                        let val = next_value()
                        match self.peek_error() {
                          Some(_) => return
                          None => ()
                        }
                        if done {
                          break
                        }
                        rest_items.push(val)
                      }
                      let rest_val = js_array_from(rest_items)
                      self.assign_prepared_target(target, rest_val, env)
                      match self.peek_error() {
                        Some(_) => {
                          if not(done) {
                            self.iterator_close_on_error(iterator)
                          }
                          return
                        }
                        None => ()
                      }
                    }
                    None => {
                      if not(done) {
                        self.iterator_close_on_error(iterator)
                      }
                      return
                    }
                  }
                }
                _ => {
                  let rest_items : Array[JSValue] = []
                  while not(done) {
                    let val = next_value()
                    match self.peek_error() {
                      Some(_) => return
                      None => ()
                    }
                    if done {
                      break
                    }
                    rest_items.push(val)
                  }
                  let rest_val = js_array_from(rest_items)
                  self.assign_pattern(rest_binding, rest_val, env)
                  match self.peek_error() {
                    Some(_) => {
                      if not(done) {
                        self.iterator_close_on_error(iterator)
                      }
                      return
                    }
                    None => ()
                  }
                }
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
                let default_expr = elem.default
                match elem.default {
                  Some(expr) =>
                    if val is Undefined {
                      val = self.eval_expr(expr, env)
                      used_default = true
                    }
                  None => ()
                }
                if used_default {
                  self.maybe_set_default_name_for_binding(
                    elem.binding,
                    val,
                    default_expr,
                  )
                }
                self.assign_pattern(elem.binding, val, env)
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
              self.assign_pattern(rest_binding, rest_val, env)
            }
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
    let key = self.eval_object_binding_key(prop, env)
    if self.peek_error() is Some(_) {
      return
    }
    used_keys.push(key)
    let mut val = self.get_prop_value(value, key)
    let mut used_default = false
    let default_expr = prop.default
    match prop.default {
      Some(expr) =>
        if val is Undefined {
          val = self.eval_expr(expr, env)
          used_default = true
        }
      None => ()
    }
    if used_default {
      self.maybe_set_default_name_for_binding(
        prop.binding,
        val,
        default_expr,
      )
    }
    self.bind_pattern(prop.binding, val, env)
    if self.peek_error() is Some(_) {
      return
    }
  }
  match pattern.rest {
    None => ()
    Some(rest_name) => {
      let rest_obj = self.new_object()
      match value {
        Object(map) => {
          for prop in map.props {
            if not(prop.enumerable) {
              continue
            }
            if not(contains_key(used_keys, prop.key)) {
              let val = self.eval_prop_value(JSValue::Object(map), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)
            }
          }
        }
        Array(arr) => {
          for i, item in arr.items {
            let key = i.to_string()
            if not(contains_key(used_keys, key)) && arr.present[i] {
              let _ = js_set_prop(rest_obj, key, item)
            }
          }
          for prop in arr.props {
            if not(contains_key(used_keys, prop.key)) {
              if not(prop.enumerable) {
                continue
              }
              let val = self.eval_prop_value(JSValue::Array(arr), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)
            }
          }
        }
        Function(closure) => {
          for prop in closure.props {
            if not(contains_key(used_keys, prop.key)) {
              if not(prop.enumerable) {
                continue
              }
              let val = self.eval_prop_value(JSValue::Function(closure), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)
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
fn JSInterpreter::init_object_pattern(
  self : JSInterpreter,
  pattern : @parser.TsObjectBinding,
  value : JSValue,
  env : JSEnv,
  is_const : Bool,
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
    let key = self.eval_object_binding_key(prop, env)
    if self.peek_error() is Some(_) {
      return
    }
    used_keys.push(key)
    let mut val = self.get_prop_value(value, key)
    let mut used_default = false
    let default_expr = prop.default
    match prop.default {
      Some(expr) =>
        if val is Undefined {
          val = self.eval_expr(expr, env)
          used_default = true
        }
      None => ()
    }
    if used_default {
      self.maybe_set_default_name_for_binding(
        prop.binding,
        val,
        default_expr,
      )
    }
    self.init_pattern(prop.binding, val, env, is_const)
    if self.peek_error() is Some(_) {
      return
    }
  }
  match pattern.rest {
    None => ()
    Some(rest_name) => {
      let rest_obj = self.new_object()
      match value {
        Object(map) => {
          for prop in map.props {
            if not(prop.enumerable) {
              continue
            }
            if not(contains_key(used_keys, prop.key)) {
              let val = self.eval_prop_value(JSValue::Object(map), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)
            }
          }
        }
        Array(arr) => {
          for i, item in arr.items {
            let key = i.to_string()
            if not(contains_key(used_keys, key)) && arr.present[i] {
              let _ = js_set_prop(rest_obj, key, item)
            }
          }
          for prop in arr.props {
            if not(contains_key(used_keys, prop.key)) {
              if not(prop.enumerable) {
                continue
              }
              let val = self.eval_prop_value(JSValue::Array(arr), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)
            }
          }
        }
        Function(closure) => {
          for prop in closure.props {
            if not(contains_key(used_keys, prop.key)) {
              if not(prop.enumerable) {
                continue
              }
              let val = self.eval_prop_value(JSValue::Function(closure), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)
            }
          }
        }
        _ => ()
      }
      env.initialize(rest_name, rest_obj, is_const)
    }
  }
}

///|
fn JSInterpreter::assign_object_pattern(
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
    let key = self.eval_object_binding_key(prop, env)
    if self.peek_error() is Some(_) {
      return
    }
    used_keys.push(key)
    let mut val = self.get_prop_value(value, key)
    let mut used_default = false
    let default_expr = prop.default
    match prop.default {
      Some(expr) =>
        if val is Undefined {
          val = self.eval_expr(expr, env)
          used_default = true
        }
      None => ()
    }
    if used_default {
      self.maybe_set_default_name_for_binding(
        prop.binding,
        val,
        default_expr,
      )
    }
    self.assign_pattern(prop.binding, val, env)
    if self.peek_error() is Some(_) {
      return
    }
  }
  match pattern.rest {
    None => ()
    Some(rest_name) => {
      let rest_obj = self.new_object()
      match value {
        Object(map) => {
          for prop in map.props {
            if not(prop.enumerable) {
              continue
            }
            if not(contains_key(used_keys, prop.key)) {
              let val = self.eval_prop_value(JSValue::Object(map), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)
            }
          }
        }
        Array(arr) => {
          for i, item in arr.items {
            let key = i.to_string()
            if not(contains_key(used_keys, key)) && arr.present[i] {
              let _ = js_set_prop(rest_obj, key, item)
            }
          }
          for prop in arr.props {
            if not(contains_key(used_keys, prop.key)) {
              if not(prop.enumerable) {
                continue
              }
              let val = self.eval_prop_value(JSValue::Array(arr), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)
            }
          }
        }
        Function(closure) => {
          for prop in closure.props {
            if not(contains_key(used_keys, prop.key)) {
              if not(prop.enumerable) {
                continue
              }
              let val = self.eval_prop_value(JSValue::Function(closure), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)
            }
          }
        }
        _ => ()
      }
      self.assign_ident(rest_name, rest_obj, env)
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
          self.maybe_set_default_name_for_binding(binding, val, param.default)
        }
        self.bind_pattern(binding, val, env)
      }
      None => {
        if used_default {
          self.maybe_set_default_name(val, param.name, param.default)
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
fn JSInterpreter::generator_next(
  self : JSInterpreter,
  gen_id : Int,
  sent : JSValue,
) -> JSValue {
  if gen_id < 0 || gen_id >= self.generators.length() {
    return self.set_error_kind("TypeError", "Invalid generator")
  }
  let state = self.generators[gen_id]
  if state.done {
    return self.make_iter_result(Undefined, true)
  }
  self.current_gen_id = Some(gen_id)
  match state.cont {
    Some(cont_fn) => {
      state.cont = None
      match cont_fn(sent) {
        GenSignal::Continue => {
          self.generators[gen_id] = state
        }
        GenSignal::Yield(val) => {
          self.generators[gen_id] = state
          self.current_gen_id = None
          return self.make_iter_result(val, false)
        }
        GenSignal::Suspend(val, cont) => {
          state.cont = Some(cont)
          self.generators[gen_id] = state
          self.current_gen_id = None
          return self.make_iter_result(val, false)
        }
        GenSignal::Return(val) => {
          state.done = true
          self.generators[gen_id] = state
          self.current_gen_id = None
          return self.make_iter_result(val, true)
        }
      }
      match self.peek_error() {
        Some(err) => {
          state.done = true
          self.generators[gen_id] = state
          self.current_gen_id = None
          return err
        }
        None => ()
      }
    }
    None => ()
  }
  let stmts = state.func.body.stmts
  while state.index < stmts.length() {
    let stmt = stmts[state.index]
    state.index = state.index + 1
    match self.exec_stmt_gen(stmt, state.env) {
      GenSignal::Continue => ()
      GenSignal::Yield(val) => {
        self.generators[gen_id] = state
        self.current_gen_id = None
        return self.make_iter_result(val, false)
      }
      GenSignal::Suspend(val, cont) => {
        state.cont = Some(cont)
        self.generators[gen_id] = state
        self.current_gen_id = None
        return self.make_iter_result(val, false)
      }
      GenSignal::Return(val) => {
        state.done = true
        self.generators[gen_id] = state
        self.current_gen_id = None
        return self.make_iter_result(val, true)
      }
    }
    match self.peek_error() {
      Some(err) => {
        state.done = true
        self.generators[gen_id] = state
        self.current_gen_id = None
        return err
      }
      None => ()
    }
  }
  state.done = true
  self.generators[gen_id] = state
  self.current_gen_id = None
  self.make_iter_result(Undefined, true)
}

///|
fn JSInterpreter::generator_return(
  self : JSInterpreter,
  gen_id : Int,
  value : JSValue,
) -> JSValue {
  if gen_id < 0 || gen_id >= self.generators.length() {
    return self.set_error_kind("TypeError", "Invalid generator")
  }
  let state = self.generators[gen_id]
  if state.done {
    return self.make_iter_result(value, true)
  }
  for iterator in state.active_iterators {
    self.iterator_close(iterator)
  }
  state.active_iterators = []
  state.done = true
  state.cont = None
  self.generators[gen_id] = state
  match self.peek_error() {
    Some(err) => err
    None => self.make_iter_result(value, true)
  }
}

///|
fn JSInterpreter::generator_throw(
  self : JSInterpreter,
  gen_id : Int,
  value : JSValue,
) -> JSValue {
  if gen_id < 0 || gen_id >= self.generators.length() {
    return self.set_error_kind("TypeError", "Invalid generator")
  }
  let state = self.generators[gen_id]
  self.last_error = Some(value)
  for iterator in state.active_iterators {
    self.iterator_close_on_error(iterator)
  }
  state.active_iterators = []
  state.done = true
  state.cont = None
  self.generators[gen_id] = state
  value
}

///|
fn JSInterpreter::iter_result_value_done(
  self : JSInterpreter,
  result : JSValue,
) -> (Bool, JSValue) {
  match result {
    Object(_) | Array(_) | Function(_) => {
      let done_val = self.get_prop_value(result, "done")
      let done = done_val.to_boolean()
      let val = self.get_prop_value(result, "value")
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
      gen_to_signal(self.eval_expr_gen(expr, env), (_val) =>
        match self.peek_error() {
          Some(err) => GenSignal::Return(err)
          None => GenSignal::Continue
        }
      )
    @parser.TsStmt::Assign(name, value) =>
      gen_to_signal(self.eval_expr_gen(value, env), (val) => {
        self.assign_ident(name, val, env)
        match self.peek_error() {
          Some(err) => GenSignal::Return(err)
          None => GenSignal::Continue
        }
      })
    @parser.TsStmt::PropAssign(obj_expr, prop, value_expr) =>
      gen_to_signal(
        gen_bind(self.eval_expr_gen(obj_expr, env), (obj) =>
          gen_bind(self.eval_expr_gen(value_expr, env), (val) => {
            self.set_prop_value(obj, prop, val)
            GenValue::Value(val)
          })
        ),
        (_val) =>
          match self.peek_error() {
            Some(err) => GenSignal::Return(err)
            None => GenSignal::Continue
          },
      )
    @parser.TsStmt::IndexAssign(obj_expr, idx_expr, value_expr) =>
      gen_to_signal(
        gen_bind(self.eval_expr_gen(obj_expr, env), (obj) =>
          gen_bind(self.eval_expr_gen(idx_expr, env), (idx) =>
            gen_bind(self.eval_expr_gen(value_expr, env), (val) => {
              let key = idx.to_js_string()
              self.set_prop_value(obj, key, val)
              GenValue::Value(val)
            })
          )
        ),
        (_val) =>
          match self.peek_error() {
            Some(err) => GenSignal::Return(err)
            None => GenSignal::Continue
          },
      )
    @parser.TsStmt::Return(opt) =>
      match opt {
        Some(e) =>
          gen_to_signal(self.eval_expr_gen(e, env), (val) =>
            GenSignal::Return(val)
          )
        None => GenSignal::Return(JSValue::Undefined)
      }
    @parser.TsStmt::If(cond, then_block, else_block) =>
      gen_to_signal(self.eval_expr_gen(cond, env), (cond_val) =>
        match self.peek_error() {
          Some(err) => GenSignal::Return(err)
          None =>
            if cond_val.to_boolean() {
              self.exec_block_gen(then_block, env)
            } else {
              match else_block {
                Some(block) => self.exec_block_gen(block, env)
                None => GenSignal::Continue
              }
            }
        }
      )
    @parser.TsStmt::Block(block) => self.exec_block_gen(block, env)
    _ =>
      match self.exec_stmt(stmt, env) {
        Some(BreakSignal(_)) | Some(ContinueSignal(_)) => GenSignal::Continue
        Some(val) => GenSignal::Return(val)
        None => GenSignal::Continue
      }
  }
}

///|
fn JSInterpreter::exec_block_gen(
  self : JSInterpreter,
  block : @parser.TsBlock,
  env : JSEnv,
) -> GenSignal {
  for inner in block.stmts {
    match self.exec_stmt_gen(inner, env) {
      GenSignal::Continue => ()
      other => return other
    }
  }
  GenSignal::Continue
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

        let args_obj = self.make_arguments(args)
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
      let mut body_env = call_env
      match closure.body {
        Ast(func_def) => {
          let has_param_expr = has_param_expressions(func_def.params)
          if has_param_expr {
            let param_names = collect_param_names(func_def.params)
            if param_names.length() > 0 {
              call_env.define_var(
                "__param_names__",
                js_array_from(string_array_to_js(param_names)),
              )
            }
          }
          self.bind_params(func_def.params, args, call_env)
          if has_param_expr {
            body_env = js_new_env(Some(call_env))
          }
        }
        _ =>
          for i, param in closure.params {
            let val = if i < args.length() { args[i] } else { Undefined }
            call_env.define_var(param, val)
          }
      }

      // run
      match closure.body {
        Ast(func_def) =>
          match self.exec_block(func_def.body, body_env) {
            Some(val) => val
            None => Undefined
          }
        Native(name) =>
          if name == "Promise" {
            if not(new_target.is_undefined()) {
              self.promise_construct_with_instance(this_arg, args)
            } else {
              self.call_native(name, this_arg, args)
            }
          } else if name == "Iterator" {
            if new_target.is_undefined() {
              self.set_error_kind("TypeError", "Iterator constructor must be called with new")
            } else {
              match js_strict_eq(new_target, func) {
                Bool(true) =>
                  self.set_error_kind("TypeError", "Iterator is not directly constructible")
                _ => this_arg
              }
            }
          } else if name == "__export_get__" {
            let name_val = js_get_prop(func, "__export_name")
            let module_val = js_get_prop(func, "__export_module")
            match (module_val, name_val) {
              (Object(_) | Function(_) | Array(_), String(n)) =>
                js_get_prop(module_val, n)
              _ =>
                match name_val {
                  String(n) => closure.env.get(n)
                  _ => Undefined
                }
            }
          } else {
            self.call_native(name, this_arg, args)
          }
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
        _ => self.set_error_kind("TypeError", "object is not callable")
      }
    }
    _ => self.set_error_kind("TypeError", "value is not callable")
  }
}
