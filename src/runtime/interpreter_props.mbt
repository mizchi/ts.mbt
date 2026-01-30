///|
// / get
fn JSInterpreter::get_proto(_self : JSInterpreter, value : JSValue) -> JSValue? {
  match value {
    Object(_) | Function(_) | Array(_) =>
      if _self.is_proxy(value) {
        let proto_val = _self.proxy_get_prototype_of(value)
        match _self.peek_error() {
          Some(_) => None
          None =>
            match proto_val {
              Object(_) | Function(_) | Array(_) | Null => Some(proto_val)
              _ => None
            }
        }
      } else {
        match value {
          Object(map) => map.prototype
          Function(closure) => closure.object_proto
          Array(arr) => arr.prototype
          _ => None
        }
      }
    _ => None
  }
}

///|
fn JSInterpreter::normalize_prop_key(
  _self : JSInterpreter,
  key : String,
) -> String {
  if key == "Symbol(Symbol.iterator)" {
    "@@iterator"
  } else {
    key
  }
}

///|
/// Extract the original private name from a mangled private key (e.g. "__private_brand_0__#field" -> "#field")
fn extract_private_name(key : String) -> String {
  let len = key.length()
  let mut idx = 0
  while idx < len - 2 {
    if key[idx] == '_' && key[idx + 1] == '_' && key[idx + 2] == '#' {
      return key[(idx + 2):].to_string() catch { _ => key }
    }
    idx += 1
  }
  key
}

/// Check if a private property is a method or getter-only accessor (cannot be assigned)
/// Returns true if assignment should throw TypeError
fn is_private_readonly(obj : JSValue, key : String) -> Bool {
  // Check own property and prototype chain for getter-only accessor or method
  is_private_readonly_on_chain(obj, key)
}

/// Find a setter for a property on the prototype chain
fn find_setter_on_chain(obj : JSValue, key : String) -> JSValue? {
  match obj {
    Object(map) =>
      for prop in map.props {
        if prop.key == key {
          return prop.set
        }
      }
    Function(closure) =>
      for prop in closure.props {
        if prop.key == key {
          return prop.set
        }
      }
    _ => ()
  }
  // Check prototype chain
  match obj {
    Object(map) =>
      match map.prototype {
        Some(proto) => find_setter_on_chain(proto, key)
        None => None
      }
    Function(closure) =>
      match closure.object_proto {
        Some(proto) => find_setter_on_chain(proto, key)
        None => None
      }
    _ => None
  }
}

/// Recursively check if a property is readonly on the prototype chain
fn is_private_readonly_on_chain(obj : JSValue, key : String) -> Bool {
  // Check own properties first
  match obj {
    Object(map) =>
      for prop in map.props {
        if prop.key == key {
          // Accessor with getter but no setter
          if prop.get is Some(_) && prop.set is None {
            return true
          }
          // Method (function value)
          match prop.value {
            Function(_) => return true
            _ => ()
          }
          return false
        }
      }
    Function(closure) =>
      for prop in closure.props {
        if prop.key == key {
          // Accessor with getter but no setter
          if prop.get is Some(_) && prop.set is None {
            return true
          }
          // Method (function value)
          match prop.value {
            Function(_) => return true
            _ => ()
          }
          return false
        }
      }
    _ => ()
  }
  // Check prototype chain
  match obj {
    Object(map) =>
      match map.prototype {
        Some(proto) => is_private_readonly_on_chain(proto, key)
        None => false
      }
    Function(closure) =>
      match closure.object_proto {
        Some(proto) => is_private_readonly_on_chain(proto, key)
        None => false
      }
    _ => false
  }
}


///|
/// Check if a property name is a mangled private field (e.g. __private_brand_0__#field)
/// and extract the brand name if so.
fn extract_private_brand(key : String) -> String? {
  // Pattern: __private_brand_N__#fieldname
  if key.has_prefix("__private_brand_") {
    // Find the position of "__#" by checking key contains it
    if key.contains("__#") {
      // Find the index where "__#" starts
      let len = key.length()
      let mut idx = 0
      while idx < len - 2 {
        if key[idx] == '_' && key[idx + 1] == '_' && key[idx + 2] == '#' {
          // Brand is everything before "__#"
          let brand = key[:idx].to_string() catch { _ => "" }
          return Some(brand)
        }
        idx += 1
      }
    }
    None
  } else {
    None
  }
}

