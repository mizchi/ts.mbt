///|
fn JSInterpreter::call_object_native(
  self : JSInterpreter,
  name : String,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue? {
  match name {
    "Object.create" => {
      let proto = if args.length() > 0 { args[0] } else { Undefined }
      Some(
        match proto {
          Null => js_new_object_with_proto(None)
          Object(_) | Function(_) | Array(_) =>
            js_new_object_with_proto(Some(proto))
          _ => self.new_object()
        },
      )
    }
    "Object.getPrototypeOf" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      if self.is_proxy(target) {
        return Some(self.proxy_get_prototype_of(target))
      }
      Some(
        match target {
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
          _ => Undefined
        },
      )
    }
    "Object.getOwnPropertyDescriptor" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let raw_key = if args.length() > 1 { args[1].to_js_string() } else { "" }
      let key = self.normalize_prop_key(raw_key)
      if self.is_proxy(target) {
        return Some(self.proxy_get_own_property_descriptor(target, key))
      }
      Some(
        match target {
          Function(closure) => {
            let mut result : JSValue = Undefined
            for prop in closure.props {
              if prop.key == key {
                result = if prop.get is Some(_) || prop.set is Some(_) {
                  self.make_accessor_descriptor(
                    prop.get,
                    prop.set,
                    prop.enumerable,
                    prop.configurable,
                  )
                } else {
                  self.make_data_descriptor(
                    prop.value,
                    prop.writable,
                    prop.enumerable,
                    prop.configurable,
                  )
                }
                break
              }
            }
            result
          }
          Object(map) => {
            let mut result : JSValue = Undefined
            for prop in map.props {
              if prop.key == key {
                result = if prop.get is Some(_) || prop.set is Some(_) {
                  self.make_accessor_descriptor(
                    prop.get,
                    prop.set,
                    prop.enumerable,
                    prop.configurable,
                  )
                } else {
                  self.make_data_descriptor(
                    prop.value,
                    prop.writable,
                    prop.enumerable,
                    prop.configurable,
                  )
                }
                break
              }
            }
            result
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
              if idx >= 0 && idx < arr.items.length() && arr.present[idx] {
                self.make_data_descriptor(arr.items[idx], true, true, true)
              } else {
                let mut result : JSValue = Undefined
                for prop in arr.props {
                  if prop.key == key {
                    result = if prop.get is Some(_) || prop.set is Some(_) {
                      self.make_accessor_descriptor(
                        prop.get,
                        prop.set,
                        prop.enumerable,
                        prop.configurable,
                      )
                    } else {
                      self.make_data_descriptor(
                        prop.value,
                        prop.writable,
                        prop.enumerable,
                        prop.configurable,
                      )
                    }
                    break
                  }
                }
                result
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
              let idx = @strconv.parse_int(key) catch { _ => -1 }
              if idx >= 0 && idx < s.length() {
                let ch = JSValue::String(
                  s[idx:idx + 1].to_string() catch {
                    _ => ""
                  },
                )
                self.make_data_descriptor(ch, false, true, false)
              } else {
                Undefined
              }
            }
          _ => Undefined
        },
      )
    }
    "Object.defineProperties" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let props = if args.length() > 1 { args[1] } else { Undefined }
      let receiver = match target {
        Undefined | Null =>
          return Some(
            self.set_error_kind(
              "TypeError", "Object.defineProperties called on null or undefined",
            ),
          )
        Object(_) | Function(_) | Array(_) => target
        _ =>
          return Some(
            self.set_error_kind(
              "TypeError", "Object.defineProperties called on non-object",
            ),
          )
      }
      match props {
        Object(_) | Function(_) | Array(_) => {
          let keys = self.own_property_keys(props)
          for key in keys {
            let desc = self.get_prop_value(props, key)
            match self.peek_error() {
              Some(err) => return Some(err)
              None => ()
            }
            let _ = self.define_property(receiver, key, desc)
            match self.peek_error() {
              Some(err) => return Some(err)
              None => ()
            }
          }
          Some(receiver)
        }
        _ => Some(receiver)
      }
    }
    "Object.defineProperty" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let raw_key = if args.length() > 1 {
        self.to_property_key(args[1])
      } else {
        ""
      }
      let key = self.normalize_prop_key(raw_key)
      let desc = if args.length() > 2 { args[2] } else { Undefined }
      let receiver = match target {
        Undefined | Null =>
          return Some(
            self.set_error_kind(
              "TypeError", "Object.defineProperty called on null or undefined",
            ),
          )
        Object(_) | Function(_) | Array(_) => target
        _ =>
          return Some(
            self.set_error_kind(
              "TypeError", "Object.defineProperty called on non-object",
            ),
          )
      }
      let _ = self.define_property(receiver, key, desc)
      Some(
        match self.peek_error() {
          Some(err) => err
          None => receiver
        },
      )
    }
    "Object.setPrototypeOf" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let proto = if args.length() > 1 { args[1] } else { Undefined }
      match target {
        Object(_) | Function(_) | Array(_) => ()
        _ =>
          return Some(
            self.set_error_kind(
              "TypeError", "Object.setPrototypeOf called on non-object",
            ),
          )
      }
      match proto {
        Object(_) | Function(_) | Array(_) | Null => ()
        _ =>
          return Some(
            self.set_error_kind(
              "TypeError", "Object.setPrototypeOf called with invalid prototype",
            ),
          )
      }
      let _ = js_set_prop(target, "__proto__", proto)
      Some(target)
    }
    "Object.hasOwnProperty" => {
      let key = if args.length() > 0 { args[0].to_js_string() } else { "" }
      Some(
        match this_arg {
          Object(map) => {
            let mut found = false
            for prop in map.props {
              if prop.key == key {
                found = true
                break
              }
            }
            Bool(found)
          }
          Function(closure) => {
            let mut found = false
            for prop in closure.props {
              if prop.key == key {
                found = true
                break
              }
            }
            Bool(found)
          }
          Array(arr) =>
            if key == "length" {
              Bool(true)
            } else {
              let idx = @strconv.parse_int(key) catch { _ => -1 }
              if idx >= 0 && idx < arr.items.length() && arr.present[idx] {
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
        },
      )
    }
    "Object.prototype.propertyIsEnumerable" => {
      let key = if args.length() > 0 { args[0].to_js_string() } else { "" }
      Some(
        if self.has_own_prop(this_arg, key) {
          Bool(self.is_enumerable(this_arg, key))
        } else {
          Bool(false)
        },
      )
    }
    "Object.getOwnPropertyNames" =>
      Some(self.object_get_own_property_names(args))
    "Object.getOwnPropertySymbols" =>
      Some(self.object_get_own_property_symbols(args))
    "Object.keys" => Some(self.object_keys(args))
    "Object.values" => Some(self.object_values(args))
    "Object.entries" => Some(self.object_entries(args))
    "Object.assign" => Some(self.object_assign(args))
    "Object.fromEntries" => Some(self.object_from_entries(args))
    "Object.isExtensible" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      Some(
        match target {
          Object(_) | Function(_) | Array(_) =>
            match js_get_prop(target, "__non_extensible") {
              Bool(true) => Bool(false)
              _ => Bool(true)
            }
          _ => Bool(false)
        },
      )
    }
    "Object.preventExtensions" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      Some(
        match target {
          Object(_) | Function(_) | Array(_) => {
            let _ = js_define_data_prop(
              target,
              "__non_extensible",
              Bool(true),
              false,
              false,
              false,
            )
            target
          }
          _ => target
        },
      )
    }
    "Object.freeze" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      Some(
        match target {
          Object(_) | Function(_) | Array(_) => {
            let _ = js_define_data_prop(
              target,
              "__non_extensible",
              Bool(true),
              false,
              false,
              false,
            )
            let _ = js_define_data_prop(
              target,
              "__frozen",
              Bool(true),
              false,
              false,
              false,
            )
            target
          }
          _ => target
        },
      )
    }
    "Object.seal" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      Some(
        match target {
          Object(_) | Function(_) | Array(_) => {
            let _ = js_define_data_prop(
              target,
              "__non_extensible",
              Bool(true),
              false,
              false,
              false,
            )
            let _ = js_define_data_prop(
              target,
              "__sealed",
              Bool(true),
              false,
              false,
              false,
            )
            target
          }
          _ => target
        },
      )
    }
    "Object.isFrozen" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      Some(
        match target {
          Object(_) | Function(_) | Array(_) =>
            match js_get_prop(target, "__frozen") {
              Bool(true) => Bool(true)
              _ => Bool(false)
            }
          _ => Bool(true)
        },
      )
    }
    "Object.isSealed" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      Some(
        match target {
          Object(_) | Function(_) | Array(_) =>
            match js_get_prop(target, "__sealed") {
              Bool(true) => Bool(true)
              _ =>
                match js_get_prop(target, "__frozen") {
                  Bool(true) => Bool(true)
                  _ => Bool(false)
                }
            }
          _ => Bool(true)
        },
      )
    }
    "Object.is" => {
      let left = if args.length() > 0 { args[0] } else { Undefined }
      let right = if args.length() > 1 { args[1] } else { Undefined }
      Some(Bool(self.same_value(left, right)))
    }
    "Object.prototype.toString" =>
      Some(
        {
          let tag = match this_arg {
            Undefined => "Undefined"
            Null => "Null"
            Bool(_) => "Boolean"
            Number(_) => "Number"
            String(_) => "String"
            BigInt(_) => "BigInt"
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
            BreakSignal(_) | ContinueSignal(_) | Empty => "Object"
          }
          String("[object " + tag + "]")
        },
      )
    "Object.prototype.isPrototypeOf" =>
      Some(
        if args.length() == 0 {
          Bool(false)
        } else {
          let target = args[0]
          let mut cur = self.get_proto(target)
          let mut found = false
          while cur is Some(p) {
            match js_strict_eq(p, this_arg) {
              Bool(true) => {
                found = true
                break
              }
              _ => ()
            }
            cur = self.get_proto(p)
          }
          Bool(found)
        },
      )
    "Object.prototype.valueOf" => Some(this_arg)
    _ => None
  }
}

