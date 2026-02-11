// JSValue interpreter errors/state

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
// / Get the last error (public API for test runners)
pub fn JSInterpreter::get_last_error(self : JSInterpreter) -> JSValue? {
  self.last_error
}