///|
/// Check if the target object has the required brand for private field access.
/// Returns true if access is allowed, false if brand check fails.
fn JSInterpreter::check_private_brand(
  self : JSInterpreter,
  obj : JSValue,
  brand : String,
  key : String,
) -> Bool {
  // Check if obj has the brand property set to true
  let brand_value = js_get_prop(obj, brand)
  match brand_value {
    Bool(true) => true
    _ => {
      // Extract the original private field name (part after "__#")
      let original_name = if key.contains("__#") {
        let len = key.length()
        let mut idx = 0
        while idx < len - 2 {
          if key[idx] == '_' && key[idx + 1] == '_' && key[idx + 2] == '#' {
            // Return everything after "__" (so including the #)
            break
          }
          idx += 1
        }
        key[idx + 2:].to_string() catch { _ => key }
      } else {
        key
      }
      let _ = self.set_error_kind(
        "TypeError",
        "Cannot read private member \{original_name} from an object whose class did not declare it",
      )
      false
    }
  }
}

///|
fn JSInterpreter::proxy_key_value(
  _self : JSInterpreter,
  key : String,
) -> JSValue {
  if key == "@@iterator" {
    String("Symbol(Symbol.iterator)")
  } else {
    String(key)
  }
}

///|
fn JSInterpreter::is_proxy(_self : JSInterpreter, value : JSValue) -> Bool {
  match value {
    Object(_) | Function(_) | Array(_) =>
      js_has_prop(value, "__proxy_target") &&
      js_has_prop(value, "__proxy_handler")
    _ => false
  }
}

///|
fn JSInterpreter::proxy_target(
  _self : JSInterpreter,
  proxy : JSValue,
) -> JSValue {
  js_get_prop(proxy, "__proxy_target")
}

///|
fn JSInterpreter::proxy_handler(
  _self : JSInterpreter,
  proxy : JSValue,
) -> JSValue {
  js_get_prop(proxy, "__proxy_handler")
}

///|
fn JSInterpreter::new_proxy(
  self : JSInterpreter,
  target : JSValue,
  handler : JSValue,
) -> JSValue {
  match target {
    Object(_) | Function(_) | Array(_) => ()
    _ => {
      let _ = self.set_error_kind("TypeError", "Proxy target is not an object")
      return Undefined
    }
  }
  match handler {
    Object(_) | Function(_) | Array(_) => ()
    _ => {
      let _ = self.set_error_kind("TypeError", "Proxy handler is not an object")
      return Undefined
    }
  }
  let proxy = self.new_object()
  let _ = js_set_prop(proxy, "__proxy_target", target)
  let _ = js_set_prop(proxy, "__proxy_handler", handler)
  proxy
}

///|
fn JSInterpreter::get_proxy_trap(
  self : JSInterpreter,
  handler : JSValue,
  name : String,
) -> JSValue? {
  let trap = self.get_prop_value(handler, name)
  match self.peek_error() {
    Some(_) => return None
    None => ()
  }
  match trap {
    Undefined | Null => None
    _ =>
      if not(self.is_callable(trap)) {
        let _ = self.set_error_kind("TypeError", "Proxy trap is not callable")
        None
      } else {
        Some(trap)
      }
  }
}

///|
fn JSInterpreter::proxy_get(
  self : JSInterpreter,
  proxy : JSValue,
  key : String,
  receiver : JSValue,
) -> JSValue {
  let handler = self.proxy_handler(proxy)
  match handler {
    Null | Undefined =>
      return self.set_error_kind(
        "TypeError", "Cannot perform operation on a revoked Proxy",
      )
    _ => ()
  }
  let target = self.proxy_target(proxy)
  let norm_key = self.normalize_prop_key(key)
  let key_val = self.proxy_key_value(norm_key)
  match self.get_proxy_trap(handler, "get") {
    Some(trap) => self.call_function(trap, handler, [target, key_val, receiver])
    None => self.get_prop_value_with_receiver(target, receiver, norm_key)
  }
}