///|
fn JSInterpreter::object_get_own_property_names(
  _self : JSInterpreter,
  args : Array[JSValue],
) -> JSValue {
  let target = if args.length() > 0 { args[0] } else { Undefined }
  let names : Array[JSValue] = []
  match target {
    Function(closure) =>
      for prop in closure.props {
        if not(prop.key.has_prefix("Symbol(")) {
          names.push(String(prop.key))
        }
      }
    Object(map) =>
      for prop in map.props {
        if not(prop.key.has_prefix("Symbol(")) {
          names.push(String(prop.key))
        }
      }
    Array(arr) => {
      for i in 0..<arr.items.length() {
        if arr.present[i] {
          names.push(String(i.to_string()))
        }
      }
      for prop in arr.props {
        if not(prop.key.has_prefix("Symbol(")) {
          names.push(String(prop.key))
        }
      }
      names.push(String("length"))
    }
    _ => ()
  }
  let integer_keys : Array[(Int, String)] = []
  let string_keys : Array[String] = []
  for item in names {
    match item {
      String(s) => {
        let is_index = s.length() > 0 &&
          {
            let mut valid = true
            let has_leading_zero = s.length() > 1 && s[0] == '0'
            for i = 0; i < s.length(); i = i + 1 {
              let c = s[i]
              if c < '0' || c > '9' {
                valid = false
                break
              }
            }
            valid && not(has_leading_zero)
          }
        if is_index {
          let mut n = 0
          for i = 0; i < s.length(); i = i + 1 {
            n = n * 10 + (s[i].to_int() - '0'.to_int())
          }
          integer_keys.push((n, s))
        } else {
          string_keys.push(s)
        }
      }
      _ => ()
    }
  }
  integer_keys.sort_by(fn(a, b) { a.0.compare(b.0) })
  let reordered : Array[JSValue] = []
  for pair in integer_keys {
    reordered.push(String(pair.1))
  }
  for key in string_keys {
    reordered.push(String(key))
  }
  match target {
    Function(_) => {
      let others : Array[JSValue] = []
      let mut has_length = false
      let mut has_name = false
      for item in reordered {
        match item {
          String("length") => has_length = true
          String("name") => has_name = true
          _ => others.push(item)
        }
      }
      let final_result : Array[JSValue] = []
      if has_length {
        final_result.push(String("length"))
      }
      if has_name {
        final_result.push(String("name"))
      }
      for item in others {
        final_result.push(item)
      }
      return js_array_from(final_result)
    }
    _ => ()
  }
  js_array_from(reordered)
}

