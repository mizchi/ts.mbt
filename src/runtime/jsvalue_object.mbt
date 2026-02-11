// JS object/array structures and property operations.

///|
// / property
pub struct JSProp {
  key : String
  value : JSValue
  writable : Bool
  enumerable : Bool
  configurable : Bool
  get : JSValue?
  set : JSValue?
} derive(Show)

///|
// / objectproperty
pub struct JSPropMap {
  id : Int
  props : Array[JSProp]
  mut prototype : JSValue?
} derive(Show)

///|
// / array
pub struct JSArray {
  id : Int
  items : Array[JSValue]
  present : Array[Bool]
  props : Array[JSProp]
  mut length : Int
  mut prototype : JSValue?
} derive(Show)

///|
const MAX_DENSE_ARRAY_LENGTH : Int = 1000000

///|
priv struct ArrayProtoHolder {
  mut proto : JSValue?
}

///|
let array_proto_holder : ArrayProtoHolder = { proto: None }

///|
const WITH_BINDING_NAME : String = "__with_obj__"

///|
// / array prototype set
pub fn js_set_default_array_proto(proto : JSValue) -> Unit {
  array_proto_holder.proto = Some(proto)
}

///|
// / array prototype get
pub fn js_get_default_array_proto() -> JSValue? {
  array_proto_holder.proto
}

///|
// / ToNumber - JSconversion
pub fn JSValue::to_number(self : JSValue) -> Double {
  match self {
    Undefined => js_nan
    Null => 0.0
    Bool(true) => 1.0
    Bool(false) => 0.0
    Number(n) => n
    BigInt(n) => n.to_int64().to_double() // Note: May lose precision for large BigInts
    String(s) =>
      // simpleimplementation: string0,
      if s.length() == 0 {
        0.0
      } else {
        // TODO:
        @strconv.parse_double(s) catch {
          _ => js_nan
        }
      }
    Object(_) | Array(_) | Function(_) => {
      let prim = js_get_prop(self, "value")
      match prim {
        Undefined => js_nan
        _ => prim.to_number()
      }
    }
    BreakSignal(_) | ContinueSignal(_) | Empty => js_nan // internal
  }
}

///|
fn is_html_dda(value : JSValue) -> Bool {
  match value {
    Object(_) | Function(_) =>
      match js_get_prop(value, "__class") {
        String("IsHTMLDDA") => true
        _ => false
      }
    _ => false
  }
}

///|
// / objectcreate
pub fn js_new_object() -> JSValue {
  js_new_object_with_proto(None)
}

///|
// / objectcreate
pub fn js_new_object_with_proto(proto : JSValue?) -> JSValue {
  Object({ id: fresh_object_id(), props: [], prototype: proto })
}

///|
// / propertyobjectcreate
pub fn js_object_with_props(props : Array[JSProp], proto : JSValue?) -> JSValue {
  Object({ id: fresh_object_id(), props, prototype: proto })
}