///|
fn JSInterpreter::proxy_set(
  self : JSInterpreter,
  proxy : JSValue,
  key : String,
  value : JSValue,
  receiver : JSValue,
) -> Bool {
  let handler = self.proxy_handler(proxy)
  match handler {
    Null | Undefined => {
      let _ = self.set_error_kind(
        "TypeError", "Cannot perform operation on a revoked Proxy",
      )
      return false
    }
    _ => ()
  }
  let target = self.proxy_target(proxy)
  let norm_key = self.normalize_prop_key(key)
  let key_val = self.proxy_key_value(norm_key)
  match self.get_proxy_trap(handler, "set") {
    Some(trap) => {
      let result = self.call_function(trap, handler, [
        target, key_val, value, receiver,
      ])
      match self.peek_error() {
        Some(_) => false
        None => result.to_boolean()
      }
    }
    None => {
      self.set_prop_value(target, norm_key, value)
      match self.peek_error() {
        Some(_) => false
        None => true
      }
    }
  }
}

///|
fn JSInterpreter::proxy_has(
  self : JSInterpreter,
  proxy : JSValue,
  key : String,
) -> Bool {
  let handler = self.proxy_handler(proxy)
  match handler {
    Null | Undefined => {
      let _ = self.set_error_kind(
        "TypeError", "Cannot perform operation on a revoked Proxy",
      )
      return false
    }
    _ => ()
  }
  let target = self.proxy_target(proxy)
  let norm_key = self.normalize_prop_key(key)
  let key_val = self.proxy_key_value(norm_key)
  match self.get_proxy_trap(handler, "has") {
    Some(trap) => {
      let result = self.call_function(trap, handler, [target, key_val])
      match self.peek_error() {
        Some(_) => false
        None => result.to_boolean()
      }
    }
    None => js_has_prop(target, norm_key)
  }
}

///|
fn JSInterpreter::proxy_get_own_property_descriptor(
  self : JSInterpreter,
  proxy : JSValue,
  key : String,
) -> JSValue {
  let handler = self.proxy_handler(proxy)
  match handler {
    Null | Undefined =>
      return self.set_error_kind(
        "TypeError", "Cannot perform operation on a revoked Proxy",
      )
    _ => ()
  }
  let target = self.proxy_target(proxy)
  let norm_key = self.normalize_prop_key(key)
  let key_val = self.proxy_key_value(norm_key)
  match self.get_proxy_trap(handler, "getOwnPropertyDescriptor") {
    Some(trap) => self.call_function(trap, handler, [target, key_val])
    None =>
      self.call_native("Object.getOwnPropertyDescriptor", Undefined, [
        target,
        String(norm_key),
      ])
  }
}

///|
fn JSInterpreter::proxy_define_property(
  self : JSInterpreter,
  proxy : JSValue,
  key : String,
  desc : JSValue,
) -> JSValue {
  let handler = self.proxy_handler(proxy)
  match handler {
    Null | Undefined =>
      return self.set_error_kind(
        "TypeError", "Cannot perform operation on a revoked Proxy",
      )
    _ => ()
  }
  let target = self.proxy_target(proxy)
  let norm_key = self.normalize_prop_key(key)
  let key_val = self.proxy_key_value(norm_key)
  match self.get_proxy_trap(handler, "defineProperty") {
    Some(trap) => {
      let result = self.call_function(trap, handler, [target, key_val, desc])
      match self.peek_error() {
        Some(err) => err
        None => result
      }
    }
    None => self.define_property(target, norm_key, desc)
  }
}

