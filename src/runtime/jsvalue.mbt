// JSValue - ボックス化されたJavaScript値の表現
// WasmGC struct ベースの動的型付けランタイム

///|
/// JSValueのタグ
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
/// JSTag を i32 に変換
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
/// i32 から JSTag に変換
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
/// プロパティエントリ
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
/// オブジェクトのプロパティマップ
pub struct JSPropMap {
  id : Int
  props : Array[JSProp]
  prototype : JSValue? // プロトタイプチェーン
} derive(Show)

///|
/// 配列
pub struct JSArray {
  id : Int
  items : Array[JSValue]
  props : Array[JSProp]
  mut length : Int
} derive(Show)

const MAX_DENSE_ARRAY_LENGTH : Int = 1000000

///|
/// クロージャ環境
pub struct JSEnv {
  parent : JSEnv?
  bindings : Array[(String, JSValue)]
} derive(Show)

///|
/// JSValue - すべてのJS値を表現
pub enum JSValue {
  Undefined
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Object(JSPropMap)
  Array(JSArray)
  Function(JSClosure)
  // 内部制御フロー信号
  BreakSignal
  ContinueSignal
} derive(Show)

///|
/// クロージャ
pub struct JSClosure {
  id : Int
  params : Array[String]
  body : JSFuncBody
  env : JSEnv
  is_arrow : Bool
  is_strict : Bool
  props : Array[JSProp]
  object_proto : JSValue?
} derive(Show)

///|
/// 関数本体（ASTまたはコンパイル済みコード）
pub enum JSFuncBody {
  Ast(@parser.TsFunc) // 解釈実行用
  Native(String) // ネイティブ関数名
  Bound(JSValue, JSValue, Array[JSValue]) // target, thisArg, bound args
  Compiled(Int) // コンパイル済み関数インデックス
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

// === 型判定 ===

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
    BreakSignal | ContinueSignal => JSTag::Undefined // 内部信号
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

// === 型変換 (ToBoolean, ToNumber, ToString) ===

///|
/// ToBoolean - JSの真偽値変換
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
    BreakSignal | ContinueSignal => false // 内部信号
  }
}

///|
/// NaN定数
let js_nan : Double = 0.0 / 0.0

///|
/// ToNumber - JSの数値変換
pub fn JSValue::to_number(self : JSValue) -> Double {
  match self {
    Undefined => js_nan
    Null => 0.0
    Bool(true) => 1.0
    Bool(false) => 0.0
    Number(n) => n
    String(s) =>
      // 簡易実装：空文字列は0、それ以外はパース試行
      if s.length() == 0 {
        0.0
      } else {
        // TODO: 適切な数値パース
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
    BreakSignal | ContinueSignal => js_nan // 内部信号
  }
}

///|
/// ToString - JSの文字列変換
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
    BreakSignal | ContinueSignal => "" // 内部信号
  }
}

// === 演算子 ===

///|
/// 加算 (+) - 数値加算または文字列連結
pub fn js_add(left : JSValue, right : JSValue) -> JSValue {
  // どちらかが文字列なら文字列連結
  match (left, right) {
    (String(a), String(b)) => String(a + b)
    (String(a), b) => String(a + b.to_js_string())
    (a, String(b)) => String(a.to_js_string() + b)
    _ => Number(left.to_number() + right.to_number())
  }
}

///|
/// 減算 (-)
pub fn js_sub(left : JSValue, right : JSValue) -> JSValue {
  Number(left.to_number() - right.to_number())
}

///|
/// 乗算 (*)
pub fn js_mul(left : JSValue, right : JSValue) -> JSValue {
  Number(left.to_number() * right.to_number())
}

///|
/// 除算 (/)
pub fn js_div(left : JSValue, right : JSValue) -> JSValue {
  Number(left.to_number() / right.to_number())
}

///|
/// 剰余 (%)
pub fn js_mod(left : JSValue, right : JSValue) -> JSValue {
  let a = left.to_number()
  let b = right.to_number()
  // JSの剰余演算はfmod相当
  Number(a - (a / b).floor() * b)
}

///|
/// 単項マイナス
pub fn js_neg(val : JSValue) -> JSValue {
  Number(-val.to_number())
}

///|
/// 単項プラス（数値変換）
pub fn js_pos(val : JSValue) -> JSValue {
  Number(val.to_number())
}

///|
/// 論理NOT
pub fn js_not(val : JSValue) -> JSValue {
  Bool(not(val.to_boolean()))
}

///|
/// typeof演算子
pub fn js_typeof(val : JSValue) -> JSValue {
  String(
    match val {
      Undefined => "undefined"
      Null => "object" // JSの有名なバグ
      Bool(_) => "boolean"
      Number(_) => "number"
      String(_) => "string"
      Object(_) => "object"
      Array(_) => "object"
    Function(_) => "function"
    BreakSignal | ContinueSignal => "undefined" // 内部信号
  },
  )
}

// === 比較演算子 ===

