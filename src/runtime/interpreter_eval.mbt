///|
// / expression
pub fn JSInterpreter::eval_expr(
  self : JSInterpreter,
  expr : @ast.TsExpr,
  env : JSEnv,
) -> JSValue {
  self.tick()
  match expr {
    @ast.TsExpr::IntLit(n) => Number(n.to_double())
    @ast.TsExpr::NumberLit(n) => Number(n)
    @ast.TsExpr::BigIntLit(s) => {
      let obj = self.new_object()
      let _ = js_set_prop(obj, "__class", String("BigInt"))
      let _ = js_set_prop(obj, "value", String(s))
      obj
    }
    @ast.TsExpr::BoolLit(b) => Bool(b)
    @ast.TsExpr::StringLit(s) => String(s)
    @ast.TsExpr::NullLit => Null
    @ast.TsExpr::ArrayHole => Undefined
    @ast.TsExpr::Spread(_) => {
      let _ = self.set_error_kind("TypeError", "Unexpected spread expression")
      Undefined
    }
    @ast.TsExpr::Yield(_) => Undefined
    @ast.TsExpr::YieldStar(_) => Undefined
    @ast.TsExpr::Var(name) =>
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
    @ast.TsExpr::Seq(left, right) => {
      let _ = self.eval_expr(left, env)
      self.eval_expr(right, env)
    }
    @ast.TsExpr::BinOp(op, left, right) => {
      match op {
        @ast.TsBinOp::And => {
          let lval = self.eval_expr(left, env)
          if lval.to_boolean() {
            self.eval_expr(right, env)
          } else {
            lval
          }
        }
        @ast.TsBinOp::Or => {
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
        @ast.TsBinOp::Add => {
          let lprim = self.to_primitive_for_add(lval)
          let rprim = self.to_primitive_for_add(rval)
          match (lprim, rprim) {
            (String(_), _) | (_, String(_)) =>
              String(lprim.to_js_string() + rprim.to_js_string())
            _ => js_add(lprim, rprim)
          }
        }
        @ast.TsBinOp::Sub => js_sub(lval, rval)
        @ast.TsBinOp::Mul => js_mul(lval, rval)
        @ast.TsBinOp::Div => js_div(lval, rval)
        @ast.TsBinOp::Mod => js_mod(lval, rval)
        @ast.TsBinOp::Pow => Number(@math.pow(lval.to_number(), rval.to_number()))
        @ast.TsBinOp::BitAnd => {
          let li = lval.to_number().to_int()
          let ri = rval.to_number().to_int()
          Number((li & ri).to_double())
        }
        @ast.TsBinOp::BitOr => {
          let li = lval.to_number().to_int()
          let ri = rval.to_number().to_int()
          Number((li | ri).to_double())
        }
        @ast.TsBinOp::BitXor => {
          let li = lval.to_number().to_int()
          let ri = rval.to_number().to_int()
          Number((li ^ ri).to_double())
        }
        @ast.TsBinOp::Shl => {
          let li = lval.to_number().to_int()
          let ri = rval.to_number().to_int()
          let shift = ri & 31
          Number((li << shift).to_double())
        }
        @ast.TsBinOp::Shr => {
          let li = lval.to_number().to_int()
          let ri = rval.to_number().to_int()
          let shift = ri & 31
          Number((li >> shift).to_double())
        }
        @ast.TsBinOp::UShr => {
          let li = lval.to_number()
          let ri = rval.to_number().to_int()
          let shift = ri & 31
          let u = if li < 0.0 { li + 4294967296.0 } else { li }
          let denom = @math.pow(2.0, shift.to_double())
          Number(@math.floor(u / denom))
        }
        @ast.TsBinOp::BinLt => js_lt(lval, rval)
        @ast.TsBinOp::BinLe => js_le(lval, rval)
        @ast.TsBinOp::BinGt => js_gt(lval, rval)
        @ast.TsBinOp::BinGe => js_ge(lval, rval)
        @ast.TsBinOp::BinEq => js_strict_eq(lval, rval) // === (strict equality)
        @ast.TsBinOp::BinNe => js_strict_ne(lval, rval) // !== (strict inequality)
        @ast.TsBinOp::AbstractEq => js_eq(lval, rval) // == (abstract equality)
        @ast.TsBinOp::AbstractNe => js_ne(lval, rval) // != (abstract inequality)
        @ast.TsBinOp::Instanceof => Bool(self.instanceof(lval, rval))
        @ast.TsBinOp::In => Bool(js_has_prop(rval, lval.to_js_string()))
        @ast.TsBinOp::And =>
          // handled above for short-circuit
          Undefined
        @ast.TsBinOp::Or =>
          // handled above for short-circuit
          Undefined
          }
        }
      }
    }
    @ast.TsExpr::UnaryOp(op, operand) =>
      match op {
        @ast.TsUnaryOp::PreInc =>
          // ++x:
          match operand {
            @ast.TsExpr::Var(name) => {
              let old_val = env.get(name)
              let new_val = js_add(old_val, Number(1.0))
              self.assign_ident(name, new_val, env)
              new_val
            }
            @ast.TsExpr::PropAccess(obj_expr, prop) => {
              let obj = self.eval_expr(obj_expr, env)
              let old_val = self.get_prop_value(obj, prop)
              let new_val = js_add(old_val, Number(1.0))
              self.set_prop_value(obj, prop, new_val)
              new_val
            }
            @ast.TsExpr::IndexAccess(obj_expr, idx_expr) => {
              let obj = self.eval_expr(obj_expr, env)
              let idx = self.eval_expr(idx_expr, env)
              let key = idx.to_js_string()
              let old_val = self.get_prop_value(obj, key)
              let new_val = js_add(old_val, Number(1.0))
              self.set_prop_value(obj, key, new_val)
              new_val
            }
            _ => {
              let val = self.eval_expr(operand, env)
              js_add(val, Number(1.0))
            }
          }
        @ast.TsUnaryOp::PreDec =>
          // --x:
          match operand {
            @ast.TsExpr::Var(name) => {
              let old_val = env.get(name)
              let new_val = js_sub(old_val, Number(1.0))
              self.assign_ident(name, new_val, env)
              new_val
            }
            @ast.TsExpr::PropAccess(obj_expr, prop) => {
              let obj = self.eval_expr(obj_expr, env)
              let old_val = self.get_prop_value(obj, prop)
              let new_val = js_sub(old_val, Number(1.0))
              self.set_prop_value(obj, prop, new_val)
              new_val
            }
            @ast.TsExpr::IndexAccess(obj_expr, idx_expr) => {
              let obj = self.eval_expr(obj_expr, env)
              let idx = self.eval_expr(idx_expr, env)
              let key = idx.to_js_string()
              let old_val = self.get_prop_value(obj, key)
              let new_val = js_sub(old_val, Number(1.0))
              self.set_prop_value(obj, key, new_val)
              new_val
            }
            _ => {
              let val = self.eval_expr(operand, env)
              js_sub(val, Number(1.0))
            }
          }
        @ast.TsUnaryOp::PostInc =>
          // x++:
          match operand {
            @ast.TsExpr::Var(name) => {
              let old_val = env.get(name)
              let new_val = js_add(old_val, Number(1.0))
              self.assign_ident(name, new_val, env)
              old_val
            }
            @ast.TsExpr::PropAccess(obj_expr, prop) => {
              let obj = self.eval_expr(obj_expr, env)
              let old_val = self.get_prop_value(obj, prop)
              let new_val = js_add(old_val, Number(1.0))
              self.set_prop_value(obj, prop, new_val)
              old_val
            }
            @ast.TsExpr::IndexAccess(obj_expr, idx_expr) => {
              let obj = self.eval_expr(obj_expr, env)
              let idx = self.eval_expr(idx_expr, env)
              let key = idx.to_js_string()
              let old_val = self.get_prop_value(obj, key)
              let new_val = js_add(old_val, Number(1.0))
              self.set_prop_value(obj, key, new_val)
              old_val
            }
            _ => {
              let val = self.eval_expr(operand, env)
              val
            }
          }
        @ast.TsUnaryOp::PostDec =>
          // x--:
          match operand {
            @ast.TsExpr::Var(name) => {
              let old_val = env.get(name)
              let new_val = js_sub(old_val, Number(1.0))
              self.assign_ident(name, new_val, env)
              old_val
            }
            @ast.TsExpr::PropAccess(obj_expr, prop) => {
              let obj = self.eval_expr(obj_expr, env)
              let old_val = self.get_prop_value(obj, prop)
              let new_val = js_sub(old_val, Number(1.0))
              self.set_prop_value(obj, prop, new_val)
              old_val
            }
            @ast.TsExpr::IndexAccess(obj_expr, idx_expr) => {
              let obj = self.eval_expr(obj_expr, env)
              let idx = self.eval_expr(idx_expr, env)
              let key = idx.to_js_string()
              let old_val = self.get_prop_value(obj, key)
              let new_val = js_sub(old_val, Number(1.0))
              self.set_prop_value(obj, key, new_val)
              old_val
            }
            _ => {
              let val = self.eval_expr(operand, env)
              val
            }
          }
        @ast.TsUnaryOp::Neg => js_neg(self.eval_expr(operand, env))
        @ast.TsUnaryOp::Not => js_not(self.eval_expr(operand, env))
        @ast.TsUnaryOp::Plus => js_pos(self.eval_expr(operand, env))
        @ast.TsUnaryOp::Typeof =>
          match operand {
            @ast.TsExpr::Var(name) =>
              if env.has(name) || js_has_prop(self.global_env.get("globalThis"), name) {
                js_typeof(self.eval_expr(operand, env))
              } else {
                String("undefined")
              }
            _ => js_typeof(self.eval_expr(operand, env))
          }
        @ast.TsUnaryOp::Delete =>
          match operand {
            @ast.TsExpr::PropAccess(obj_expr, prop) => {
              let obj = self.eval_expr(obj_expr, env)
              Bool(js_delete_prop(obj, prop))
            }
            @ast.TsExpr::IndexAccess(obj_expr, idx_expr) => {
              let obj = self.eval_expr(obj_expr, env)
              let idx = self.eval_expr(idx_expr, env)
              let key = idx.to_js_string()
              Bool(js_delete_prop(obj, key))
            }
            @ast.TsExpr::Var(name) =>
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
        @ast.TsUnaryOp::Void => {
          let _ = self.eval_expr(operand, env)
          Undefined
        }
    }
    @ast.TsExpr::Call(name, args) => {
      if name == "eval" {
        let arg_values = self.eval_args(args, env)
        match self.peek_error() {
          Some(_) => return self.error_or_undefined()
          None => ()
        }
        let src =
          if arg_values.length() > 0 {
            arg_values[0].to_js_string()
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
            @ast.TsExpr::Var(rest_name) if rest_name == "__super_args__" => {
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
            _ => {
              let values = self.eval_args(args, env)
              for value in values {
                arg_values.push(value)
              }
            }
          }
        } else {
          let values = self.eval_args(args, env)
          for value in values {
            arg_values.push(value)
          }
        }
        match self.peek_error() {
          Some(_) => return self.error_or_undefined()
          None => ()
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
      let arg_values = self.eval_args(args, env)
      match self.peek_error() {
        Some(_) => return self.error_or_undefined()
        None => ()
      }
      self.call_function(func, Undefined, arg_values)
    }
    @ast.TsExpr::CallExpr(callee, args) => {
      let arg_values = self.eval_args(args, env)
      match self.peek_error() {
        Some(_) => return self.error_or_undefined()
        None => ()
      }
      match callee {
        @ast.TsExpr::IndexAccess(obj_expr, idx_expr) => {
          let obj = self.eval_expr(obj_expr, env)
          let idx = self.eval_expr(idx_expr, env)
          let key = idx.to_js_string()
          let func = self.get_prop_value(obj, key)
          self.call_function(func, obj, arg_values)
        }
        @ast.TsExpr::PropAccess(obj_expr, prop) => {
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
    @ast.TsExpr::MethodCall(obj_expr, method_name, args) => {
      match obj_expr {
        @ast.TsExpr::Var(name) if name == "super" && env.has("__super_proto") => {
          let super_proto = env.get("__super_proto")
          let super_this = if env.has("__super_this") { env.get("__super_this") } else { env.get("this") }
          let arg_values = self.eval_args(args, env)
          match self.peek_error() {
            Some(_) => return self.error_or_undefined()
            None => ()
          }
          let func = self.get_prop_value(super_proto, method_name)
          return self.call_function(func, super_this, arg_values)
        }
        _ => ()
      }
      let obj = self.eval_expr(obj_expr, env)
      let arg_values = self.eval_args(args, env)
      match self.peek_error() {
        Some(_) => return self.error_or_undefined()
        None => ()
      }
      self.call_method(obj, method_name, arg_values)
    }
    @ast.TsExpr::ArrayLit(elements) => {
      let arr = js_new_array()
      let mut idx = 0
      for elem in elements {
        match elem {
          @ast.TsExpr::ArrayHole => idx += 1
          @ast.TsExpr::Spread(spread_expr) => {
            let spread_val = self.eval_expr(spread_expr, env)
            match self.peek_error() {
              Some(_) => return self.error_or_undefined()
              None => ()
            }
            let values =
              match self.collect_spread_values(spread_val) {
                Some(list) => list
                None => return self.error_or_undefined()
              }
            for value in values {
              let _ = js_set_prop(arr, idx.to_string(), value)
              idx += 1
            }
          }
          _ => {
            let value = self.eval_expr(elem, env)
            match self.peek_error() {
              Some(_) => return self.error_or_undefined()
              None => ()
            }
            let _ = js_set_prop(arr, idx.to_string(), value)
            idx += 1
          }
        }
      }
      let _ = js_set_prop(arr, "length", Number(idx.to_double()))
      arr
    }
    @ast.TsExpr::ObjectLit(fields) => {
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
    @ast.TsExpr::IndexAccess(obj_expr, idx_expr) => {
      let obj = self.eval_expr(obj_expr, env)
      let idx = self.eval_expr(idx_expr, env)
      let key = idx.to_js_string()
      self.get_prop_value(obj, key)
    }
    @ast.TsExpr::PropAccess(obj_expr, prop) => {
      match obj_expr {
        @ast.TsExpr::Var(name) if name == "super" && env.has("__super_proto") => {
          let super_proto = env.get("__super_proto")
          self.get_prop_value(super_proto, prop)
        }
        _ => {
          let obj = self.eval_expr(obj_expr, env)
          self.get_prop_value(obj, prop)
        }
      }
    }
    @ast.TsExpr::CompoundAssignExpr(left, op, right) => {
      match left {
        @ast.TsExpr::Var(name) => {
          let current = env.get(name)
          let val = self.eval_expr(right, env)
          let new_val = apply_compound_op(op, current, val)
          self.assign_ident(name, new_val, env)
          new_val
        }
        @ast.TsExpr::PropAccess(obj_expr, prop) => {
          let obj = self.eval_expr(obj_expr, env)
          let current = self.get_prop_value(obj, prop)
          let val = self.eval_expr(right, env)
          let new_val = apply_compound_op(op, current, val)
          let _ = js_set_prop(obj, prop, new_val)
          new_val
        }
        @ast.TsExpr::IndexAccess(obj_expr, idx_expr) => {
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
    @ast.TsExpr::AssignExpr(name, val_expr) => {
      let val = self.eval_expr(val_expr, env)
      self.assign_ident(name, val, env)
      val
    }
    @ast.TsExpr::AssignPattern(binding, val_expr) => {
      let val = self.eval_expr(val_expr, env)
      self.assign_pattern(binding, val, env)
      val
    }
    @ast.TsExpr::PropAssignExpr(obj_expr, prop, val_expr) => {
      let obj = self.eval_expr(obj_expr, env)
      let val = self.eval_expr(val_expr, env)
      self.set_prop_value(obj, prop, val)
      val
    }
    @ast.TsExpr::IndexAssignExpr(obj_expr, idx_expr, val_expr) => {
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
    @ast.TsExpr::Cond(cond, then_expr, else_expr) => {
      let cond_val = self.eval_expr(cond, env)
      if cond_val.to_boolean() {
        self.eval_expr(then_expr, env)
      } else {
        self.eval_expr(else_expr, env)
      }
    }
    @ast.TsExpr::New(class_name, args) => {
      let arg_values = self.eval_args(args, env)
      match self.peek_error() {
        Some(_) => return self.error_or_undefined()
        None => ()
      }
      self.new_instance(class_name, arg_values, env)
    }
    @ast.TsExpr::NewExpr(callee_expr, args) => {
      let ctor = self.eval_expr(callee_expr, env)
      let arg_values = self.eval_args(args, env)
      match self.peek_error() {
        Some(_) => return self.error_or_undefined()
        None => ()
      }
      match ctor {
        Function(_) => self.construct_with(ctor, ctor, arg_values)
        _ => self.new_object()
      }
    }
    @ast.TsExpr::ArrowFunc(params, body) => {
      let param_names : Array[String] = []
      for param in params {
        param_names.push(param.name)
      }
      let is_strict = match body {
        @ast.TsArrowBody::ArrowExpr(_) => env.has("__strict__")
        @ast.TsArrowBody::ArrowBlock(block) =>
          self.is_strict_body(block, env.has("__strict__"))
      }
      let closure = JSValue::Function({
        id: fresh_function_id(),
        params: param_names,
        body: match body {
          @ast.TsArrowBody::ArrowExpr(expr) =>
            Ast({
              name: "<arrow>",
              params,
              return_type: @ast.TsType::Any,
              body: { stmts: [@ast.TsStmt::Return(Some(expr))] },
              is_generator: false,
            })
          @ast.TsArrowBody::ArrowBlock(block) =>
            Ast({
              name: "<arrow>",
              params,
              return_type: @ast.TsType::Any,
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
    @ast.TsExpr::FuncExpr(func) => {
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
fn JSInterpreter::eval_args(
  self : JSInterpreter,
  args : Array[@ast.TsExpr],
  env : JSEnv,
) -> Array[JSValue] {
  let arg_values : Array[JSValue] = []
  for arg in args {
    match arg {
      @ast.TsExpr::Spread(spread_expr) => {
        let spread_val = self.eval_expr(spread_expr, env)
        match self.peek_error() {
          Some(_) => return arg_values
          None => ()
        }
        let values =
          match self.collect_spread_values(spread_val) {
            Some(list) => list
            None => return arg_values
          }
        for value in values {
          arg_values.push(value)
        }
      }
      _ => {
        let value = self.eval_expr(arg, env)
        match self.peek_error() {
          Some(_) => return arg_values
          None => ()
        }
        arg_values.push(value)
      }
    }
  }
  arg_values
}

///|
fn JSInterpreter::eval_expr_gen(
  self : JSInterpreter,
  expr : @ast.TsExpr,
  env : JSEnv,
) -> GenValue {
  if not(expr_has_yield(expr)) {
    return GenValue::Value(self.eval_expr(expr, env))
  }
  match expr {
    @ast.TsExpr::Yield(opt) =>
      match opt {
        Some(inner) =>
          gen_bind(self.eval_expr_gen(inner, env), (yielded) =>
            GenValue::Yield(yielded, (sent) => GenValue::Value(sent))
          )
        None => GenValue::Yield(JSValue::Undefined, (sent) => GenValue::Value(sent))
      }
    @ast.TsExpr::YieldStar(inner) => self.eval_yield_star(inner, env)
    @ast.TsExpr::Seq(left, right) =>
      gen_bind(self.eval_expr_gen(left, env), (_unused) =>
        self.eval_expr_gen(right, env)
      )
    @ast.TsExpr::AssignExpr(name, value) =>
      gen_bind(self.eval_expr_gen(value, env), (val) => {
        self.assign_ident(name, val, env)
        GenValue::Value(val)
      })
    @ast.TsExpr::AssignPattern(binding, value) =>
      gen_bind(self.eval_expr_gen(value, env), (val) =>
        gen_bind(self.assign_pattern_gen(binding, val, env), (_unused) =>
          GenValue::Value(val)
        )
      )
    @ast.TsExpr::PropAccess(obj_expr, prop) =>
      gen_bind(self.eval_expr_gen(obj_expr, env), (obj) =>
        GenValue::Value(self.get_prop_value(obj, prop))
      )
    @ast.TsExpr::IndexAccess(obj_expr, idx_expr) =>
      gen_bind(self.eval_expr_gen(obj_expr, env), (obj) =>
        gen_bind(self.eval_expr_gen(idx_expr, env), (idx) => {
          let key = idx.to_js_string()
          GenValue::Value(self.get_prop_value(obj, key))
        })
      )
    @ast.TsExpr::PropAssignExpr(obj_expr, prop, value_expr) =>
      gen_bind(self.eval_expr_gen(obj_expr, env), (obj) =>
        gen_bind(self.eval_expr_gen(value_expr, env), (val) => {
          self.set_prop_value(obj, prop, val)
          GenValue::Value(val)
        })
      )
    @ast.TsExpr::IndexAssignExpr(obj_expr, idx_expr, value_expr) =>
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
  stmt : @ast.TsStmt,
  names : Array[String],
) -> Unit {
  match stmt {
    @ast.TsStmt::Let(binding, _, _) | @ast.TsStmt::Const(binding, _, _) =>
      collect_binding_names(binding, names)
    @ast.TsStmt::Block(block) =>
      for inner in block.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    @ast.TsStmt::Label(_, inner) => collect_decl_names_from_stmt(inner, names)
    @ast.TsStmt::If(_, then_block, else_block) => {
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
    @ast.TsStmt::While(_, body) =>
      for inner in body.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    @ast.TsStmt::For(init, _, _, body) => {
      match init {
        Some(inner) => collect_decl_names_from_stmt(inner, names)
        None => ()
      }
      for inner in body.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    }
    @ast.TsStmt::Switch(_, cases) => {
      for case_ in cases {
        for inner in case_.body.stmts {
          collect_decl_names_from_stmt(inner, names)
        }
      }
    }
    @ast.TsStmt::ForOf(kind, binding, _, _, body) => {
      if kind != @ast.TsForOfKind::Assign {
        collect_binding_names(binding, names)
      }
      for inner in body.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    }
    @ast.TsStmt::ForIn(kind, binding, _, _, body) => {
      if kind != @ast.TsForOfKind::Assign {
        collect_binding_names(binding, names)
      }
      for inner in body.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    }
    @ast.TsStmt::With(_, body) =>
      for inner in body.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
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
  block : @ast.TsBlock,
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
  block : @ast.TsBlock,
  env : JSEnv,
) -> JSValue {
  let mut last = JSValue::Undefined
  for stmt in block.stmts {
    match self.exec_stmt_for_eval(stmt, env) {
      (Some(val), _) => return val // Control flow (return, break, throw)
      (None, completion) => last = completion
    }
  }
  last
}

///|
/// Execute a statement and return (control_flow, completion_value)
/// control_flow: Some(val) for return/break/throw, None for normal completion
/// completion_value: The completion value of the statement
fn JSInterpreter::exec_stmt_for_eval(
  self : JSInterpreter,
  stmt : @ast.TsStmt,
  env : JSEnv,
) -> (JSValue?, JSValue) {
  self.tick()
  match self.peek_error() {
    Some(err) => return (Some(err), Undefined)
    None => ()
  }
  match stmt {
    @ast.TsStmt::Expr(expr) => {
      let val = self.eval_expr(expr, env)
      match self.peek_error() {
        Some(err) => (Some(err), Undefined)
        None => (None, val)
      }
    }
    @ast.TsStmt::Var(_, _, _)
    | @ast.TsStmt::Let(_, _, _)
    | @ast.TsStmt::Const(_, _, _)
    | @ast.TsStmt::Assign(_, _)
    | @ast.TsStmt::CompoundAssign(_, _, _)
    | @ast.TsStmt::IndexAssign(_, _, _)
    | @ast.TsStmt::PropAssign(_, _, _)
    | @ast.TsStmt::Empty => {
      match self.exec_stmt(stmt, env) {
        Some(val) => (Some(val), Empty) // abrupt completions have empty value
        None => (None, Empty) // assignments have empty completion value
      }
    }
    @ast.TsStmt::If(cond, then_block, else_block) => {
      let cond_val = self.eval_expr(cond, env)
      match self.peek_error() {
        Some(err) => return (Some(err), Undefined)
        None => ()
      }
      if cond_val.to_boolean() {
        self.exec_block_for_eval(then_block, env)
      } else {
        match else_block {
          Some(block) => self.exec_block_for_eval(block, env)
          None => (None, Undefined) // if (false) {} -> undefined
        }
      }
    }
    @ast.TsStmt::While(cond, body) => self.exec_while_for_eval(cond, body, env)
    @ast.TsStmt::DoWhile(cond, body) =>
      self.exec_do_while_for_eval(cond, body, env)
    @ast.TsStmt::For(init, cond, update, body) =>
      self.exec_for_for_eval(init, cond, update, body, env)
    @ast.TsStmt::Block(block) => {
      let block_env = js_new_env(Some(env))
      self.hoist_block_lexical(block, block_env)
      self.exec_block_for_eval(block, block_env)
    }
    @ast.TsStmt::Label(name, inner) => {
      // Handle labeled statements with completion value tracking
      match inner {
        @ast.TsStmt::While(cond, body) =>
          self.exec_while_for_eval_labeled(cond, body, env, name)
        @ast.TsStmt::DoWhile(cond, body) =>
          self.exec_do_while_for_eval_labeled(cond, body, env, name)
        @ast.TsStmt::For(init, cond, update, body) =>
          self.exec_for_for_eval_labeled(init, cond, update, body, env, name)
        _ => {
          // For non-loop labeled statements
          match self.exec_stmt_for_eval(inner, env) {
            (Some(BreakSignal(Some(lbl))), completion) if lbl == name => {
              // Break to this label - convert to normal completion
              let final_val = if is_not_empty(completion) {
                completion
              } else {
                Undefined
              }
              (None, final_val)
            }
            other => other
          }
        }
      }
    }
    _ => {
      // For other statements, fall back to regular exec_stmt
      match self.exec_stmt(stmt, env) {
        Some(val) => (Some(val), Empty) // abrupt completions have empty value
        None => (None, Empty) // most statements have empty completion value
      }
    }
  }
}

///|
fn JSInterpreter::exec_block_for_eval(
  self : JSInterpreter,
  block : @ast.TsBlock,
  env : JSEnv,
) -> (JSValue?, JSValue) {
  let mut last = JSValue::Undefined // blockValue starts as undefined
  for stmt in block.stmts {
    match self.exec_stmt_for_eval(stmt, env) {
      (Some(val), completion) => {
        // UpdateEmpty: if completion value is not empty, use it; otherwise use last
        let final_completion = if is_not_empty(completion) {
          completion
        } else {
          last
        }
        return (Some(val), final_completion)
      }
      (None, completion) => {
        // Only update last if completion is not empty (UpdateEmpty semantics)
        if is_not_empty(completion) {
          last = completion
        }
      }
    }
  }
  (None, last)
}

///|
/// Check if a JSValue is not Empty (for UpdateEmpty semantics)
fn is_not_empty(v : JSValue) -> Bool {
  match v {
    Empty => false
    _ => true
  }
}

///|
fn JSInterpreter::exec_while_for_eval(
  self : JSInterpreter,
  cond : @ast.TsExpr,
  body : @ast.TsBlock,
  env : JSEnv,
) -> (JSValue?, JSValue) {
  let mut v = JSValue::Undefined
  while true {
    let cond_val = self.eval_expr(cond, env)
    match self.peek_error() {
      Some(err) => return (Some(err), Undefined)
      None => ()
    }
    if not(cond_val.to_boolean()) {
      return (None, v)
    }
    match self.exec_block_for_eval(body, env) {
      (Some(BreakSignal(None)), completion) => {
        // UpdateEmpty: use completion value if not undefined
        if is_not_empty(completion) {
          v = completion
        }
        return (None, v)
      }
      (Some(BreakSignal(Some(_))), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (Some(BreakSignal(None)), v)
      }
      (Some(ContinueSignal(None)), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        continue
      }
      (Some(ContinueSignal(Some(_))), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (Some(ContinueSignal(None)), v)
      }
      (Some(val), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (Some(val), v)
      }
      (None, completion) => {
        if is_not_empty(completion) {
          v = completion
        }
      }
    }
  }
  (None, v) // unreachable but needed for type
}

///|
fn JSInterpreter::exec_do_while_for_eval(
  self : JSInterpreter,
  cond : @ast.TsExpr,
  body : @ast.TsBlock,
  env : JSEnv,
) -> (JSValue?, JSValue) {
  let mut v = JSValue::Undefined
  while true {
    // Execute body first (do-while semantics)
    match self.exec_block_for_eval(body, env) {
      (Some(BreakSignal(None)), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (None, v)
      }
      (Some(BreakSignal(Some(_))), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (Some(BreakSignal(None)), v)
      }
      (Some(ContinueSignal(None)), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        // continue to condition check
      }
      (Some(ContinueSignal(Some(_))), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (Some(ContinueSignal(None)), v)
      }
      (Some(val), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (Some(val), v)
      }
      (None, completion) => {
        if is_not_empty(completion) {
          v = completion
        }
      }
    }
    // Check condition after body execution
    let cond_val = self.eval_expr(cond, env)
    match self.peek_error() {
      Some(err) => return (Some(err), Undefined)
      None => ()
    }
    if not(cond_val.to_boolean()) {
      return (None, v)
    }
  }
  (None, v) // unreachable but needed for type
}

///|
fn JSInterpreter::exec_for_for_eval(
  self : JSInterpreter,
  init : @ast.TsStmt?,
  cond : @ast.TsExpr?,
  update : @ast.TsStmt?,
  body : @ast.TsBlock,
  env : JSEnv,
) -> (JSValue?, JSValue) {
  // Create new environment for for loop
  let for_env = js_new_env(Some(env))

  // Execute init
  match init {
    Some(s) => {
      self.hoist_stmt(s, for_env)
      match self.exec_stmt(s, for_env) {
        Some(val) => return (Some(val), Undefined)
        None => ()
      }
    }
    None => ()
  }

  let mut v = JSValue::Undefined
  while true {
    // Check condition
    match cond {
      Some(c) => {
        let cond_val = self.eval_expr(c, for_env)
        match self.peek_error() {
          Some(err) => return (Some(err), Undefined)
          None => ()
        }
        if not(cond_val.to_boolean()) {
          return (None, v)
        }
      }
      None => ()
    }

    // Execute body
    match self.exec_block_for_eval(body, for_env) {
      (Some(BreakSignal(None)), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (None, v)
      }
      (Some(BreakSignal(Some(_))), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (Some(BreakSignal(None)), v)
      }
      (Some(ContinueSignal(None)), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
      }
      (Some(ContinueSignal(Some(_))), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (Some(ContinueSignal(None)), v)
      }
      (Some(val), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (Some(val), v)
      }
      (None, completion) => {
        if is_not_empty(completion) {
          v = completion
        }
      }
    }

    // Execute update
    match update {
      Some(u) => {
        match self.exec_stmt(u, for_env) {
          Some(val) => return (Some(val), Undefined)
          None => ()
        }
      }
      None => ()
    }
  }
  (None, v) // unreachable but needed for type
}

///|
/// Labeled version of exec_while_for_eval
fn JSInterpreter::exec_while_for_eval_labeled(
  self : JSInterpreter,
  cond : @ast.TsExpr,
  body : @ast.TsBlock,
  env : JSEnv,
  label : String,
) -> (JSValue?, JSValue) {
  let mut v = JSValue::Undefined
  while true {
    let cond_val = self.eval_expr(cond, env)
    match self.peek_error() {
      Some(err) => return (Some(err), Undefined)
      None => ()
    }
    if not(cond_val.to_boolean()) {
      return (None, v)
    }
    match self.exec_block_for_eval(body, env) {
      (Some(BreakSignal(None)), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (None, v)
      }
      (Some(BreakSignal(Some(lbl))), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        if lbl == label {
          return (None, v)
        } else {
          return (Some(BreakSignal(Some(lbl))), v)
        }
      }
      (Some(ContinueSignal(None)), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        continue
      }
      (Some(ContinueSignal(Some(lbl))), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        if lbl == label {
          continue
        } else {
          return (Some(ContinueSignal(Some(lbl))), v)
        }
      }
      (Some(val), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (Some(val), v)
      }
      (None, completion) => {
        if is_not_empty(completion) {
          v = completion
        }
      }
    }
  }
  (None, v) // unreachable but needed for type
}

///|
/// Labeled version of exec_do_while_for_eval
fn JSInterpreter::exec_do_while_for_eval_labeled(
  self : JSInterpreter,
  cond : @ast.TsExpr,
  body : @ast.TsBlock,
  env : JSEnv,
  label : String,
) -> (JSValue?, JSValue) {
  let mut v = JSValue::Undefined
  while true {
    // Execute body first (do-while semantics)
    match self.exec_block_for_eval(body, env) {
      (Some(BreakSignal(None)), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (None, v)
      }
      (Some(BreakSignal(Some(lbl))), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        if lbl == label {
          return (None, v)
        } else {
          return (Some(BreakSignal(Some(lbl))), v)
        }
      }
      (Some(ContinueSignal(None)), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        // continue to condition check
      }
      (Some(ContinueSignal(Some(lbl))), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        if lbl == label {
          // continue to condition check
        } else {
          return (Some(ContinueSignal(Some(lbl))), v)
        }
      }
      (Some(val), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (Some(val), v)
      }
      (None, completion) => {
        if is_not_empty(completion) {
          v = completion
        }
      }
    }
    // Check condition after body execution
    let cond_val = self.eval_expr(cond, env)
    match self.peek_error() {
      Some(err) => return (Some(err), Undefined)
      None => ()
    }
    if not(cond_val.to_boolean()) {
      return (None, v)
    }
  }
  (None, v) // unreachable but needed for type
}

///|
/// Labeled version of exec_for_for_eval
fn JSInterpreter::exec_for_for_eval_labeled(
  self : JSInterpreter,
  init : @ast.TsStmt?,
  cond : @ast.TsExpr?,
  update : @ast.TsStmt?,
  body : @ast.TsBlock,
  env : JSEnv,
  label : String,
) -> (JSValue?, JSValue) {
  // Create new environment for for loop
  let for_env = js_new_env(Some(env))

  // Execute init
  match init {
    Some(s) => {
      self.hoist_stmt(s, for_env)
      match self.exec_stmt(s, for_env) {
        Some(val) => return (Some(val), Undefined)
        None => ()
      }
    }
    None => ()
  }

  let mut v = JSValue::Undefined
  while true {
    // Check condition
    match cond {
      Some(c) => {
        let cond_val = self.eval_expr(c, for_env)
        match self.peek_error() {
          Some(err) => return (Some(err), Undefined)
          None => ()
        }
        if not(cond_val.to_boolean()) {
          return (None, v)
        }
      }
      None => ()
    }

    // Execute body
    match self.exec_block_for_eval(body, for_env) {
      (Some(BreakSignal(None)), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (None, v)
      }
      (Some(BreakSignal(Some(lbl))), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        if lbl == label {
          return (None, v)
        } else {
          return (Some(BreakSignal(Some(lbl))), v)
        }
      }
      (Some(ContinueSignal(None)), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
      }
      (Some(ContinueSignal(Some(lbl))), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        if lbl == label {
          // Continue in this loop - fall through to update
        } else {
          return (Some(ContinueSignal(Some(lbl))), v)
        }
      }
      (Some(val), completion) => {
        if is_not_empty(completion) {
          v = completion
        }
        return (Some(val), v)
      }
      (None, completion) => {
        if is_not_empty(completion) {
          v = completion
        }
      }
    }

    // Execute update
    match update {
      Some(u) => {
        match self.exec_stmt(u, for_env) {
          Some(val) => return (Some(val), Undefined)
          None => ()
        }
      }
      None => ()
    }
  }
  (None, v) // unreachable but needed for type
}

///|
fn apply_compound_op(
  op : @ast.TsCompoundOp,
  current : JSValue,
  val : JSValue,
) -> JSValue {
  match op {
    @ast.TsCompoundOp::AddAssign => js_add(current, val)
    @ast.TsCompoundOp::SubAssign => js_sub(current, val)
    @ast.TsCompoundOp::MulAssign => js_mul(current, val)
    @ast.TsCompoundOp::DivAssign => js_div(current, val)
    @ast.TsCompoundOp::ModAssign => js_mod(current, val)
    @ast.TsCompoundOp::BitAndAssign => {
      let li = current.to_number().to_int()
      let ri = val.to_number().to_int()
      Number((li & ri).to_double())
    }
    @ast.TsCompoundOp::BitOrAssign => {
      let li = current.to_number().to_int()
      let ri = val.to_number().to_int()
      Number((li | ri).to_double())
    }
    @ast.TsCompoundOp::BitXorAssign => {
      let li = current.to_number().to_int()
      let ri = val.to_number().to_int()
      Number((li ^ ri).to_double())
    }
    @ast.TsCompoundOp::ShlAssign => {
      let li = current.to_number().to_int()
      let ri = val.to_number().to_int()
      let shift = ri & 31
      Number((li << shift).to_double())
    }
    @ast.TsCompoundOp::ShrAssign => {
      let li = current.to_number().to_int()
      let ri = val.to_number().to_int()
      let shift = ri & 31
      Number((li >> shift).to_double())
    }
    @ast.TsCompoundOp::UShrAssign => {
      let li = current.to_number()
      let ri = val.to_number().to_int()
      let shift = ri & 31
      let u = if li < 0.0 { li + 4294967296.0 } else { li }
      let denom = @math.pow(2.0, shift.to_double())
      Number(@math.floor(u / denom))
    }
    @ast.TsCompoundOp::PowAssign => Number(@math.pow(current.to_number(), val.to_number()))
  }
}

///|
fn JSInterpreter::apply_for_of_binding(
  self : JSInterpreter,
  kind : @ast.TsForOfKind,
  binding : @ast.TsBinding,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match kind {
    @ast.TsForOfKind::Assign => self.assign_pattern(binding, value, env)
    @ast.TsForOfKind::Var =>
      match binding {
        @ast.TsBinding::Ident(name) => {
          if not(env.set(name, value)) {
            env.define_var(name, value)
          }
        }
        _ => self.bind_pattern(binding, value, env)
      }
    @ast.TsForOfKind::Let => self.init_pattern(binding, value, env, false)
    @ast.TsForOfKind::Const => self.init_pattern(binding, value, env, true)
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
  cond : @ast.TsExpr,
  body : @ast.TsBlock,
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
fn JSInterpreter::exec_do_while_loop(
  self : JSInterpreter,
  cond : @ast.TsExpr,
  body : @ast.TsBlock,
  env : JSEnv,
  loop_label : String?,
) -> JSValue? {
  while true {
    // Execute body first (do-while semantics)
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
          // continue to condition check
        } else {
          return Some(ContinueSignal(label))
        }
      Some(val) => return Some(val)
      None => ()
    }
    // Check condition after body execution
    let cond_val = self.eval_expr(cond, env)
    match self.peek_error() {
      Some(err) => return Some(err)
      None => ()
    }
    if not(cond_val.to_boolean()) {
      break
    }
  }
  None
}

///|
fn JSInterpreter::exec_for_loop(
  self : JSInterpreter,
  init : @ast.TsStmt?,
  cond : @ast.TsExpr?,
  update : @ast.TsStmt?,
  body : @ast.TsBlock,
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
  kind : @ast.TsForOfKind,
  binding : @ast.TsBinding,
  iterable : @ast.TsExpr,
  body : @ast.TsBlock,
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
  kind : @ast.TsForOfKind,
  binding : @ast.TsBinding,
  iterable : @ast.TsExpr,
  body : @ast.TsBlock,
  env : JSEnv,
  loop_label : String?,
) -> JSValue? {
  let iter_val = self.eval_expr(iterable, env)
  match self.peek_error() {
    Some(err) => return Some(err)
    None => ()
  }
  let target = match iter_val {
    Undefined | Null => return None
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
  stmt : @ast.TsStmt,
  env : JSEnv,
) -> JSValue? {
  self.tick()
  match self.peek_error() {
    Some(err) => return Some(err)
    None => ()
  }
  match stmt {
    @ast.TsStmt::Var(binding, _, init)
    | @ast.TsStmt::Let(binding, _, init)
    | @ast.TsStmt::Const(binding, _, init) => {
      let val = self.eval_expr(init, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      self.maybe_set_default_name_for_binding(binding, val, Some(init))
      let is_const = match stmt {
        @ast.TsStmt::Const(_, _, _) => true
        _ => false
      }
      self.init_pattern(binding, val, env, is_const)
      match env.parent {
        None => {
          let global_obj = self.global_env.get("globalThis")
          let names : Array[String] = []
          collect_binding_names(binding, names)
          for name in names {
            let v = env.get(name)
            let _ = js_set_prop(global_obj, name, v)
          }
        }
        Some(_) => ()
      }
      None
    }
    @ast.TsStmt::Expr(expr) => {
      let _ = self.eval_expr(expr, env)
      match self.peek_error() {
        Some(err) => Some(err)
        None => None
      }
    }
    Empty => None
    @ast.TsStmt::Block(block) => {
      // Create a new lexical environment for block scope
      let block_env = js_new_env(Some(env))
      self.hoist_block_lexical(block, block_env)
      self.exec_block(block, block_env)
    }
    @ast.TsStmt::Label(name, inner) => {
      match inner {
        @ast.TsStmt::While(cond, body) =>
          self.exec_while_loop(cond, body, env, Some(name))
        @ast.TsStmt::DoWhile(cond, body) =>
          self.exec_do_while_loop(cond, body, env, Some(name))
        @ast.TsStmt::For(init, cond, update, body) =>
          self.exec_for_loop(init, cond, update, body, env, Some(name))
        @ast.TsStmt::ForOf(kind, binding, _, iterable, body) =>
          self.exec_for_of_loop(kind, binding, iterable, body, env, Some(name))
        @ast.TsStmt::ForIn(kind, binding, _, iterable, body) =>
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
    @ast.TsStmt::Assign(name, val_expr) => {
      let val = self.eval_expr(val_expr, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      self.maybe_set_default_name(val, name, Some(val_expr))
      self.assign_ident(name, val, env)
      None
    }
    @ast.TsStmt::Return(Some(expr)) => {
      let val = self.eval_expr(expr, env)
      match self.peek_error() {
        Some(err) => Some(err)
        None => Some(val)
      }
    }
    @ast.TsStmt::Return(None) => Some(Undefined)
    @ast.TsStmt::Throw(expr) => {
      let val = self.eval_expr(expr, env)
      self.last_error = Some(val)
      Some(val)
    }
    @ast.TsStmt::Try(try_block, catch_binding, catch_block, finally_block) => {
      let mut result = self.exec_block(try_block, env)
      let mut pending_error : JSValue? = None
      match self.peek_error() {
        Some(_) =>
          match self.take_error() {
            Some(err) => {
              match catch_block {
                Some(block) => {
                  let catch_env = js_new_env(Some(env))
                  match catch_binding {
                    Some(binding) => self.init_pattern(binding, err, catch_env, false)
                    None => ()
                  }
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
    @ast.TsStmt::If(cond, then_block, else_block) => {
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
    @ast.TsStmt::While(cond, body) => self.exec_while_loop(cond, body, env, None)
    @ast.TsStmt::DoWhile(cond, body) =>
      self.exec_do_while_loop(cond, body, env, None)
    @ast.TsStmt::Switch(expr, cases) => {
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
    @ast.TsStmt::For(init, cond, update, body) =>
      self.exec_for_loop(init, cond, update, body, env, None)
    Break(label) => Some(BreakSignal(label))
    Continue(label) => Some(ContinueSignal(label))
    @ast.TsStmt::CompoundAssign(name, op, val_expr) => {
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
    @ast.TsStmt::IndexAssign(arr_expr, idx_expr, val_expr) => {
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
    @ast.TsStmt::PropAssign(obj_expr, prop, val_expr) => {
      let obj = self.eval_expr(obj_expr, env)
      let val = self.eval_expr(val_expr, env)
      match self.peek_error() {
        Some(err) => return Some(err)
        None => ()
      }
      if prop.has_prefix("@@define:") {
        let real_key = (try { prop[9:] } catch { _ => "" }).to_string()
        let _ = js_define_data_prop(obj, real_key, val, true, false, true)
      } else if prop.has_prefix("@@get:") || prop.has_prefix("@@set:") {
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
    @ast.TsStmt::ForOf(kind, binding, _, iterable, body) =>
      self.exec_for_of_loop(kind, binding, iterable, body, env, None)
    @ast.TsStmt::ForIn(kind, binding, _, iterable, body) =>
      self.exec_for_in_loop(kind, binding, iterable, body, env, None)
    @ast.TsStmt::With(obj_expr, body) => {
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
    @ast.TsStmt::Debugger => None
  }
}

///|
// / blockrun
pub fn JSInterpreter::exec_block(
  self : JSInterpreter,
  block : @ast.TsBlock,
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
fn JSInterpreter::hoist_stmt(self : JSInterpreter, stmt : @ast.TsStmt, env : JSEnv) -> Unit {
  match stmt {
    @ast.TsStmt::Var(binding, _, _) => {
      // var declarations are hoisted with initial value undefined (no TDZ)
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
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
      }
    }
    @ast.TsStmt::Let(binding, _, _) | @ast.TsStmt::Const(binding, _, _) => {
      // let/const declarations are hoisted with TDZ (uninitialized)
      let names : Array[String] = []
      collect_binding_names(binding, names)
      let is_const = match stmt {
        @ast.TsStmt::Const(_, _, _) => true
        _ => false
      }
      for name in names {
        if not(env.has(name)) {
          env.define_uninitialized(name, is_const)
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
    @ast.TsStmt::Block(block) => self.hoist_block(block, env)
    @ast.TsStmt::Label(_, inner) => self.hoist_stmt(inner, env)
    @ast.TsStmt::If(_, then_block, else_block) => {
      self.hoist_block(then_block, env)
      match else_block {
        Some(block) => self.hoist_block(block, env)
        None => ()
      }
    }
    @ast.TsStmt::While(_, body) => self.hoist_block(body, env)
    @ast.TsStmt::For(init, _, _, body) => {
      match init {
        Some(s) => self.hoist_stmt(s, env)
        None => ()
      }
      self.hoist_block(body, env)
    }
    @ast.TsStmt::Switch(_, cases) =>
      for case_ in cases {
        self.hoist_block(case_.body, env)
      }
    @ast.TsStmt::ForIn(kind, binding, _, _, body) => {
      if kind != @ast.TsForOfKind::Assign {
        let names : Array[String] = []
        collect_binding_names(binding, names)
        let is_const = kind == @ast.TsForOfKind::Const
        for name in names {
          if not(env.has(name)) {
            match kind {
              @ast.TsForOfKind::Var => env.define_var(name, Undefined)
              @ast.TsForOfKind::Let | @ast.TsForOfKind::Const =>
                env.define_uninitialized(name, is_const)
              @ast.TsForOfKind::Assign => ()
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
    @ast.TsStmt::With(_, body) => self.hoist_block(body, env)
    @ast.TsStmt::ForOf(kind, binding, _, _, body) => {
      if kind != @ast.TsForOfKind::Assign {
        let names : Array[String] = []
        collect_binding_names(binding, names)
        let is_const = kind == @ast.TsForOfKind::Const
        for name in names {
          if not(env.has(name)) {
            match kind {
              @ast.TsForOfKind::Var => env.define_var(name, Undefined)
              @ast.TsForOfKind::Let | @ast.TsForOfKind::Const =>
                env.define_uninitialized(name, is_const)
              @ast.TsForOfKind::Assign => ()
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
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
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
pub fn JSInterpreter::hoist_block(self : JSInterpreter, block : @ast.TsBlock, env : JSEnv) -> Unit {
  for stmt in block.stmts {
    self.hoist_stmt(stmt, env)
  }
}

///|
/// Hoist only lexical (let/const) declarations to block scope.
/// Always hoist to local scope (using has_local check) to ensure
/// block-scoped let/const shadow outer variables properly.
fn JSInterpreter::hoist_block_lexical(
  _self : JSInterpreter,
  block : @ast.TsBlock,
  env : JSEnv,
) -> Unit {
  for stmt in block.stmts {
    match stmt {
      @ast.TsStmt::Let(binding, _, _) => {
        let names : Array[String] = []
        collect_binding_names(binding, names)
        for name in names {
          // Always create local binding for let (shadowing is intended)
          if not(env.has_local(name)) {
            env.define_uninitialized(name, false)
          }
        }
      }
      @ast.TsStmt::Const(binding, _, _) => {
        let names : Array[String] = []
        collect_binding_names(binding, names)
        for name in names {
          // Always create local binding for const (shadowing is intended)
          if not(env.has_local(name)) {
            env.define_uninitialized(name, true)
          }
        }
      }
      _ => ()
    }
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
fn JSInterpreter::exec_stmt_gen(
  self : JSInterpreter,
  stmt : @ast.TsStmt,
  env : JSEnv,
) -> GenSignal {
  self.tick()
  match self.peek_error() {
    Some(err) => return GenSignal::Return(err)
    None => ()
  }
  match stmt {
    @ast.TsStmt::Expr(expr) =>
      gen_to_signal(self.eval_expr_gen(expr, env), (_val) =>
        match self.peek_error() {
          Some(err) => GenSignal::Return(err)
          None => GenSignal::Continue
        }
      )
    @ast.TsStmt::Assign(name, value) =>
      gen_to_signal(self.eval_expr_gen(value, env), (val) => {
        self.assign_ident(name, val, env)
        match self.peek_error() {
          Some(err) => GenSignal::Return(err)
          None => GenSignal::Continue
        }
      })
    @ast.TsStmt::PropAssign(obj_expr, prop, value_expr) =>
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
    @ast.TsStmt::IndexAssign(obj_expr, idx_expr, value_expr) =>
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
    @ast.TsStmt::Return(opt) =>
      match opt {
        Some(e) =>
          gen_to_signal(self.eval_expr_gen(e, env), (val) =>
            GenSignal::Return(val)
          )
        None => GenSignal::Return(JSValue::Undefined)
      }
    @ast.TsStmt::If(cond, then_block, else_block) =>
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
    @ast.TsStmt::Block(block) => self.exec_block_gen(block, env)
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
  block : @ast.TsBlock,
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
        Native(name) => {
          let prev_array_proto = js_get_default_array_proto()
          let mut switched = false
          let realm_array_proto =
            match closure.env.get("Array") {
              Function(_) | Object(_) | Array(_) =>
                js_get_prop(closure.env.get("Array"), "prototype")
              _ => Undefined
            }
          match realm_array_proto {
            Object(_) | Function(_) | Array(_) => {
              js_set_default_array_proto(realm_array_proto)
              switched = true
            }
            _ => ()
          }
          let result =
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
          if switched {
            match prev_array_proto {
              Some(proto) => js_set_default_array_proto(proto)
              None => ()
            }
          }
          result
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