///|
fn JSInterpreter::proxy_get_prototype_of(
  self : JSInterpreter,
  proxy : JSValue,
) -> JSValue {
  let handler = self.proxy_handler(proxy)
  match handler {
    Null | Undefined =>
      return self.set_error_kind(
        "TypeError", "Cannot perform operation on a revoked Proxy",
      )
    _ => ()
  }
  let target = self.proxy_target(proxy)
  match self.get_proxy_trap(handler, "getPrototypeOf") {
    Some(trap) => self.call_function(trap, handler, [target])
    None => {
      let proto = match target {
        Object(map) =>
          match map.prototype {
            Some(p) => p
            None => Null
          }
        Function(closure) =>
          match closure.object_proto {
            Some(p) => p
            None => Null
          }
        Array(arr) =>
          match arr.prototype {
            Some(p) => p
            None => Null
          }
        _ => Null
      }
      proto
    }
  }
}

///|
// / propertyget()
pub fn JSInterpreter::get_prop_value(
  self : JSInterpreter,
  obj : JSValue,
  key : String,
) -> JSValue {
  self.get_prop_value_with_receiver(obj, obj, key)
}

///|
fn JSInterpreter::set_prop_value(
  self : JSInterpreter,
  obj : JSValue,
  key : String,
  value : JSValue,
  strict? : Bool = false,
) -> Unit {
  let key = self.normalize_prop_key(key)
  if self.is_proxy(obj) {
    let _ = self.proxy_set(obj, key, value, obj)
    return
  }
  // Check private field brand before access
  match extract_private_brand(key) {
    Some(brand) => {
      if not(self.check_private_brand(obj, brand, key)) {
        return
      }
      // PrivateSet throws TypeError when:
      //   - the private element is a method (entry.[[Kind]] is ~method~)
      //   - the private element is an accessor with no setter (entry.[[Set]] is undefined)
      if is_private_readonly(obj, key) {
        let original_name = extract_private_name(key)
        let _ = self.set_error_kind(
          "TypeError",
          "Cannot assign to private member \{original_name}",
        )
        return
      }
      // For private properties with setters on the prototype chain, call the setter
      match find_setter_on_chain(obj, key) {
        Some(setter) => {
          let _ = self.call_function(setter, obj, [value])
          return
        }
        None => ()
      }
    }
    None => ()
  }
  // Setting a property on null/undefined always throws TypeError (regardless of strict mode)
  match obj {
    Null => {
      let _ = self.set_error_kind(
        "TypeError",
        "Cannot set properties of null (setting '\{key}')",
      )
      return
    }
    Undefined => {
      let _ = self.set_error_kind(
        "TypeError",
        "Cannot set properties of undefined (setting '\{key}')",
      )
      return
    }
    _ => ()
  }
  match obj {
    Function(closure) =>
      for prop in closure.props {
        if prop.key == key {
          match prop.set {
            Some(setter) => {
              let _ = self.call_function(setter, obj, [value])
              return
            }
            None =>
              if not(prop.writable) {
                if strict {
                  let _ = self.set_error_kind(
                    "TypeError",
                    "Cannot assign to read only property '\{key}'",
                  )
                }
                return
              } else {
                let _ = js_set_prop(obj, key, value)
                return
              }
          }
        }
      }
    Object(map) =>
      for prop in map.props {
        if prop.key == key {
          match prop.set {
            Some(setter) => {
              let _ = self.call_function(setter, obj, [value])
              return
            }
            None =>
              if not(prop.writable) {
                if strict {
                  let _ = self.set_error_kind(
                    "TypeError",
                    "Cannot assign to read only property '\{key}'",
                  )
                }
                return
              } else {
                let _ = js_set_prop(obj, key, value)
                return
              }
          }
        }
      }
    Array(arr) =>
      for prop in arr.props {
        if prop.key == key {
          match prop.set {
            Some(setter) => {
              let _ = self.call_function(setter, obj, [value])
              return
            }
            None =>
              if not(prop.writable) {
                if strict {
                  let _ = self.set_error_kind(
                    "TypeError",
                    "Cannot assign to read only property '\{key}'",
                  )
                }
                return
              } else {
                let _ = js_set_prop(obj, key, value)
                return
              }
          }
        }
      }
    _ => ()
  }
  // Check if object is non-extensible and we're adding a new property
  if strict && not(self.has_own_prop(obj, key)) {
    match js_get_prop(obj, "__non_extensible") {
      Bool(true) => {
        let _ = self.set_error_kind(
          "TypeError",
          "Cannot add property \{key}, object is not extensible",
        )
        return
      }
      _ => ()
    }
  }
  let _ = js_set_prop(obj, key, value)
}

