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
        if idx >= 0 && idx < arr.items.length() && arr.present[idx] {
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
        if idx >= 0 && idx < arr.items.length() && arr.present[idx] {
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
// / JS ToNumber (Object valueOf/toString)
fn JSInterpreter::to_number_value(self : JSInterpreter, value : JSValue) -> Double {
  match value {
    Object(_) | Array(_) | Function(_) => {
      let value_of = js_get_prop(value, "valueOf")
      if self.is_callable(value_of) {
        let res = self.call_function(value_of, value, [])
        match res {
          Object(_) | Array(_) | Function(_) => ()
          _ => return res.to_number()
        }
      }
      let to_str = js_get_prop(value, "toString")
      if self.is_callable(to_str) {
        let res = self.call_function(to_str, value, [])
        match res {
          Object(_) | Array(_) | Function(_) => ()
          _ => return res.to_number()
        }
      }
      value.to_number()
    }
    _ => value.to_number()
  }
}

///|
// / JSON string escape
fn JSInterpreter::json_escape(_self : JSInterpreter, s : String) -> String {
  let sb = StringBuilder::new()
  for ch in s {
    match ch {
      '\"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ => sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
// / JSON string unescape (minimal)
fn JSInterpreter::json_unescape(_self : JSInterpreter, s : String) -> String {
  let sb = StringBuilder::new()
  let mut i = 0
  let chars : Array[Char] = []
  for ch in s {
    chars.push(ch)
  }
  while i < chars.length() {
    let ch = chars[i]
    if ch == '\\' && i + 1 < chars.length() {
      let next = chars[i + 1]
      match next {
        '\"' => sb.write_char('\"')
        '\\' => sb.write_char('\\')
        'n' => sb.write_char('\n')
        'r' => sb.write_char('\r')
        't' => sb.write_char('\t')
        _ => sb.write_char(next)
      }
      i += 2
    } else {
      sb.write_char(ch)
      i += 1
    }
  }
  sb.to_string()
}

///|
// / JSON stringify (minimal)
fn JSInterpreter::json_stringify_value(
  self : JSInterpreter,
  value : JSValue,
  depth : Int,
  in_array : Bool,
) -> String? {
  if depth > 5 {
    return Some("null")
  }
  match value {
    Undefined =>
      if in_array {
        Some("null")
      } else {
        None
      }
    Function(_) =>
      if in_array {
        Some("null")
      } else {
        None
      }
    Null => Some("null")
    Bool(b) => Some(if b { "true" } else { "false" })
    Number(n) =>
      if n.is_nan() || n.is_inf() {
        Some("null")
      } else {
        Some(n.to_string())
      }
    String(s) => Some("\"" + self.json_escape(s) + "\"")
    Array(arr) => {
      let parts : Array[String] = []
      let arr_val = JSValue::Array(arr)
      let len = arr.length
      for i in 0..<len {
        let key = i.to_string()
        let elem =
          if js_has_prop(arr_val, key) {
            self.get_prop_value(arr_val, key)
          } else {
            Undefined
          }
        let elem_str = self.json_stringify_value(elem, depth + 1, true)
        match elem_str {
          Some(s) => parts.push(s)
          None => parts.push("null")
        }
      }
      Some("[" + parts.join(",") + "]")
    }
    Object(map) => {
      let parts : Array[String] = []
      for prop in map.props {
        if not(prop.enumerable) {
          continue
        }
        let value_str = self.json_stringify_value(
          self.eval_prop_value(JSValue::Object(map), prop),
          depth + 1,
          false,
        )
        match value_str {
          Some(s) => {
            let key = "\"" + self.json_escape(prop.key) + "\""
            parts.push(key + ":" + s)
          }
          None => ()
        }
      }
      Some("{" + parts.join(",") + "}")
    }
    BreakSignal | ContinueSignal => None
  }
}
