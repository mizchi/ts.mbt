// test262 harness implementation for MoonBit JS interpreter

///|
/// AssertResult テスト結果
pub enum AssertResult {
  Success
  Failure(String)
}

///|
/// 基本的な assert 関数
pub fn assert(must_be_true : Bool, message : String?) -> AssertResult {
  if must_be_true {
    Success
  } else {
    let msg = match message {
      Some(m) => m
      None => "Expected true but got false"
    }
    Failure(msg)
  }
}

///|
/// SameValue アルゴリズム
pub fn is_same_value(a : JSValue, b : JSValue) -> Bool {
  let eq = js_strict_eq(a, b)
  match eq {
    JSValue::Bool(eq_bool) =>
      if eq_bool {
        match a {
          JSValue::Number(n1) =>
            match b {
              JSValue::Number(n2) =>
                // Handle +/-0 vs. -/+0
                if n1 == 0.0 {
                  let inv1 = 1.0 / n1
                  let inv2 = 1.0 / n2
                  inv1 == inv2
                } else {
                  true
                }
              _ => true
            }
          _ => true
        }
      } else {
        // Handle NaN vs. NaN
        let a_is_nan = match a {
          JSValue::Number(n) => n.is_nan()
          _ => false
        }
        let b_is_nan = match b {
          JSValue::Number(n) => n.is_nan()
          _ => false
        }
        a_is_nan && b_is_nan
      }
    _ => false
  }
}

///|
/// assert.sameValue
pub fn assert_same_value(
  actual : JSValue,
  expected : JSValue,
  message : String?,
) -> AssertResult {
  if is_same_value(actual, expected) {
    Success
  } else {
    let prefix = match message {
      Some(m) => m + " "
      None => ""
    }
    let actual_str = actual.to_js_string()
    let expected_str = expected.to_js_string()
    Failure(
      prefix +
      "Expected SameValue(«" +
      actual_str +
      "», «" +
      expected_str +
      "») to be true",
    )
  }
}

///|
/// assert.notSameValue
pub fn assert_not_same_value(
  actual : JSValue,
  unexpected : JSValue,
  message : String?,
) -> AssertResult {
  if !is_same_value(actual, unexpected) {
    Success
  } else {
    let prefix = match message {
      Some(m) => m + " "
      None => ""
    }
    let actual_str = actual.to_js_string()
    let unexpected_str = unexpected.to_js_string()
    Failure(
      prefix +
      "Expected SameValue(«" +
      actual_str +
      "», «" +
      unexpected_str +
      "») to be false",
    )
  }
}

///|
/// 配列比較ユーティリティ
pub fn compare_array(
  actual : JSValue,
  expected : JSValue,
  message : String?,
) -> AssertResult {
  let prefix = match message {
    Some(m) => m
    None => ""
  }
  match (actual, expected) {
    (JSValue::Array(arr1), JSValue::Array(arr2)) =>
      if arr1.length() != arr2.length() {
        Failure(
          prefix +
          "Array lengths differ: " +
          arr1.length().to_string() +
          " vs " +
          arr2.length().to_string(),
        )
      } else {
        let mut i = 0
        while i < arr1.length() {
          if !is_same_value(arr1[i], arr2[i]) {
            let actual_elem = arr1[i].to_js_string()
            let expected_elem = arr2[i].to_js_string()
            return Failure(
              prefix +
              "Arrays differ at index " +
              i.to_string() +
              ": " +
              actual_elem +
              " vs " +
              expected_elem,
            )
          }
          i = i + 1
        }
        Success
      }
    _ => Failure(prefix + "Both arguments must be arrays")
  }
}