///|
// / propertyget
fn JSInterpreter::get_prop_value_with_receiver(
  self : JSInterpreter,
  target : JSValue,
  receiver : JSValue,
  key : String,
) -> JSValue {
  let key = self.normalize_prop_key(key)
  if self.is_proxy(target) {
    return self.proxy_get(target, key, receiver)
  }
  // Check private field brand before access
  match extract_private_brand(key) {
    Some(brand) =>
      if not(self.check_private_brand(receiver, brand, key)) {
        return Undefined
      }
    None => ()
  }
  match target {
    Null => {
      let _ = self.set_error_kind(
        "TypeError",
        "Cannot read properties of null (reading '\{key}')",
      )
      return Undefined
    }
    Undefined => {
      let _ = self.set_error_kind(
        "TypeError",
        "Cannot read properties of undefined (reading '\{key}')",
      )
      return Undefined
    }
    _ => ()
  }
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
      // Handle Map/Set.size specially
      if key == "size" {
        match js_get_prop(target, "__class") {
          String("Map") =>
            match js_get_prop(target, "__map_entries") {
              JSValue::Array(arr) => return Number(arr.length.to_double())
              _ => ()
            }
          String("Set") =>
            match js_get_prop(target, "__set_entries") {
              JSValue::Array(arr) => return Number(arr.length.to_double())
              _ => ()
            }
          _ => ()
        }
      }
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
              Some(proto) =>
                self.get_prop_value_with_receiver(proto, receiver, key)
              None => Undefined
            }
          }
        }
      }
    String(s) =>
      // Check if this is a symbol (Symbol(...)#N, @@global:key, or @@name)
      // Note: "Symbol(...)" without #N suffix is NOT a symbol (it's the toString result)
      if s.has_prefix("@@") || (s.has_prefix("Symbol(") && s.contains("#")) {
        // Look up on Symbol.prototype
        let symbol_ctor = self.global_env.get("Symbol")
        let symbol_proto = js_get_prop(symbol_ctor, "prototype")
        self.get_prop_value_with_receiver(symbol_proto, receiver, key)
      } else if key == "length" {
        Number(s.length().to_double())
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < s.length() {
          String(s[idx:idx + 1].to_string() catch { _ => "" })
        } else {
          // Look up on String.prototype
          let string_ctor = self.global_env.get("String")
          let string_proto = js_get_prop(string_ctor, "prototype")
          self.get_prop_value_with_receiver(string_proto, receiver, key)
        }
      }
    Number(_) => {
      // Look up on Number.prototype
      let number_ctor = self.global_env.get("Number")
      let number_proto = js_get_prop(number_ctor, "prototype")
      self.get_prop_value_with_receiver(number_proto, receiver, key)
    }
    Bool(_) => {
      // Look up on Boolean.prototype
      let boolean_ctor = self.global_env.get("Boolean")
      let boolean_proto = js_get_prop(boolean_ctor, "prototype")
      self.get_prop_value_with_receiver(boolean_proto, receiver, key)
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
fn JSInterpreter::has_own_prop(
  _self : JSInterpreter,
  obj : JSValue,
  key : String,
) -> Bool {
  let key = _self.normalize_prop_key(key)
  if _self.is_proxy(obj) {
    return _self.proxy_has(obj, key)
  }
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
fn JSInterpreter::is_enumerable(
  _self : JSInterpreter,
  obj : JSValue,
  key : String,
) -> Bool {
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
        Native(name) if name == "Promise" => {
          let executor = if args.length() > 0 { args[0] } else { Undefined }
          if not(self.is_callable(executor)) {
            return self.set_error_kind(
              "TypeError", "Promise resolver is not a function",
            )
          }
        }
        _ => ()
      }
    _ => ()
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
  let proto_val = self.get_prop_value(new_target, "prototype")
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  let mut proto = proto_val
  match proto {
    Object(_) | Function(_) => ()
    _ => {
      let fallback = js_get_prop(new_target, "__default_proto__")
      match fallback {
        Object(_) | Function(_) => proto = fallback
        _ => {
          let fallback_ctor = js_get_prop(ctor, "__default_proto__")
          match fallback_ctor {
            Object(_) | Function(_) => proto = fallback_ctor
            _ => ()
          }
        }
      }
    }
  }
  let instance = match proto {
    Object(_) | Function(_) => js_new_object_with_proto(Some(proto))
    _ => self.new_object()
  }
  let result = self.call_function(ctor, instance, args, new_target~)
  match result {
    Object(_) | Array(_) | Function(_) => result
    _ => instance
  }
}

///|
// / object
fn JSInterpreter::wrap_primitive(
  self : JSInterpreter,
  env : JSEnv,
  value : JSValue,
) -> JSValue {
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
    Object(_) | Array(_) | Function(_) => String(self.to_string_value(value))
    _ => value
  }
}

