// JSValue - JavaScript
// WasmGC struct typeruntime

///|
// / JSValue
pub enum JSTag {
  Undefined // 0
  Null // 1
  Bool // 2
  Number // 3
  String // 4
  Object // 5
  Array // 6
  Function // 7
} derive(Show, Eq)

///|
// / JSTag i32 conversion
pub fn JSTag::to_i32(self : JSTag) -> Int {
  match self {
    Undefined => 0
    Null => 1
    Bool => 2
    Number => 3
    String => 4
    Object => 5
    Array => 6
    Function => 7
  }
}

///|
// / i32 JSTag conversion
pub fn JSTag::from_i32(n : Int) -> JSTag {
  match n {
    0 => Undefined
    1 => Null
    2 => Bool
    3 => Number
    4 => String
    5 => Object
    6 => Array
    7 => Function
    _ => Undefined
  }
}

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
  props : Array[JSProp]
  mut length : Int
  mut prototype : JSValue?
} derive(Show)

const MAX_DENSE_ARRAY_LENGTH : Int = 1000000

priv struct ArrayProtoHolder {
  mut proto : JSValue?
}

let array_proto_holder : ArrayProtoHolder = { proto: None }

///|
// / array prototype set
pub fn js_set_default_array_proto(proto : JSValue) -> Unit {
  array_proto_holder.proto = Some(proto)
}

///|
// /
pub struct JSEnv {
  parent : JSEnv?
  bindings : Array[(String, JSValue)]
} derive(Show)

///|
// / JSValue - JS
pub enum JSValue {
  Undefined
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Object(JSPropMap)
  Array(JSArray)
  Function(JSClosure)
  // internal
  BreakSignal
  ContinueSignal
} derive(Show)

///|
// /
pub struct JSClosure {
  id : Int
  params : Array[String]
  body : JSFuncBody
  env : JSEnv
  is_arrow : Bool
  is_strict : Bool
  is_generator : Bool
  props : Array[JSProp]
  mut object_proto : JSValue?
} derive(Show)

///|
// / function(AST)
pub enum JSFuncBody {
  Ast(@parser.TsFunc) // run
  Native(String) // function
  Bound(JSValue, JSValue, Array[JSValue]) // target, thisArg, bound args
} derive(Show)

// === ID generator (object/function/array identity) ===

priv struct IdGen {
  mut object_id : Int
  mut function_id : Int
  mut array_id : Int
}

let id_gen : IdGen = { object_id: 1, function_id: 1, array_id: 1 }

fn fresh_object_id() -> Int {
  let id = id_gen.object_id
  id_gen.object_id = id + 1
  id
}

fn fresh_function_id() -> Int {
  let id = id_gen.function_id
  id_gen.function_id = id + 1
  id
}

fn fresh_array_id() -> Int {
  let id = id_gen.array_id
  id_gen.array_id = id + 1
  id
}

// === typecheck ===

///|
pub fn JSValue::tag(self : JSValue) -> JSTag {
  match self {
    Undefined => JSTag::Undefined
    Null => JSTag::Null
    Bool(_) => JSTag::Bool
    Number(_) => JSTag::Number
    String(_) => JSTag::String
    Object(_) => JSTag::Object
    Array(_) => JSTag::Array
    Function(_) => JSTag::Function
    BreakSignal | ContinueSignal => JSTag::Undefined // internal
  }
}

///|
pub fn JSValue::is_undefined(self : JSValue) -> Bool {
  match self {
    Undefined => true
    _ => false
  }
}

///|
pub fn JSValue::is_null(self : JSValue) -> Bool {
  match self {
    Null => true
    _ => false
  }
}

///|
pub fn JSValue::is_nullish(self : JSValue) -> Bool {
  match self {
    Undefined | Null => true
    _ => false
  }
}

///|
pub fn JSValue::is_bool(self : JSValue) -> Bool {
  match self {
    Bool(_) => true
    _ => false
  }
}

///|
pub fn JSValue::is_number(self : JSValue) -> Bool {
  match self {
    Number(_) => true
    _ => false
  }
}

///|
pub fn JSValue::is_string(self : JSValue) -> Bool {
  match self {
    String(_) => true
    _ => false
  }
}

///|
pub fn JSValue::is_object(self : JSValue) -> Bool {
  match self {
    Object(_) => true
    _ => false
  }
}

///|
pub fn JSValue::is_array(self : JSValue) -> Bool {
  match self {
    Array(_) => true
    _ => false
  }
}

///|
pub fn JSValue::is_function(self : JSValue) -> Bool {
  match self {
    Function(_) => true
    _ => false
  }
}

// === typeconversion (ToBoolean, ToNumber, ToString) ===