///|
/// 厳密等価 (===)
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
/// 厳密不等価 (!==)
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
/// 抽象等価 (==) - 型変換あり
pub fn js_eq(left : JSValue, right : JSValue) -> JSValue {
  Bool(
    match (left, right) {
      // 同じ型
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
      // 型が違う場合は数値に変換して比較
      (Number(_), _) | (_, Number(_)) => left.to_number() == right.to_number()
      (Bool(_), _) | (_, Bool(_)) => left.to_number() == right.to_number()
      (String(_), _) | (_, String(_)) => left.to_number() == right.to_number()
      _ => false
    },
  )
}

///|
/// 抽象不等価 (!=)
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
/// 小なり (<)
pub fn js_lt(left : JSValue, right : JSValue) -> JSValue {
  Bool(left.to_number() < right.to_number())
}

///|
/// 小なりイコール (<=)
pub fn js_le(left : JSValue, right : JSValue) -> JSValue {
  Bool(left.to_number() <= right.to_number())
}

///|
/// 大なり (>)
pub fn js_gt(left : JSValue, right : JSValue) -> JSValue {
  Bool(left.to_number() > right.to_number())
}

///|
/// 大なりイコール (>=)
pub fn js_ge(left : JSValue, right : JSValue) -> JSValue {
  Bool(left.to_number() >= right.to_number())
}

// === オブジェクト操作 ===

///|
/// 空オブジェクトを作成
pub fn js_new_object() -> JSValue {
  js_new_object_with_proto(None)
}

///|
/// プロトタイプ付きオブジェクトを作成
pub fn js_new_object_with_proto(proto : JSValue?) -> JSValue {
  Object({ id: fresh_object_id(), props: [], prototype: proto })
}

///|
/// プロパティ付きオブジェクトを作成
pub fn js_object_with_props(props : Array[JSProp], proto : JSValue?) -> JSValue {
  Object({ id: fresh_object_id(), props, prototype: proto })
}

///|
/// プロパティを取得
pub fn js_get_prop(obj : JSValue, key : String) -> JSValue {
  match obj {
    Function(closure) => {
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
      // 自身のプロパティを検索
      for prop in map.props {
        if prop.key == key {
          return prop.value
        }
      }
      // プロトタイプチェーンを辿る
      match map.prototype {
        Some(proto) => js_get_prop(proto, key)
        None => Undefined
      }
    }
    Array(arr) =>
      if key == "length" {
        Number(arr.length.to_double())
      } else {
        // インデックスアクセス
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < arr.items.length() {
          arr.items[idx]
        } else {
          for prop in arr.props {
            if prop.key == key {
              return prop.value
            }
          }
          Undefined
        }
      }
    String(s) =>
      if key == "length" {
        Number(s.length().to_double())
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < s.length() {
          // TODO: charAt相当
          Undefined
        } else {
          Undefined
        }
      }
    _ => Undefined
  }
}

///|
/// プロパティの存在確認
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
/// プロパティを設定
pub fn js_set_prop(obj : JSValue, key : String, value : JSValue) -> JSValue {
  match obj {
    Function(closure) => {
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
      // 既存プロパティを更新
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
      // 新規プロパティを追加
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
          // 配列を拡張
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
/// プロパティを削除
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
/// データプロパティを定義
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
/// アクセサプロパティを定義
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

// === 配列操作 ===

///|
/// 空配列を作成
pub fn js_new_array() -> JSValue {
  Array({ id: fresh_array_id(), items: [], props: [], length: 0 })
}

///|
/// 配列リテラルから作成
pub fn js_array_from(items : Array[JSValue]) -> JSValue {
  Array({ id: fresh_array_id(), items, props: [], length: items.length() })
}

///|
/// 配列に要素を追加 (push)
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
/// 配列の長さを取得
pub fn js_array_length(arr : JSValue) -> JSValue {
  match arr {
    Array(arr_map) => Number(arr_map.length.to_double())
    _ => Undefined
  }
}

// === 環境操作 ===

///|
/// 新しい環境を作成
pub fn js_new_env(parent : JSEnv?) -> JSEnv {
  { parent, bindings: [] }
}

///|
/// 環境に変数を定義
pub fn JSEnv::define(self : JSEnv, name : String, value : JSValue) -> Unit {
  self.bindings.push((name, value))
}

///|
/// 環境から変数を取得（最新のバインディングを優先）
pub fn JSEnv::get(self : JSEnv, name : String) -> JSValue {
  // 現在の環境を後ろから検索（最新のバインディングを優先）
  let len = self.bindings.length()
  let mut i = len - 1
  while i >= 0 {
    let (n, v) = self.bindings[i]
    if n == name {
      return v
    }
    i -= 1
  }
  // 親環境を検索
  match self.parent {
    Some(parent) => parent.get(name)
    None => Undefined
  }
}

///|
/// 環境に変数があるか確認
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
/// 環境の変数を更新
pub fn JSEnv::set(self : JSEnv, name : String, value : JSValue) -> Bool {
  // 現在の環境を検索（最新のバインディングを優先）
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
  // 親環境を検索
  match self.parent {
    Some(parent) => parent.set(name, value)
    None => false
  }
}
