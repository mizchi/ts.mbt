// JS value tags, conversions, and operators.
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
  BreakSignal(String?)
  ContinueSignal(String?)
  Empty // ECMAScript empty completion value (distinct from undefined)
} derive(Show)

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
    BreakSignal(_) | ContinueSignal(_) | Empty => JSTag::Undefined // internal
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
    Object(map) => {
      let mut is_bigint = false
      let mut bigint_value = ""
      for prop in map.props {
        if prop.key == "__class" {
          match prop.value {
            String("IsHTMLDDA") => return false
            String("BigInt") => is_bigint = true
            _ => ()
          }
        }
        if prop.key == "value" {
          match prop.value {
            String(s) => bigint_value = s
            _ => ()
          }
        }
      }
      if is_bigint {
        return bigint_value != "0"
      }
      true
    }
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
    Function(closure) => {
      for prop in closure.props {
        if prop.key == "__class" {
          match prop.value {
            String("IsHTMLDDA") => return false
            _ => ()
          }
        }
      }
      true
    }
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
    Object(map) => {
      let mut class_name : String? = None
      let mut bigint_value : String? = None
      for prop in map.props {
        if prop.key == "__class" {
          match prop.value {
            String(name) => class_name = Some(name)
            _ => ()
          }
        } else if prop.key == "value" {
          match prop.value {
            String(val) => bigint_value = Some(val)
            _ => ()
          }
        }
      }
      match class_name {
        Some("IsHTMLDDA") => false
        Some("BigInt") =>
          match bigint_value {
            Some("0") => false
            _ => true
          }
        _ => true
      }
    }
    Array(_) => true
    Function(closure) => {
      for prop in closure.props {
        if prop.key == "__class" {
          match prop.value {
            String("IsHTMLDDA") => return false
            _ => ()
          }
        }
      }
      true
    }
    BreakSignal(_) | ContinueSignal(_) | Empty => false // internal
  }
}

///|
// / NaN
let js_nan : Double = 0.0 / 0.0

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
    Object(_) =>
      // Check for special object types
      match js_get_prop(self, "__class") {
        String("BigInt") =>
          match js_get_prop(self, "value") {
            String(s) => s + "n"
            _ => "[object Object]"
          }
        _ =>
          match js_get_prop(self, "__gen_id") {
            Number(_) => "[object Generator]"
            _ => "[object Object]"
          }
      }
    Array(arr) => {
      let parts : Array[String] = []
      for item in arr.items {
        parts.push(item.to_js_string())
      }
      parts.join(",")
    }
    Function(closure) => {
      // Get the name from the "name" property if available
      let name_prop = js_get_prop(self, "name")
      let name = match name_prop {
        String(s) => s
        _ => ""
      }
      match closure.body {
        Native(_) => "function \{name}() { [native code] }"
        Bound(_, _, _) => "function \{name}() { [native code] }"
        Ast(func) => {
          let params_arr : Array[String] = []
          for p in func.params {
            match p.binding {
              Some(@ast.TsBinding::Ident(id)) => params_arr.push(id)
              _ => params_arr.push("_")
            }
          }
          let params_str = params_arr.join(", ")
          if closure.is_arrow {
            if params_arr.length() == 1 {
              "\{params_str} => {}"
            } else {
              "(\{params_str}) => {}"
            }
          } else if closure.is_generator {
            "function* \{name}(\{params_str}) {}"
          } else if name == "<anon>" || name == "" {
            "function (\{params_str}) {}"
          } else {
            "function \{name}(\{params_str}) {}"
          }
        }
      }
    }
    BreakSignal(_) | ContinueSignal(_) | Empty => "" // internal
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
      BreakSignal(_) | ContinueSignal(_) | Empty => "undefined" // internal
    },
  )
}

// === comparisonoperator ===

///|
// Helper to check if a JSValue is a BigInt and get its value string
fn get_bigint_value(val : JSValue) -> String? {
  match val {
    Object(_) => {
      match js_get_prop(val, "__class") {
        String("BigInt") =>
          match js_get_prop(val, "value") {
            String(s) => Some(s)
            _ => None
          }
        _ => None
      }
    }
    _ => None
  }
}

///|
// / (===)
pub fn js_strict_eq(left : JSValue, right : JSValue) -> JSValue {
  // Special case for BigInt comparison
  match (get_bigint_value(left), get_bigint_value(right)) {
    (Some(a), Some(b)) => return Bool(a == b)
    (Some(_), None) | (None, Some(_)) => return Bool(false) // BigInt !== non-BigInt
    _ => ()
  }
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
      (a, Undefined) | (a, Null) if is_html_dda(a) => true
      (Undefined, b) | (Null, b) if is_html_dda(b) => true
      // type
      (Undefined, Undefined) => true
      (Null, Null) => true
      (Undefined, Null) | (Null, Undefined) => true
      (Bool(a), Bool(b)) => a == b
      (Number(a), Number(b)) => a == b
      (String(a), String(b)) => a == b
      (Object(_), Object(_))
      | (Array(_), Array(_))
      | (Function(_), Function(_)) =>
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
// / stringcreate
pub fn js_string(value : String) -> JSValue {
  String(value)
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
