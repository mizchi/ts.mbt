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