///|
fn JSInterpreter::object_get_own_property_symbols(
  _self : JSInterpreter,
  args : Array[JSValue],
) -> JSValue {
  let target = if args.length() > 0 { args[0] } else { Undefined }
  let symbols : Array[JSValue] = []
  match target {
    Function(closure) =>
      for prop in closure.props {
        if prop.key.has_prefix("Symbol(") {
          symbols.push(String(prop.key))
        }
      }
    Object(map) =>
      for prop in map.props {
        if prop.key.has_prefix("Symbol(") {
          symbols.push(String(prop.key))
        }
      }
    Array(arr) =>
      for prop in arr.props {
        if prop.key.has_prefix("Symbol(") {
          symbols.push(String(prop.key))
        }
      }
    _ => ()
  }
  js_array_from(symbols)
}

///|
fn JSInterpreter::object_keys(
  _self : JSInterpreter,
  args : Array[JSValue],
) -> JSValue {
  let target = if args.length() > 0 { args[0] } else { Undefined }
  let names : Array[JSValue] = []
  match target {
    Function(closure) =>
      for prop in closure.props {
        if prop.enumerable {
          names.push(String(prop.key))
        }
      }
    Object(map) =>
      for prop in map.props {
        if prop.enumerable {
          names.push(String(prop.key))
        }
      }
    Array(arr) => {
      for i in 0..<arr.items.length() {
        if arr.present[i] {
          names.push(String(i.to_string()))
        }
      }
      for prop in arr.props {
        if prop.enumerable {
          names.push(String(prop.key))
        }
      }
    }
    _ => ()
  }
  js_array_from(names)
}