///|
// / propertyget
pub fn js_get_prop(obj : JSValue, key : String) -> JSValue {
  match obj {
    Function(closure) => {
      if key == "__proto__" {
        match closure.object_proto {
          Some(proto) => return proto
          None => return Undefined
        }
      }
      for prop in closure.props {
        if prop.key == key {
          match prop.get {
            Some(getter) =>
              match getter {
                Function(getter_closure) =>
                  match getter_closure.body {
                    Native(name) =>
                      if name == "__export_get__" {
                        let name_val = js_get_prop(getter, "__export_name")
                        let module_val = js_get_prop(getter, "__export_module")
                        match (module_val, name_val) {
                          (Object(_) | Function(_) | Array(_), String(n)) =>
                            return js_get_prop(module_val, n)
                          _ => ()
                        }
                        match name_val {
                          String(n) => return getter_closure.env.get(n)
                          _ => ()
                        }
                      }
                    _ => ()
                  }
                _ => ()
              }
            None => ()
          }
          return prop.value
        }
      }
      match closure.object_proto {
        Some(proto) => js_get_prop(proto, key)
        None => Undefined
      }
    }
    Object(map) => {
      if key == "__proto__" {
        match map.prototype {
          Some(proto) => return proto
          None => return Undefined
        }
      }
      // Check if this is a TypedArray index access
      match get_typedarray_data(obj) {
        Some(data) => {
          let idx = @strconv.parse_int(key) catch { _ => -1 }
          if idx >= 0 {
            if idx < data.length && not(data.buffer.detached) {
              return typedarray_get_element_jsvalue(data, idx)
            }
            return Undefined
          }
        }
        None => ()
      }
      // propertylookup
      for prop in map.props {
        if prop.key == key {
          match prop.get {
            Some(getter) =>
              match getter {
                Function(getter_closure) =>
                  match getter_closure.body {
                    Native(name) =>
                      if name == "__export_get__" {
                        let name_val = js_get_prop(getter, "__export_name")
                        let module_val = js_get_prop(getter, "__export_module")
                        match (module_val, name_val) {
                          (Object(_) | Function(_) | Array(_), String(n)) =>
                            return js_get_prop(module_val, n)
                          _ => ()
                        }
                        match name_val {
                          String(n) => return getter_closure.env.get(n)
                          _ => ()
                        }
                      }
                    _ => ()
                  }
                _ => ()
              }
            None => ()
          }
          return prop.value
        }
      }
      match map.prototype {
        Some(proto) => js_get_prop(proto, key)
        None => Undefined
      }
    }
    Array(arr) =>
      if key == "length" {
        Number(arr.length.to_double())
      } else if key == "__proto__" {
        match arr.prototype {
          Some(proto) => proto
          None => Undefined
        }
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < arr.items.length() && arr.present[idx] {
          arr.items[idx]
        } else {
          for prop in arr.props {
            if prop.key == key {
              match prop.get {
                Some(getter) =>
                  match getter {
                    Function(getter_closure) =>
                      match getter_closure.body {
                        Native(name) =>
                          if name == "__export_get__" {
                            let name_val = js_get_prop(getter, "__export_name")
                            let module_val = js_get_prop(
                              getter, "__export_module",
                            )
                            match (module_val, name_val) {
                              (Object(_) | Function(_) | Array(_), String(n)) =>
                                return js_get_prop(module_val, n)
                              _ => ()
                            }
                            match name_val {
                              String(n) => return getter_closure.env.get(n)
                              _ => ()
                            }
                          }
                        _ => ()
                      }
                    _ => ()
                  }
                None => ()
              }
              return prop.value
            }
          }
          match arr.prototype {
            Some(proto) => js_get_prop(proto, key)
            None => Undefined
          }
        }
      }
    String(s) =>
      if key == "length" {
        Number(s.length().to_double())
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < s.length() {
          // TODO: charAt
          Undefined
        } else {
          Undefined
        }
      }
    _ => Undefined
  }
}

