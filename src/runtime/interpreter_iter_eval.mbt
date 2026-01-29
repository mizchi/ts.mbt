// Iterator and generator helpers used by the evaluator.

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
fn collect_binding_names(binding : @ast.TsBinding, names : Array[String]) -> Unit {
  match binding {
    @ast.TsBinding::Ident(name) => names.push(name)
    @ast.TsBinding::Array(arr) => {
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
    @ast.TsBinding::Object(obj) => {
      for prop in obj.props {
        collect_binding_names(prop.binding, names)
      }
      match obj.rest {
        Some(rest_name) => names.push(rest_name)
        None => ()
      }
    }
    @ast.TsBinding::Target(_) => ()
  }
}

///|
fn collect_param_names(params : Array[@ast.TsParam]) -> Array[String] {
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
fn has_param_expressions(params : Array[@ast.TsParam]) -> Bool {
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
  match value {
    String(s) if s.has_prefix("Symbol(") => {
      let _ = self.set_error_kind("TypeError", "Symbol is not iterable")
      return None
    }
    _ => ()
  }
  let target = match value {
    Bool(_) | Number(_) | String(_) => self.wrap_primitive(self.global_env, value)
    _ => value
  }
  let iter_method = self.get_prop_value(target, "@@iterator")
  match self.peek_error() {
    Some(_) => return None
    None => ()
  }
  match iter_method {
    Undefined | Null => None
    _ => {
      let iterator = self.call_function(iter_method, target, [])
      match self.peek_error() {
        Some(_) => None
        None => {
          match iterator {
            Object(_) | Function(_) | Array(_) => ()
            _ => {
              let _ = self.set_error_kind("TypeError", "Iterator result is not an object")
              return None
            }
          }
          let next_method = self.get_prop_value(iterator, "next")
          match self.peek_error() {
            Some(_) => None
            None =>
              if not(self.is_callable(next_method)) {
                let _ = self.set_error_kind("TypeError", "Iterator next is not callable")
                None
              } else {
                Some(iterator)
              }
          }
        }
      }
    }
  }
}

///|
fn JSInterpreter::collect_spread_values(
  self : JSInterpreter,
  value : JSValue,
) -> Array[JSValue]? {
  let iterator =
    match self.get_iterator(value) {
      Some(iter) => iter
      None => {
        let _ = self.set_error_kind("TypeError", "Spread value is not iterable")
        return None
      }
    }
  let values : Array[JSValue] = []
  while true {
    let result =
      match self.iterator_next_object(iterator) {
        Some(res) => res
        None => {
          self.iterator_close_on_error(iterator)
          return None
        }
      }
    let done = self.get_prop_value(result, "done").to_boolean()
    match self.peek_error() {
      Some(_) => {
        self.iterator_close_on_error(iterator)
        return None
      }
      None => ()
    }
    if done {
      break
    }
    let value = self.get_prop_value(result, "value")
    match self.peek_error() {
      Some(_) => {
        self.iterator_close_on_error(iterator)
        return None
      }
      None => ()
    }
    values.push(value)
  }
  Some(values)
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
  expr : @ast.TsExpr,
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
fn expr_has_yield(expr : @ast.TsExpr) -> Bool {
  match expr {
    @ast.TsExpr::Yield(_) => true
    @ast.TsExpr::YieldStar(_) => true
    @ast.TsExpr::Spread(inner) => expr_has_yield(inner)
    @ast.TsExpr::AssignExpr(_, value) => expr_has_yield(value)
    @ast.TsExpr::AssignPattern(binding, value) =>
      binding_has_yield(binding) || expr_has_yield(value)
    @ast.TsExpr::CompoundAssignExpr(left, _, right) =>
      expr_has_yield(left) || expr_has_yield(right)
    @ast.TsExpr::PropAssignExpr(obj, _, value) =>
      expr_has_yield(obj) || expr_has_yield(value)
    @ast.TsExpr::IndexAssignExpr(obj, index, value) =>
      expr_has_yield(obj) || expr_has_yield(index) || expr_has_yield(value)
    @ast.TsExpr::Seq(left, right) =>
      expr_has_yield(left) || expr_has_yield(right)
    @ast.TsExpr::BinOp(_, left, right) =>
      expr_has_yield(left) || expr_has_yield(right)
    @ast.TsExpr::UnaryOp(_, operand) => expr_has_yield(operand)
    @ast.TsExpr::Cond(cond, then_expr, else_expr) =>
      expr_has_yield(cond) || expr_has_yield(then_expr) || expr_has_yield(else_expr)
    @ast.TsExpr::CallExpr(callee, args) => {
      if expr_has_yield(callee) {
        true
      } else {
        for arg in args {
          match arg {
            @ast.TsExpr::Spread(inner) =>
              if expr_has_yield(inner) {
                return true
              }
            _ =>
              if expr_has_yield(arg) {
                return true
              }
          }
        }
        false
      }
    }
    @ast.TsExpr::Call(_, args) => {
      for arg in args {
        match arg {
          @ast.TsExpr::Spread(inner) =>
            if expr_has_yield(inner) {
              return true
            }
          _ =>
            if expr_has_yield(arg) {
              return true
            }
        }
      }
      false
    }
    @ast.TsExpr::MethodCall(receiver, _, args) => {
      if expr_has_yield(receiver) {
        true
      } else {
        for arg in args {
          match arg {
            @ast.TsExpr::Spread(inner) =>
              if expr_has_yield(inner) {
                return true
              }
            _ =>
              if expr_has_yield(arg) {
                return true
              }
          }
        }
        false
      }
    }
    @ast.TsExpr::IndexAccess(obj, index) =>
      expr_has_yield(obj) || expr_has_yield(index)
    @ast.TsExpr::PropAccess(obj, _) => expr_has_yield(obj)
    @ast.TsExpr::New(_, args) => {
      for arg in args {
        match arg {
          @ast.TsExpr::Spread(inner) =>
            if expr_has_yield(inner) {
              return true
            }
          _ =>
            if expr_has_yield(arg) {
              return true
            }
        }
      }
      false
    }
    @ast.TsExpr::NewExpr(expr, args) => {
      if expr_has_yield(expr) {
        true
      } else {
        for arg in args {
          match arg {
            @ast.TsExpr::Spread(inner) =>
              if expr_has_yield(inner) {
                return true
              }
            _ =>
              if expr_has_yield(arg) {
                return true
              }
          }
        }
        false
      }
    }
    @ast.TsExpr::ArrayLit(elements) => {
      for elem in elements {
        match elem {
          @ast.TsExpr::Spread(inner) =>
            if expr_has_yield(inner) {
              return true
            }
          _ =>
            if expr_has_yield(elem) {
              return true
            }
        }
      }
      false
    }
    @ast.TsExpr::ObjectLit(fields) => {
      for field in fields {
        let (_, value) = field
        if expr_has_yield(value) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::ArrowFunc(_, _) => false
    @ast.TsExpr::FuncExpr(_) => false
    _ => false
  }
}

///|
fn binding_has_yield(binding : @ast.TsBinding) -> Bool {
  match binding {
    @ast.TsBinding::Ident(_) => false
    @ast.TsBinding::Target(expr) => expr_has_yield(expr)
    @ast.TsBinding::Array(arr) => {
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
    @ast.TsBinding::Object(obj) => {
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