///|
fn JSInterpreter::object_values(
  _self : JSInterpreter,
  args : Array[JSValue],
) -> JSValue {
  let target = if args.length() > 0 { args[0] } else { Undefined }
  let values : Array[JSValue] = []
  match target {
    Function(closure) =>
      for prop in closure.props {
        if prop.enumerable {
          values.push(prop.value)
        }
      }
    Object(map) =>
      for prop in map.props {
        if prop.enumerable {
          values.push(prop.value)
        }
      }
    Array(arr) => {
      for i in 0..<arr.items.length() {
        if arr.present[i] {
          values.push(arr.items[i])
        }
      }
      for prop in arr.props {
        if prop.enumerable {
          values.push(prop.value)
        }
      }
    }
    _ => ()
  }
  js_array_from(values)
}

///|
fn JSInterpreter::object_entries(
  _self : JSInterpreter,
  args : Array[JSValue],
) -> JSValue {
  let target = if args.length() > 0 { args[0] } else { Undefined }
  let entries : Array[JSValue] = []
  match target {
    Function(closure) =>
      for prop in closure.props {
        if prop.enumerable {
          entries.push(js_array_from([String(prop.key), prop.value]))
        }
      }
    Object(map) =>
      for prop in map.props {
        if prop.enumerable {
          entries.push(js_array_from([String(prop.key), prop.value]))
        }
      }
    Array(arr) => {
      for i in 0..<arr.items.length() {
        if arr.present[i] {
          entries.push(js_array_from([String(i.to_string()), arr.items[i]]))
        }
      }
      for prop in arr.props {
        if prop.enumerable {
          entries.push(js_array_from([String(prop.key), prop.value]))
        }
      }
    }
    _ => ()
  }
  js_array_from(entries)
}

///|
fn JSInterpreter::object_assign(
  self : JSInterpreter,
  args : Array[JSValue],
) -> JSValue {
  let target = if args.length() > 0 { args[0] } else { Undefined }
  match target {
    Undefined | Null =>
      return self.set_error_kind(
        "TypeError", "Cannot convert undefined or null to object",
      )
    _ => ()
  }
  for i in 1..<args.length() {
    let source = args[i]
    match source {
      Undefined | Null => continue
      Object(map) =>
        for prop in map.props {
          if prop.enumerable {
            let _ = js_set_prop(target, prop.key, prop.value)

          }
        }
      Array(arr) => {
        for j in 0..<arr.items.length() {
          if arr.present[j] {
            let _ = js_set_prop(target, j.to_string(), arr.items[j])

          }
        }
        for prop in arr.props {
          if prop.enumerable {
            let _ = js_set_prop(target, prop.key, prop.value)

          }
        }
      }
      Function(closure) =>
        for prop in closure.props {
          if prop.enumerable {
            let _ = js_set_prop(target, prop.key, prop.value)

          }
        }
      _ => ()
    }
  }
  target
}

///|
fn JSInterpreter::object_from_entries(
  self : JSInterpreter,
  args : Array[JSValue],
) -> JSValue {
  let iterable = if args.length() > 0 { args[0] } else { Undefined }
  let obj = js_new_object_with_proto(Some(self.object_proto))
  match iterable {
    Array(arr) =>
      for i in 0..<arr.items.length() {
        if arr.present[i] {
          match arr.items[i] {
            Array(entry) =>
              if entry.items.length() >= 2 &&
                entry.present[0] &&
                entry.present[1] {
                let key = entry.items[0].to_js_string()
                let value = entry.items[1]
                let _ = js_set_prop(obj, key, value)

              }
            _ => ()
          }
        }
      }
    _ => ()
  }
  obj
}