///|
// / propertyset
pub fn js_set_prop(obj : JSValue, key : String, value : JSValue) -> JSValue {
  match obj {
    Function(closure) => {
      if key == "__proto__" {
        // Check if object is non-extensible
        for prop in closure.props {
          if prop.key == "__non_extensible" {
            match prop.value {
              Bool(true) => return value // Silently fail for non-extensible objects
              _ => ()
            }
          }
        }
        closure.object_proto = match value {
          Object(_) | Array(_) | Function(_) => Some(value)
          Null | Undefined => None
          _ => closure.object_proto
        }
        return value
      }
      for i, prop in closure.props {
        if prop.key == key {
          if prop.get is Some(_) || prop.set is Some(_) {
            return value
          }
          if not(prop.writable) {
            return prop.value
          }
          closure.props[i] = {
            key,
            value,
            writable: prop.writable,
            enumerable: prop.enumerable,
            configurable: prop.configurable,
            get: prop.get,
            set: prop.set,
          }
          return value
        }
      }
      closure.props.push({
        key,
        value,
        writable: true,
        enumerable: true,
        configurable: true,
        get: None,
        set: None,
      })
      value
    }
    Object(map) => {
      if key == "__proto__" {
        // Check if object is non-extensible (preventExtensions was called)
        for prop in map.props {
          if prop.key == "__non_extensible" {
            match prop.value {
              Bool(true) => return value // Silently fail for non-extensible objects
              _ => ()
            }
          }
        }
        map.prototype = match value {
          Object(_) | Array(_) | Function(_) => Some(value)
          Null | Undefined => None
          _ => map.prototype
        }
        return value
      }
      // Check if this is a TypedArray index access
      match get_typedarray_data(obj) {
        Some(data) => {
          let idx = @strconv.parse_int(key) catch { _ => -1 }
          if idx >= 0 {
            if idx < data.length && not(data.buffer.detached) {
              typedarray_set_element_jsvalue(data, idx, value)
            }
            return value
          }
        }
        None => ()
      }
      // propertyupdate
      for i, prop in map.props {
        if prop.key == key {
          if prop.get is Some(_) || prop.set is Some(_) {
            return value
          }
          if not(prop.writable) {
            return prop.value
          }
          map.props[i] = {
            key,
            value,
            writable: prop.writable,
            enumerable: prop.enumerable,
            configurable: prop.configurable,
            get: prop.get,
            set: prop.set,
          }
          return value
        }
      }
      // propertyadd
      map.props.push({
        key,
        value,
        writable: true,
        enumerable: true,
        configurable: true,
        get: None,
        set: None,
      })
      value
    }
    Array(arr) => {
      if key == "__proto__" {
        // Check if array is non-extensible
        for prop in arr.props {
          if prop.key == "__non_extensible" {
            match prop.value {
              Bool(true) => return value // Silently fail for non-extensible objects
              _ => ()
            }
          }
        }
        arr.prototype = match value {
          Object(_) | Array(_) | Function(_) => Some(value)
          Null | Undefined => None
          _ => arr.prototype
        }
        return value
      }
      if key == "length" {
        let new_len = value.to_number().to_int()
        if new_len >= 0 {
          if new_len < arr.items.length() {
            while arr.items.length() > new_len {
              let _ = arr.items.pop()
              let _ = arr.present.pop()
            }
          } else if new_len <= MAX_DENSE_ARRAY_LENGTH {
            while arr.items.length() < new_len {
              arr.items.push(Undefined)
              arr.present.push(false)
            }
          }
          arr.length = new_len
        }
        return value
      }
      let idx = @strconv.parse_int(key) catch { _ => -1 }
      if idx >= 0 {
        if idx < MAX_DENSE_ARRAY_LENGTH {
          // array
          while arr.items.length() <= idx {
            arr.items.push(Undefined)
            arr.present.push(false)
          }
          arr.items[idx] = value
          arr.present[idx] = true
        } else {
          let mut replaced = false
          for i, prop in arr.props {
            if prop.key == key {
              if prop.get is Some(_) || prop.set is Some(_) {
                return value
              }
              if not(prop.writable) {
                return prop.value
              }
              arr.props[i] = {
                key,
                value,
                writable: prop.writable,
                enumerable: prop.enumerable,
                configurable: prop.configurable,
                get: prop.get,
                set: prop.set,
              }
              replaced = true
              break
            }
          }
          if not(replaced) {
            arr.props.push({
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
        let new_len = idx + 1
        if new_len > arr.length {
          arr.length = new_len
        }
      } else {
        for i, prop in arr.props {
          if prop.key == key {
            if prop.get is Some(_) || prop.set is Some(_) {
              return value
            }
            if not(prop.writable) {
              return prop.value
            }
            arr.props[i] = {
              key,
              value,
              writable: prop.writable,
              enumerable: prop.enumerable,
              configurable: prop.configurable,
              get: prop.get,
              set: prop.set,
            }
            return value
          }
        }
        arr.props.push({
          key,
          value,
          writable: true,
          enumerable: true,
          configurable: true,
          get: None,
          set: None,
        })
      }
      value
    }
    _ => value
  }
}

///|
// / propertydelete
pub fn js_delete_prop(obj : JSValue, key : String) -> Bool {
  match obj {
    Function(closure) => {
      let mut i = 0
      while i < closure.props.length() {
        if closure.props[i].key == key {
          if not(closure.props[i].configurable) {
            return false
          }
          let _ = closure.props.remove(i)
          return true
        }
        i += 1
      }
      true
    }
    Object(map) => {
      let mut i = 0
      while i < map.props.length() {
        if map.props[i].key == key {
          if not(map.props[i].configurable) {
            return false
          }
          let _ = map.props.remove(i)
          return true
        }
        i += 1
      }
      true
    }
    Array(arr) =>
      if key == "length" {
        false
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < arr.items.length() {
          arr.present[idx] = false
        } else {
          let mut i = 0
          while i < arr.props.length() {
            if arr.props[i].key == key {
              if not(arr.props[i].configurable) {
                return false
              }
              let _ = arr.props.remove(i)
              return true
            }
            i += 1
          }
        }
        true
      }
    _ => true
  }
}

///|
// / datapropertydefine
pub fn js_define_data_prop(
  obj : JSValue,
  key : String,
  value : JSValue,
  writable : Bool,
  enumerable : Bool,
  configurable : Bool,
) -> JSValue {
  match obj {
    Function(closure) => {
      for i, prop in closure.props {
        if prop.key == key {
          closure.props[i] = {
            key,
            value,
            writable,
            enumerable,
            configurable,
            get: None,
            set: None,
          }
          return value
        }
      }
      closure.props.push({
        key,
        value,
        writable,
        enumerable,
        configurable,
        get: None,
        set: None,
      })
      value
    }
    Object(map) => {
      for i, prop in map.props {
        if prop.key == key {
          map.props[i] = {
            key,
            value,
            writable,
            enumerable,
            configurable,
            get: None,
            set: None,
          }
          return value
        }
      }
      map.props.push({
        key,
        value,
        writable,
        enumerable,
        configurable,
        get: None,
        set: None,
      })
      value
    }
    Array(arr) => {
      if key == "length" {
        let new_len = value.to_number().to_int()
        if new_len >= 0 {
          if new_len < arr.items.length() {
            while arr.items.length() > new_len {
              let _ = arr.items.pop()
              let _ = arr.present.pop()
            }
          } else if new_len <= MAX_DENSE_ARRAY_LENGTH {
            while arr.items.length() < new_len {
              arr.items.push(Undefined)
              arr.present.push(false)
            }
          }
          arr.length = new_len
        }
        return value
      }
      let idx = @strconv.parse_int(key) catch { _ => -1 }
      if idx >= 0 {
        if idx < MAX_DENSE_ARRAY_LENGTH {
          while arr.items.length() <= idx {
            arr.items.push(Undefined)
            arr.present.push(false)
          }
          arr.items[idx] = value
          arr.present[idx] = true
        } else {
          let mut replaced = false
          for i, prop in arr.props {
            if prop.key == key {
              arr.props[i] = {
                key,
                value,
                writable,
                enumerable,
                configurable,
                get: None,
                set: None,
              }
              replaced = true
              break
            }
          }
          if not(replaced) {
            arr.props.push({
              key,
              value,
              writable,
              enumerable,
              configurable,
              get: None,
              set: None,
            })
          }
        }
        let new_len = idx + 1
        if new_len > arr.length {
          arr.length = new_len
        }
        return value
      }
      for i, prop in arr.props {
        if prop.key == key {
          arr.props[i] = {
            key,
            value,
            writable,
            enumerable,
            configurable,
            get: None,
            set: None,
          }
          return value
        }
      }
      arr.props.push({
        key,
        value,
        writable,
        enumerable,
        configurable,
        get: None,
        set: None,
      })
      value
    }
    _ => value
  }
}

///|
// / propertydefine
pub fn js_define_accessor_prop(
  obj : JSValue,
  key : String,
  get : JSValue?,
  set : JSValue?,
  enumerable : Bool,
  configurable : Bool,
) -> JSValue {
  match obj {
    Function(closure) => {
      for i, prop in closure.props {
        if prop.key == key {
          closure.props[i] = {
            key,
            value: Undefined,
            writable: false,
            enumerable,
            configurable,
            get,
            set,
          }
          return Undefined
        }
      }
      closure.props.push({
        key,
        value: Undefined,
        writable: false,
        enumerable,
        configurable,
        get,
        set,
      })
      Undefined
    }
    Object(map) => {
      for i, prop in map.props {
        if prop.key == key {
          map.props[i] = {
            key,
            value: Undefined,
            writable: false,
            enumerable,
            configurable,
            get,
            set,
          }
          return Undefined
        }
      }
      map.props.push({
        key,
        value: Undefined,
        writable: false,
        enumerable,
        configurable,
        get,
        set,
      })
      Undefined
    }
    Array(arr) => {
      if key == "length" {
        return Undefined
      }
      let idx = @strconv.parse_int(key) catch { _ => -1 }
      if idx >= 0 {
        let mut replaced = false
        for i, prop in arr.props {
          if prop.key == key {
            arr.props[i] = {
              key,
              value: Undefined,
              writable: false,
              enumerable,
              configurable,
              get,
              set,
            }
            replaced = true
            break
          }
        }
        if not(replaced) {
          arr.props.push({
            key,
            value: Undefined,
            writable: false,
            enumerable,
            configurable,
            get,
            set,
          })
        }
        let new_len = idx + 1
        if new_len > arr.length {
          arr.length = new_len
        }
        return Undefined
      }
      for i, prop in arr.props {
        if prop.key == key {
          arr.props[i] = {
            key,
            value: Undefined,
            writable: false,
            enumerable,
            configurable,
            get,
            set,
          }
          return Undefined
        }
      }
      arr.props.push({
        key,
        value: Undefined,
        writable: false,
        enumerable,
        configurable,
        get,
        set,
      })
      Undefined
    }
    _ => Undefined
  }
}

// === array ===

///|
// / arraycreate
pub fn js_new_array() -> JSValue {
  Array({
    id: fresh_array_id(),
    items: [],
    present: [],
    props: [],
    length: 0,
    prototype: array_proto_holder.proto,
  })
}

///|
// / arrayliteralcreate
pub fn js_array_from(items : Array[JSValue]) -> JSValue {
  let present : Array[Bool] = []
  for _ in items {
    present.push(true)
  }
  Array({
    id: fresh_array_id(),
    items,
    present,
    props: [],
    length: items.length(),
    prototype: array_proto_holder.proto,
  })
}

///|
// / arrayelementadd (push)
pub fn js_array_push(arr : JSValue, value : JSValue) -> JSValue {
  match arr {
    Array(arr_map) => {
      arr_map.items.push(value)
      arr_map.present.push(true)
      let new_len = arr_map.items.length()
      if new_len > arr_map.length {
        arr_map.length = new_len
      }
      Number(arr_map.length.to_double())
    }
    _ => Undefined
  }
}

///|
// / arraylengthget
pub fn js_array_length(arr : JSValue) -> JSValue {
  match arr {
    Array(arr_map) => Number(arr_map.length.to_double())
    _ => Undefined
  }
}

// === ===

///|
// / variableget(prefer)
pub fn JSEnv::get(self : JSEnv, name : String) -> JSValue {
  // currentlookup(prefer)
  let len = self.bindings.length()
  let mut i = len - 1
  let mut with_target : JSValue? = None
  while i >= 0 {
    let binding = self.bindings[i]
    if binding.name == name {
      return binding.value
    }
    if binding.name == WITH_BINDING_NAME {
      with_target = Some(binding.value)
    }
    i -= 1
  }
  match with_target {
    Some(obj) => if js_has_prop(obj, name) { return js_get_prop(obj, name) }
    None => ()
  }
  // lookup
  match self.parent {
    Some(parent) => parent.get(name)
    None => Undefined
  }
}

///|
// / variableupdate
pub fn JSEnv::set(self : JSEnv, name : String, value : JSValue) -> Bool {
  // currentlookup(prefer)
  let len = self.bindings.length()
  let mut i = len - 1
  let mut with_target : JSValue? = None
  while i >= 0 {
    if self.bindings[i].name == name {
      if self.bindings[i].is_const {
        return false
      }
      self.bindings[i].value = value
      self.bindings[i].is_uninitialized = false
      return true
    }
    if self.bindings[i].name == WITH_BINDING_NAME {
      with_target = Some(self.bindings[i].value)
    }
    i -= 1
  }
  match with_target {
    Some(obj) =>
      if js_has_prop(obj, name) {
        let _ = js_set_prop(obj, name, value)
        return true
      }
    None => ()
  }
  // lookup
  match self.parent {
    Some(parent) => parent.set(name, value)
    None => false
  }
}
