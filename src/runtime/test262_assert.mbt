// test262 harness implementation for MoonBit JS interpreter

///|
// / AssertResult testresult
pub enum AssertResult {
  Success
  Failure(String)
}

///|
// / SameValue
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
/// Get array-like length
fn get_arraylike_length(value : JSValue) -> Int? {
  match value {
    JSValue::Array(arr) => Some(arr.items.length())
    JSValue::Object(_) =>
      match js_get_prop(value, "length") {
        JSValue::Number(n) => Some(n.to_int())
        _ => None
      }
    _ => None
  }
}

///|
/// Get element from array-like value
fn get_arraylike_element(value : JSValue, index : Int) -> JSValue {
  match value {
    JSValue::Array(arr) =>
      if index >= 0 && index < arr.items.length() {
        arr.items[index]
      } else {
        JSValue::Undefined
      }
    JSValue::Object(_) =>
      // Try TypedArray first
      match get_typedarray_data(value) {
        Some(data) =>
          if index >= 0 && index < data.length {
            // Return as BigInt for BigInt typed arrays
            match data.kind {
              BigInt64Array | BigUint64Array =>
                JSValue::BigInt(
                  BigInt::from_int64(
                    typedarray_get_element(data, index).to_int64(),
                  ),
                )
              _ => JSValue::Number(typedarray_get_element(data, index))
            }
          } else {
            JSValue::Undefined
          }
        None =>
          // Fall back to regular property access
          js_get_prop(value, index.to_string())
      }
    _ => JSValue::Undefined
  }
}

///|
// / arraycomparison
pub fn compare_array(
  actual : JSValue,
  expected : JSValue,
  message : String?,
) -> AssertResult {
  let prefix = match message {
    Some(m) => m
    None => ""
  }
  let len1 = match get_arraylike_length(actual) {
    Some(n) => n
    None => return Failure(prefix + "Both arguments must be arrays")
  }
  let len2 = match get_arraylike_length(expected) {
    Some(n) => n
    None => return Failure(prefix + "Both arguments must be arrays")
  }
  if len1 != len2 {
    return Failure(
      prefix +
      "Array lengths differ: " +
      len1.to_string() +
      " vs " +
      len2.to_string(),
    )
  }
  let mut i = 0
  while i < len1 {
    let elem1 = get_arraylike_element(actual, i)
    let elem2 = get_arraylike_element(expected, i)
    if not(is_same_value(elem1, elem2)) {
      return Failure(
        prefix +
        "Arrays differ at index " +
        i.to_string() +
        ": " +
        elem1.to_js_string() +
        " vs " +
        elem2.to_js_string(),
      )
    }
    i = i + 1
  }
  Success
}
