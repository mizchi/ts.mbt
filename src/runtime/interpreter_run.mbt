///|
// / run
pub fn JSInterpreter::run_module(
  self : JSInterpreter,
  module_ : @ast.TsModule,
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
          let result =
            match self.exec_block(func_def.body, self.global_env) {
              Some(val) => val
              None => Undefined
            }
          self.drain_microtasks()
          result
        }
        _ => {
          let result = self.call_function(main_func, self.global_env.get("globalThis"), [])
          self.drain_microtasks()
          result
        }
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