///|
// / ToBoolean - JSconversion
pub fn JSValue::to_boolean(self : JSValue) -> Bool {
  match self {
    Undefined => false
    Null => false
    Bool(b) => b
    Number(n) => n != 0.0 && not(n.is_nan())
    String(s) => s.length() > 0
    Object(_) => true
    Array(_) => true
    Function(_) => true
    BreakSignal | ContinueSignal => false // internal
  }
}

///|
// / NaN
let js_nan : Double = 0.0 / 0.0

///|
// / ToNumber - JSconversion
pub fn JSValue::to_number(self : JSValue) -> Double {
  match self {
    Undefined => js_nan
    Null => 0.0
    Bool(true) => 1.0
    Bool(false) => 0.0
    Number(n) => n
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
    BreakSignal | ContinueSignal => js_nan // internal
  }
}

///|
// / ToString - JSstringconversion
pub fn JSValue::to_js_string(self : JSValue) -> String {
  match self {
    Undefined => "undefined"
    Null => "null"
    Bool(true) => "true"
    Bool(false) => "false"
    Number(n) => n.to_string()
    String(s) => s
    Object(_) => "[object Object]"
    Array(arr) => {
      let parts : Array[String] = []
      for item in arr.items {
        parts.push(item.to_js_string())
      }
      parts.join(",")
    }
    Function(_) => "[function]"
    BreakSignal | ContinueSignal => "" // internal
  }
}

// === operator ===

///|
// / (+) - string
pub fn js_add(left : JSValue, right : JSValue) -> JSValue {
  // stringstring
  match (left, right) {
    (String(a), String(b)) => String(a + b)
    (String(a), b) => String(a + b.to_js_string())
    (a, String(b)) => String(a.to_js_string() + b)
    _ => Number(left.to_number() + right.to_number())
  }
}

///|
// / (-)
pub fn js_sub(left : JSValue, right : JSValue) -> JSValue {
  Number(left.to_number() - right.to_number())
}

///|
// / (*)
pub fn js_mul(left : JSValue, right : JSValue) -> JSValue {
  Number(left.to_number() * right.to_number())
}

///|
// / (/)
pub fn js_div(left : JSValue, right : JSValue) -> JSValue {
  Number(left.to_number() / right.to_number())
}

///|
// / (%)
pub fn js_mod(left : JSValue, right : JSValue) -> JSValue {
  let a = left.to_number()
  let b = right.to_number()
  // JSfmod
  Number(a - (a / b).floor() * b)
}

///|
// / unary
pub fn js_neg(val : JSValue) -> JSValue {
  Number(-val.to_number())
}

///|
// / unary(conversion)
pub fn js_pos(val : JSValue) -> JSValue {
  Number(val.to_number())
}

///|
// / NOT
pub fn js_not(val : JSValue) -> JSValue {
  Bool(not(val.to_boolean()))
}

///|
// / typeofoperator
pub fn js_typeof(val : JSValue) -> JSValue {
  String(
    match val {
      Undefined => "undefined"
      Null => "object" // JS
      Bool(_) => "boolean"
      Number(_) => "number"
      String(_) => "string"
      Object(_) => "object"
      Array(_) => "object"
    Function(_) => "function"
    BreakSignal | ContinueSignal => "undefined" // internal
  },
  )
}

// === comparisonoperator ===

///|
// / (===)
pub fn js_strict_eq(left : JSValue, right : JSValue) -> JSValue {
  Bool(
    match (left, right) {
      (Undefined, Undefined) => true
      (Null, Null) => true
      (Bool(a), Bool(b)) => a == b
      (Number(a), Number(b)) => a == b
      (String(a), String(b)) => a == b
      (Object(a), Object(b)) => a.id == b.id
      (Array(a), Array(b)) => a.id == b.id
      (Function(a), Function(b)) => a.id == b.id
      _ => false
    },
  )
}

///|
// / (!==)
pub fn js_strict_ne(left : JSValue, right : JSValue) -> JSValue {
  Bool(
    not(
      match js_strict_eq(left, right) {
        Bool(b) => b
        _ => false
      },
    ),
  )
}

///|
// / (==) - typeconversion
pub fn js_eq(left : JSValue, right : JSValue) -> JSValue {
  Bool(
    match (left, right) {
      // type
      (Undefined, Undefined) => true
      (Null, Null) => true
      (Undefined, Null) | (Null, Undefined) => true
      (Bool(a), Bool(b)) => a == b
      (Number(a), Number(b)) => a == b
      (String(a), String(b)) => a == b
      (Object(_), Object(_)) | (Array(_), Array(_)) | (Function(_), Function(_)) =>
        match js_strict_eq(left, right) {
          Bool(b) => b
          _ => false
        }
      // typeconversioncomparison
      (Number(_), _) | (_, Number(_)) => left.to_number() == right.to_number()
      (Bool(_), _) | (_, Bool(_)) => left.to_number() == right.to_number()
      (String(_), _) | (_, String(_)) => left.to_number() == right.to_number()
      _ => false
    },
  )
}

