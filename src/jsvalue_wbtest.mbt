// JSValue のテスト

///|
test "jsvalue: type checks" {
  let undef = JSValue::Undefined
  let null = JSValue::Null
  let bool = JSValue::Bool(true)
  let num = JSValue::Number(42.0)
  let str = JSValue::String("hello")
  assert_eq(undef.is_undefined(), true)
  assert_eq(null.is_null(), true)
  assert_eq(bool.is_bool(), true)
  assert_eq(num.is_number(), true)
  assert_eq(str.is_string(), true)
  assert_eq(undef.is_nullish(), true)
  assert_eq(null.is_nullish(), true)
  assert_eq(bool.is_nullish(), false)
}

///|
test "jsvalue: to_boolean" {
  // falsy values
  assert_eq(JSValue::Undefined.to_boolean(), false)
  assert_eq(JSValue::Null.to_boolean(), false)
  assert_eq(JSValue::Bool(false).to_boolean(), false)
  assert_eq(JSValue::Number(0.0).to_boolean(), false)
  assert_eq(JSValue::String("").to_boolean(), false)

  // truthy values
  assert_eq(JSValue::Bool(true).to_boolean(), true)
  assert_eq(JSValue::Number(1.0).to_boolean(), true)
  assert_eq(JSValue::Number(-1.0).to_boolean(), true)
  assert_eq(JSValue::String("hello").to_boolean(), true)
  assert_eq(JSValue::Object({ props: [], prototype: None }).to_boolean(), true)
  assert_eq(JSValue::Array([]).to_boolean(), true)
}

///|
test "jsvalue: to_number" {
  assert_eq(JSValue::Null.to_number(), 0.0)
  assert_eq(JSValue::Bool(true).to_number(), 1.0)
  assert_eq(JSValue::Bool(false).to_number(), 0.0)
  assert_eq(JSValue::Number(42.0).to_number(), 42.0)
  assert_eq(JSValue::String("").to_number(), 0.0)
  assert_eq(JSValue::String("123").to_number(), 123.0)
  assert_eq(JSValue::String("3.14").to_number(), 3.14)

  // NaN cases
  assert_true(JSValue::Undefined.to_number().is_nan())
  assert_true(JSValue::String("hello").to_number().is_nan())
}

///|
test "jsvalue: to_js_string" {
  assert_eq(JSValue::Undefined.to_js_string(), "undefined")
  assert_eq(JSValue::Null.to_js_string(), "null")
  assert_eq(JSValue::Bool(true).to_js_string(), "true")
  assert_eq(JSValue::Bool(false).to_js_string(), "false")
  assert_eq(JSValue::String("hello").to_js_string(), "hello")
}

///|
test "jsvalue: js_add numbers" {
  let a = JSValue::Number(10.0)
  let b = JSValue::Number(5.0)
  match js_add(a, b) {
    Number(n) => assert_eq(n, 15.0)
    _ => fail("expected Number")
  }
}

///|
test "jsvalue: js_add strings" {
  let a = JSValue::String("hello")
  let b = JSValue::String(" world")
  match js_add(a, b) {
    String(s) => assert_eq(s, "hello world")
    _ => fail("expected String")
  }
}

///|
test "jsvalue: js_add mixed" {
  let a = JSValue::String("value: ")
  let b = JSValue::Number(42.0)
  match js_add(a, b) {
    String(s) => assert_eq(s, "value: 42")
    _ => fail("expected String")
  }
}

///|
test "jsvalue: arithmetic" {
  let a = JSValue::Number(10.0)
  let b = JSValue::Number(3.0)
  match js_sub(a, b) {
    Number(n) => assert_eq(n, 7.0)
    _ => fail("expected Number")
  }
  match js_mul(a, b) {
    Number(n) => assert_eq(n, 30.0)
    _ => fail("expected Number")
  }
}

///|
test "jsvalue: comparison" {
  let a = JSValue::Number(5.0)
  let b = JSValue::Number(10.0)
  match js_lt(a, b) {
    Bool(v) => assert_eq(v, true)
    _ => fail("expected Bool")
  }
  match js_gt(a, b) {
    Bool(v) => assert_eq(v, false)
    _ => fail("expected Bool")
  }
  match js_le(a, a) {
    Bool(v) => assert_eq(v, true)
    _ => fail("expected Bool")
  }
}