///|
// / JS ToPropertyKey - convert a value to a property key (string or symbol)
fn JSInterpreter::to_property_key(
  self : JSInterpreter,
  value : JSValue,
) -> String {
  // For symbols, return the symbol representation (includes unique ID)
  match value {
    String(s) if s.has_prefix("Symbol(") && s.contains("#") => s
    String(s) if s.has_prefix("Symbol(") => s // Well-known symbols like Symbol(Symbol.iterator)
    _ => self.to_string_value(value)
  }
}

///|
// / JS ToString (Object toString )
fn JSInterpreter::to_string_value(
  self : JSInterpreter,
  value : JSValue,
) -> String {
  match value {
    String(s) =>
      if s.has_prefix("Symbol(") {
        let _ = self.set_error_kind(
          "TypeError", "Cannot convert Symbol to string",
        )
        ""
      } else {
        s
      }
    Object(_) | Array(_) | Function(_) => {
      let to_prim = js_get_prop(value, "@@toPrimitive")
      if self.is_callable(to_prim) {
        let res = self.call_function(to_prim, value, [String("string")])
        match res {
          Object(_) | Array(_) | Function(_) => {
            let _ = self.set_error_kind(
              "TypeError", "Cannot convert object to primitive value",
            )
            return ""
          }
          _ => return res.to_js_string()
        }
      } else if not(to_prim.is_undefined()) {
        let _ = self.set_error_kind(
          "TypeError", "Cannot convert object to primitive value",
        )
        return ""
      }
      match js_get_prop(value, "__class") {
        String("BigInt") =>
          match js_get_prop(value, "value") {
            String(s) => return s
            _ => ()
          }
        _ => ()
      }
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
fn JSInterpreter::to_number_value(
  self : JSInterpreter,
  value : JSValue,
) -> Double {
  match value {
    String(s) =>
      if s.has_prefix("Symbol(") {
        let _ = self.set_error_kind(
          "TypeError", "Cannot convert Symbol to number",
        )
        0.0
      } else {
        value.to_number()
      }
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
  self.tick()
  match self.peek_error() {
    Some(_) => return None
    None => ()
  }
  if depth > 5 {
    return Some("null")
  }
  match value {
    Undefined => if in_array { Some("null") } else { None }
    Function(_) => if in_array { Some("null") } else { None }
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
        self.tick()
        match self.peek_error() {
          Some(_) => return None
          None => ()
        }
        let key = i.to_string()
        let elem = if js_has_prop(arr_val, key) {
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
      let keys : Array[String] = []
      for prop in map.props {
        if prop.enumerable {
          keys.push(prop.key)
        }
      }
      let parts : Array[String] = []
      for key in keys {
        self.tick()
        match self.peek_error() {
          Some(_) => return None
          None => ()
        }
        let value_str = self.json_stringify_value(
          self.get_prop_value(JSValue::Object(map), key),
          depth + 1,
          false,
        )
        match value_str {
          Some(s) => {
            let key_str = "\"" + self.json_escape(key) + "\""
            parts.push(key_str + ":" + s)
          }
          None => ()
        }
      }
      Some("{" + parts.join(",") + "}")
    }
    BreakSignal(_) | ContinueSignal(_) | Empty => None
  }
}