///|
// / (!=)
pub fn js_ne(left : JSValue, right : JSValue) -> JSValue {
  Bool(
    not(
      match js_eq(left, right) {
        Bool(b) => b
        _ => false
      },
    ),
  )
}

///|
// / (<)
pub fn js_lt(left : JSValue, right : JSValue) -> JSValue {
  Bool(left.to_number() < right.to_number())
}

///|
// / (<=)
pub fn js_le(left : JSValue, right : JSValue) -> JSValue {
  Bool(left.to_number() <= right.to_number())
}

///|
// / (>)
pub fn js_gt(left : JSValue, right : JSValue) -> JSValue {
  Bool(left.to_number() > right.to_number())
}

///|
// / (>=)
pub fn js_ge(left : JSValue, right : JSValue) -> JSValue {
  Bool(left.to_number() >= right.to_number())
}

// === object ===

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
      // propertylookup
      for prop in map.props {
        if prop.key == key {
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
        if idx >= 0 && idx < arr.items.length() {
          arr.items[idx]
        } else {
          for prop in arr.props {
            if prop.key == key {
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
// / propertyexistencecheck
pub fn js_has_prop(obj : JSValue, key : String) -> Bool {
  match obj {
    Function(closure) => {
      for prop in closure.props {
        if prop.key == key {
          return true
        }
      }
      match closure.object_proto {
        Some(proto) => js_has_prop(proto, key)
        None => false
      }
    }
    Object(map) => {
      for prop in map.props {
        if prop.key == key {
          return true
        }
      }
      match map.prototype {
        Some(proto) => js_has_prop(proto, key)
        None => false
      }
    }
    Array(arr) =>
      if key == "length" {
        true
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < arr.items.length() {
          true
        } else {
          let mut found = false
          for prop in arr.props {
            if prop.key == key {
              found = true
              break
            }
          }
          if found {
            true
          } else {
            match arr.prototype {
              Some(proto) => js_has_prop(proto, key)
              None => false
            }
          }
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
// / propertyset
pub fn js_set_prop(obj : JSValue, key : String, value : JSValue) -> JSValue {
  match obj {
    Function(closure) => {
      if key == "__proto__" {
        closure.object_proto =
          match value {
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
        map.prototype =
          match value {
            Object(_) | Array(_) | Function(_) => Some(value)
            Null | Undefined => None
            _ => map.prototype
          }
        return value
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
        arr.prototype =
          match value {
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
            }
          } else if new_len <= MAX_DENSE_ARRAY_LENGTH {
            while arr.items.length() < new_len {
              arr.items.push(Undefined)
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
          }
          arr.items[idx] = value
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
          arr.items[idx] = Undefined
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
            }
          } else if new_len <= MAX_DENSE_ARRAY_LENGTH {
            while arr.items.length() < new_len {
              arr.items.push(Undefined)
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
          }
          arr.items[idx] = value
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
        if idx < MAX_DENSE_ARRAY_LENGTH {
          while arr.items.length() <= idx {
            arr.items.push(Undefined)
          }
          arr.items[idx] = Undefined
        } else {
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
    props: [],
    length: 0,
    prototype: array_proto_holder.proto,
  })
}

///|
// / arrayliteralcreate
pub fn js_array_from(items : Array[JSValue]) -> JSValue {
  Array({
    id: fresh_array_id(),
    items,
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
// / create
pub fn js_new_env(parent : JSEnv?) -> JSEnv {
  { parent, bindings: [] }
}

///|
// / variabledefine
pub fn JSEnv::define_var(self : JSEnv, name : String, value : JSValue) -> Unit {
  self.bindings.push((name, value))
}

///|
// / variableget(prefer)
pub fn JSEnv::get(self : JSEnv, name : String) -> JSValue {
  // currentlookup(prefer)
  let len = self.bindings.length()
  let mut i = len - 1
  while i >= 0 {
    let (n, v) = self.bindings[i]
    if n == name {
      return v
    }
    i -= 1
  }
  // lookup
  match self.parent {
    Some(parent) => parent.get(name)
    None => Undefined
  }
}

///|
// / variablecheck
pub fn JSEnv::has(self : JSEnv, name : String) -> Bool {
  let len = self.bindings.length()
  let mut i = len - 1
  while i >= 0 {
    let (n, _) = self.bindings[i]
    if n == name {
      return true
    }
    i -= 1
  }
  match self.parent {
    Some(parent) => parent.has(name)
    None => false
  }
}

///|
// / variableupdate
pub fn JSEnv::set(self : JSEnv, name : String, value : JSValue) -> Bool {
  // currentlookup(prefer)
  let len = self.bindings.length()
  let mut i = len - 1
  while i >= 0 {
    let (n, _) = self.bindings[i]
    if n == name {
      self.bindings[i] = (name, value)
      return true
    }
    i -= 1
  }
  // lookup
  match self.parent {
    Some(parent) => parent.set(name, value)
    None => false
  }
}