///|
test "jsvalue: strict equality" {
  // same type, same value
  match js_strict_eq(JSValue::Number(42.0), JSValue::Number(42.0)) {
    Bool(v) => assert_eq(v, true)
    _ => fail("expected Bool")
  }

  // same type, different value
  match js_strict_eq(JSValue::Number(42.0), JSValue::Number(43.0)) {
    Bool(v) => assert_eq(v, false)
    _ => fail("expected Bool")
  }

  // different types
  match js_strict_eq(JSValue::Number(42.0), JSValue::String("42")) {
    Bool(v) => assert_eq(v, false)
    _ => fail("expected Bool")
  }
}

///|
test "jsvalue: abstract equality" {
  // null == undefined
  match js_eq(JSValue::Null, JSValue::Undefined) {
    Bool(v) => assert_eq(v, true)
    _ => fail("expected Bool")
  }

  // number == string (with coercion)
  match js_eq(JSValue::Number(42.0), JSValue::String("42")) {
    Bool(v) => assert_eq(v, true)
    _ => fail("expected Bool")
  }
}

///|
test "jsvalue: typeof" {
  match js_typeof(JSValue::Undefined) {
    String(s) => assert_eq(s, "undefined")
    _ => fail("expected String")
  }
  match js_typeof(JSValue::Null) {
    String(s) => assert_eq(s, "object") // famous JS bug
    _ => fail("expected String")
  }
  match js_typeof(JSValue::Number(42.0)) {
    String(s) => assert_eq(s, "number")
    _ => fail("expected String")
  }
}

///|
test "jsvalue: object property" {
  let obj = js_new_object()

  // 初期状態はundefined
  match js_get_prop(obj, "foo") {
    Undefined => ()
    _ => fail("expected Undefined")
  }

  // プロパティを設定
  let _ = js_set_prop(obj, "foo", JSValue::Number(42.0))
  match js_get_prop(obj, "foo") {
    Number(n) => assert_eq(n, 42.0)
    _ => fail("expected Number")
  }

  // プロパティを更新
  let _ = js_set_prop(obj, "foo", JSValue::String("bar"))
  match js_get_prop(obj, "foo") {
    String(s) => assert_eq(s, "bar")
    _ => fail("expected String")
  }
}

///|
test "jsvalue: array operations" {
  let arr = js_new_array()

  // 空配列の長さ
  match js_array_length(arr) {
    Number(n) => assert_eq(n, 0.0)
    _ => fail("expected Number")
  }

  // push
  let _ = js_array_push(arr, JSValue::Number(10.0))
  let _ = js_array_push(arr, JSValue::Number(20.0))
  match js_array_length(arr) {
    Number(n) => assert_eq(n, 2.0)
    _ => fail("expected Number")
  }

  // インデックスアクセス
  match js_get_prop(arr, "0") {
    Number(n) => assert_eq(n, 10.0)
    _ => fail("expected Number")
  }
  match js_get_prop(arr, "1") {
    Number(n) => assert_eq(n, 20.0)
    _ => fail("expected Number")
  }

  // length property
  match js_get_prop(arr, "length") {
    Number(n) => assert_eq(n, 2.0)
    _ => fail("expected Number")
  }
}

///|
test "jsvalue: environment" {
  let env = js_new_env(None)

  // 変数定義
  env.define("x", JSValue::Number(10.0))
  env.define("y", JSValue::Number(20.0))

  // 取得
  match env.get("x") {
    Number(n) => assert_eq(n, 10.0)
    _ => fail("expected Number")
  }

  // 更新
  assert_true(env.set("x", JSValue::Number(100.0)))
  match env.get("x") {
    Number(n) => assert_eq(n, 100.0)
    _ => fail("expected Number")
  }

  // 存在しない変数
  match env.get("z") {
    Undefined => ()
    _ => fail("expected Undefined")
  }
}

///|
test "jsvalue: nested environment" {
  let outer = js_new_env(None)
  outer.define("x", JSValue::Number(10.0))
  let inner = js_new_env(Some(outer))
  inner.define("y", JSValue::Number(20.0))

  // innerからouterの変数にアクセス
  match inner.get("x") {
    Number(n) => assert_eq(n, 10.0)
    _ => fail("expected Number")
  }

  // innerの変数
  match inner.get("y") {
    Number(n) => assert_eq(n, 20.0)
    _ => fail("expected Number")
  }

  // innerからouterの変数を更新
  assert_true(inner.set("x", JSValue::Number(100.0)))
  match outer.get("x") {
    Number(n) => assert_eq(n, 100.0)
    _ => fail("expected Number")
  }
}
