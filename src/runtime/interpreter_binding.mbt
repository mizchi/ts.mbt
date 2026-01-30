// Binding and pattern assignment helpers.

///|
fn JSInterpreter::eval_object_binding_key(
  self : JSInterpreter,
  prop : @ast.TsObjectBindingProp,
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
  binding : @ast.TsBinding,
  value : JSValue,
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(name) => self.maybe_set_function_name(value, name)
    @ast.TsBinding::Target(_) => ()
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
            let has_name_prop = match
              js_get_prop(value, "__class_has_name_prop") {
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
  expr : @ast.TsExpr,
) -> Bool {
  match expr {
    @ast.TsExpr::FuncExpr(func) => func.name == "<anon>"
    @ast.TsExpr::ArrowFunc(_, _, _) => true
    @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(func), _) =>
      func.name == "<class>"
    @ast.TsExpr::ObjectLit(fields) => {
      for field in fields {
        let (key, value) = field
        if key == "__class_name" {
          match value {
            @ast.TsExpr::StringLit(s) => return s.length() == 0
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
  binding : @ast.TsBinding,
  value : JSValue,
  default_expr : @ast.TsExpr?,
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
  default_expr : @ast.TsExpr?,
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
  binding : @ast.TsBinding,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(name) => env.define_var(name, value)
    @ast.TsBinding::Array(arr) => self.bind_array_pattern(arr, value, env)
    @ast.TsBinding::Object(obj) => self.bind_object_pattern(obj, value, env)
    @ast.TsBinding::Target(_) => {
      let _ = self.set_error_kind("TypeError", "Invalid binding target")

    }
  }
}

///|
fn JSInterpreter::init_pattern(
  self : JSInterpreter,
  binding : @ast.TsBinding,
  value : JSValue,
  env : JSEnv,
  is_const : Bool,
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(name) => env.initialize(name, value, is_const)
    @ast.TsBinding::Array(arr) =>
      self.init_array_pattern(arr, value, env, is_const)
    @ast.TsBinding::Object(obj) =>
      self.init_object_pattern(obj, value, env, is_const)
    @ast.TsBinding::Target(_) => {
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
  binding : @ast.TsBinding,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(name) => self.assign_ident(name, value, env)
    @ast.TsBinding::Array(arr) => self.assign_array_pattern(arr, value, env)
    @ast.TsBinding::Object(obj) => self.assign_object_pattern(obj, value, env)
    @ast.TsBinding::Target(target) =>
      self.assign_target_expr(target, value, env)
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
  target : @ast.TsExpr,
  env : JSEnv,
) -> AssignTarget? {
  match target {
    @ast.TsExpr::Var(name) => Some(AssignTarget::Ident(name))
    @ast.TsExpr::PropAccess(obj_expr, prop) => {
      let obj = self.eval_expr(obj_expr, env)
      match self.peek_error() {
        Some(_) => None
        None =>
          match obj {
            Undefined | Null => {
              let _ = self.set_error_kind(
                "TypeError", "Cannot read properties of null or undefined",
              )
              None
            }
            _ => Some(AssignTarget::Prop(obj, prop))
          }
      }
    }
    @ast.TsExpr::IndexAccess(obj_expr, idx_expr) => {
      let obj = self.eval_expr(obj_expr, env)
      match self.peek_error() {
        Some(_) => None
        None =>
          match obj {
            Undefined | Null => {
              let _ = self.set_error_kind(
                "TypeError", "Cannot read properties of null or undefined",
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
  let is_strict = env.has("__strict__")
  match target {
    AssignTarget::Ident(name) => self.assign_ident(name, value, env)
    AssignTarget::Prop(obj, prop) =>
      self.set_prop_value(obj, prop, value, strict=is_strict)
    AssignTarget::Index(obj, key) =>
      match obj {
        Array(_) | Object(_) | Function(_) =>
          self.set_prop_value(obj, key, value, strict=is_strict)
        _ => ()
      }
  }
}

///|
fn JSInterpreter::assign_target_expr(
  self : JSInterpreter,
  target : @ast.TsExpr,
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
  binding : @ast.TsBinding,
  value : JSValue,
  env : JSEnv,
) -> GenValue {
  match binding {
    @ast.TsBinding::Ident(name) => {
      self.assign_ident(name, value, env)
      GenValue::Value(value)
    }
    @ast.TsBinding::Array(arr) => self.assign_array_pattern_gen(arr, value, env)
    @ast.TsBinding::Object(obj) =>
      self.assign_object_pattern_gen(obj, value, env)
    @ast.TsBinding::Target(target) =>
      self.assign_target_expr_gen(target, value, env)
  }
}

///|
fn JSInterpreter::assign_target_expr_gen(
  self : JSInterpreter,
  target : @ast.TsExpr,
  value : JSValue,
  env : JSEnv,
) -> GenValue {
  self.eval_assignment_target_gen(target, env, prepared => {
    self.assign_prepared_target(prepared, value, env)
    GenValue::Value(value)
  })
}

///|
fn JSInterpreter::eval_assignment_target_gen(
  self : JSInterpreter,
  target : @ast.TsExpr,
  env : JSEnv,
  cont : (AssignTarget) -> GenValue,
) -> GenValue {
  match target {
    @ast.TsExpr::Var(name) => cont(AssignTarget::Ident(name))
    @ast.TsExpr::PropAccess(obj_expr, prop) =>
      gen_bind(self.eval_expr_gen(obj_expr, env), obj => {
        if self.peek_error() is Some(_) {
          return GenValue::Value(Undefined)
        }
        match obj {
          Undefined | Null => {
            let _ = self.set_error_kind(
              "TypeError", "Cannot read properties of null or undefined",
            )
            GenValue::Value(Undefined)
          }
          _ => cont(AssignTarget::Prop(obj, prop))
        }
      })
    @ast.TsExpr::IndexAccess(obj_expr, idx_expr) =>
      gen_bind(self.eval_expr_gen(obj_expr, env), obj => {
        if self.peek_error() is Some(_) {
          return GenValue::Value(Undefined)
        }
        match obj {
          Undefined | Null => {
            let _ = self.set_error_kind(
              "TypeError", "Cannot read properties of null or undefined",
            )
            GenValue::Value(Undefined)
          }
          _ =>
            gen_bind(self.eval_expr_gen(idx_expr, env), idx => {
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
  pattern : @ast.TsArrayBinding,
  value : JSValue,
  env : JSEnv,
) -> GenValue {
  match value {
    Undefined | Null => {
      let _ = self.set_error_kind(
        "TypeError", "Cannot destructure undefined or null",
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
                @ast.TsBinding::Target(target_expr) =>
                  self.eval_assignment_target_gen(target_expr, env, prepared => if self.peek_error()
                    is Some(_) {
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
                    gen_bind(
                      self.assign_pattern_gen(rest_binding, rest_val, env),
                      _unused => if self.peek_error() is Some(_) {
                        if not(done) {
                          self.iterator_close_on_error(iterator)
                        }
                        self.pop_active_iterator()
                        GenValue::Value(Undefined)
                      } else {
                        self.pop_active_iterator()
                        GenValue::Value(Undefined)
                      },
                    )
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
              let with_default = match elem.default {
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
                gen_bind(self.assign_pattern_gen(elem.binding, v, env), _unused => if self.peek_error()
                  is Some(_) {
                  if not(done) {
                    self.iterator_close_on_error(iterator)
                  }
                  self.pop_active_iterator()
                  GenValue::Value(Undefined)
                } else {
                  process_index(index + 1)
                })
              }
              match with_default {
                Some(default_signal) =>
                  gen_bind(default_signal, default_val => assign_elem(
                    default_val,
                  ))
                None => assign_elem(val)
              }
            }
          }
        }
      }

      process_index(0)
    }
    None => {
      // Check if get_iterator already set an error
      match self.peek_error() {
        Some(_) => return GenValue::Value(Undefined)
        None => ()
      }
      // If no error but get_iterator returned None, value is not iterable
      let _ = self.set_error_kind("TypeError", "is not iterable")
      GenValue::Value(Undefined)
    }
  }
}

///|
fn JSInterpreter::assign_object_pattern_gen(
  self : JSInterpreter,
  pattern : @ast.TsObjectBinding,
  value : JSValue,
  env : JSEnv,
) -> GenValue {
  match value {
    Undefined | Null => {
      let _ = self.set_error_kind(
        "TypeError", "Cannot destructure undefined or null",
      )
      return GenValue::Value(Undefined)
    }
    _ => ()
  }
  let used_keys : Array[String] = []
  fn process_prop(
    self : JSInterpreter,
    pattern : @ast.TsObjectBinding,
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
            Object(map) =>
              for prop in map.props {
                if not(prop.enumerable) {
                  continue
                }
                if not(contains_key(used_keys, prop.key)) {
                  let val = self.eval_prop_value(JSValue::Object(map), prop)
                  let _ = js_set_prop(rest_obj, prop.key, val)

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
            Function(closure) =>
              for prop in closure.props {
                if not(contains_key(used_keys, prop.key)) {
                  if not(prop.enumerable) {
                    continue
                  }
                  let val = self.eval_prop_value(
                    JSValue::Function(closure),
                    prop,
                  )
                  let _ = js_set_prop(rest_obj, prop.key, val)

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
      let key_signal = match prop.key_expr {
        Some(expr) => self.eval_expr_gen(expr, env)
        None => GenValue::Value(JSValue::String(prop.key))
      }
      gen_bind(key_signal, key_val => {
        let key = key_val.to_js_string()
        used_keys.push(key)
        let val = self.get_prop_value(value, key)
        let mut used_default = false
        let default_expr = prop.default
        let with_default = match prop.default {
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
          gen_bind(self.assign_pattern_gen(prop.binding, v, env), _unused => process_prop(
            self,
            pattern,
            env,
            value,
            used_keys,
            index + 1,
          ))
        }
        match with_default {
          Some(default_signal) =>
            gen_bind(default_signal, default_val => assign_prop(default_val))
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
  pattern : @ast.TsArrayBinding,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match value {
    Undefined | Null => {
      let _ = self.set_error_kind(
        "TypeError", "Cannot destructure undefined or null",
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
          None =>
            if not(done) {
              let _ = next_value()

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
                let mut val = if done {
                  JSValue::Undefined
                } else {
                  next_value()
                }
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
          // Check if get_iterator already set an error
          match self.peek_error() {
            Some(_) => return
            None => ()
          }
          // If no error but get_iterator returned None, value is not iterable
          let _ = self.set_error_kind("TypeError", "is not iterable")

        }
      }
  }
}

///|
fn JSInterpreter::init_array_pattern(
  self : JSInterpreter,
  pattern : @ast.TsArrayBinding,
  value : JSValue,
  env : JSEnv,
  is_const : Bool,
) -> Unit {
  match value {
    Undefined | Null => {
      let _ = self.set_error_kind(
        "TypeError", "Cannot destructure undefined or null",
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
          None =>
            if not(done) {
              let _ = next_value()

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
                let mut val = if done {
                  JSValue::Undefined
                } else {
                  next_value()
                }
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
          // Check if get_iterator already set an error (e.g., from calling the iterator method)
          match self.peek_error() {
            Some(_) => return
            None => ()
          }
          // If no error but get_iterator returned None, value is not iterable
          let _ = self.set_error_kind("TypeError", "is not iterable")

        }
      }
  }
}

///|
fn JSInterpreter::assign_array_pattern(
  self : JSInterpreter,
  pattern : @ast.TsArrayBinding,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match value {
    Undefined | Null => {
      let _ = self.set_error_kind(
        "TypeError", "Cannot destructure undefined or null",
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
          None =>
            if not(done) {
              let _ = next_value()

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
                let mut val = if done {
                  JSValue::Undefined
                } else {
                  next_value()
                }
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
                @ast.TsBinding::Target(target_expr) => {
                  let prepared = self.prepare_assignment_target(
                    target_expr, env,
                  )
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
          // Check if get_iterator already set an error
          match self.peek_error() {
            Some(_) => return
            None => ()
          }
          // If no error but get_iterator returned None, value is not iterable
          let _ = self.set_error_kind("TypeError", "is not iterable")

        }
      }
  }
}

///|
fn JSInterpreter::bind_object_pattern(
  self : JSInterpreter,
  pattern : @ast.TsObjectBinding,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match value {
    Undefined | Null => {
      let _ = self.set_error_kind(
        "TypeError", "Cannot destructure undefined or null",
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
      self.maybe_set_default_name_for_binding(prop.binding, val, default_expr)
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
        Object(map) =>
          for prop in map.props {
            if not(prop.enumerable) {
              continue
            }
            if not(contains_key(used_keys, prop.key)) {
              let val = self.eval_prop_value(JSValue::Object(map), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)

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
        Function(closure) =>
          for prop in closure.props {
            if not(contains_key(used_keys, prop.key)) {
              if not(prop.enumerable) {
                continue
              }
              let val = self.eval_prop_value(JSValue::Function(closure), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)

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
  pattern : @ast.TsObjectBinding,
  value : JSValue,
  env : JSEnv,
  is_const : Bool,
) -> Unit {
  match value {
    Undefined | Null => {
      let _ = self.set_error_kind(
        "TypeError", "Cannot destructure undefined or null",
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
      self.maybe_set_default_name_for_binding(prop.binding, val, default_expr)
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
        Object(map) =>
          for prop in map.props {
            if not(prop.enumerable) {
              continue
            }
            if not(contains_key(used_keys, prop.key)) {
              let val = self.eval_prop_value(JSValue::Object(map), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)

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
        Function(closure) =>
          for prop in closure.props {
            if not(contains_key(used_keys, prop.key)) {
              if not(prop.enumerable) {
                continue
              }
              let val = self.eval_prop_value(JSValue::Function(closure), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)

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
  pattern : @ast.TsObjectBinding,
  value : JSValue,
  env : JSEnv,
) -> Unit {
  match value {
    Undefined | Null => {
      let _ = self.set_error_kind(
        "TypeError", "Cannot destructure undefined or null",
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
      self.maybe_set_default_name_for_binding(prop.binding, val, default_expr)
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
        Object(map) =>
          for prop in map.props {
            if not(prop.enumerable) {
              continue
            }
            if not(contains_key(used_keys, prop.key)) {
              let val = self.eval_prop_value(JSValue::Object(map), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)

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
        Function(closure) =>
          for prop in closure.props {
            if not(contains_key(used_keys, prop.key)) {
              if not(prop.enumerable) {
                continue
              }
              let val = self.eval_prop_value(JSValue::Function(closure), prop)
              let _ = js_set_prop(rest_obj, prop.key, val)

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
  params : Array[@ast.TsParam],
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
      let v = if arg_index < args.length() {
        args[arg_index]
      } else {
        Undefined
      }
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
