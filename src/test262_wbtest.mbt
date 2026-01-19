// test262 style tests for the JS interpreter
// Tests that use assert.sameValue and other test262 harness functions

// ============================================
// test262: Language / Types
// ============================================
// Note: typeof operator is not yet supported in the parser

///|
test "test262: undefined value" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let x = undefined;
      #|  assert.sameValue(x === undefined, true);
      #|}
    ),
  )
  // Check if assertion failed (returned error object)
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: null value" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let x = null;
      #|  assert.sameValue(x === null, true);
      #|}
    ),
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: boolean values" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  assert.sameValue(true === true, true);
      #|  assert.sameValue(false === false, true);
      #|  assert.sameValue(true !== false, true);
      #|}
    ),
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: number values" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  assert.sameValue(42 === 42, true);
      #|  assert.sameValue(3.14 === 3.14, true);
      #|}
    ),
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: string values" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  assert.sameValue("hello" === "hello", true);
      #|  assert.sameValue("foo" !== "bar", true);
      #|}
    ),
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: function values" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function f() { return 42; }
      #|function main() {
      #|  assert.sameValue(f(), 42);
      #|}
    ),
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: object values" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let obj = {};
      #|  obj.x = 10;
      #|  assert.sameValue(obj.x, 10);
      #|}
    ),
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

// ============================================
// test262: Language / Expressions / Operators
// ============================================

///|
test "test262: addition" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(1 + 2, 3);
    #|  assert.sameValue(1.5 + 2.5, 4.0);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: subtraction" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(5 - 3, 2);
    #|  assert.sameValue(3.5 - 1.5, 2.0);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: multiplication" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(3 * 4, 12);
    #|  assert.sameValue(2.5 * 4, 10.0);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: division" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(10 / 2, 5);
    #|  assert.sameValue(7 / 2, 3.5);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: modulo" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(10 % 3, 1);
    #|  assert.sameValue(7 % 2, 1);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: comparison operators" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(1 < 2, true);
    #|  assert.sameValue(2 > 1, true);
    #|  assert.sameValue(1 <= 1, true);
    #|  assert.sameValue(2 >= 2, true);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: strict equality" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(1 === 1, true);
    #|  assert.sameValue(1 === "1", false);
    #|  assert.sameValue(null === null, true);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: strict inequality" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(1 !== 2, true);
    #|  assert.sameValue(1 !== "1", true);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: logical and" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(true && true, true);
    #|  assert.sameValue(true && false, false);
    #|  assert.sameValue(false && true, false);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: logical or" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(true || false, true);
    #|  assert.sameValue(false || true, true);
    #|  assert.sameValue(false || false, false);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

// ============================================
// test262: Language / Statements
// ============================================

///|
test "test262: if statement" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  let x = 10;
    #|  let result = 0;
    #|  if (x > 5) {
    #|    result = 1;
    #|  } else {
    #|    result = 2;
    #|  }
    #|  assert.sameValue(result, 1);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: while loop" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  let sum = 0;
    #|  let i = 1;
    #|  while (i <= 5) {
    #|    sum = sum + i;
    #|    i = i + 1;
    #|  }
    #|  assert.sameValue(sum, 15);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: for loop" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  let sum = 0;
    #|  for (let i = 1; i <= 5; i = i + 1) {
    #|    sum = sum + i;
    #|  }
    #|  assert.sameValue(sum, 15);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: break statement" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  let count = 0;
    #|  while (true) {
    #|    count = count + 1;
    #|    if (count === 3) {
    #|      break;
    #|    }
    #|  }
    #|  assert.sameValue(count, 3);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: continue statement" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  let sum = 0;
    #|  for (let i = 1; i <= 5; i = i + 1) {
    #|    if (i === 3) {
    #|      continue;
    #|    }
    #|    sum = sum + i;
    #|  }
    #|  assert.sameValue(sum, 12);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

// ============================================
// test262: Language / Functions
// ============================================

///|
test "test262: function declaration" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function add(a, b) {
    #|  return a + b;
    #|}
    #|function main() {
    #|  assert.sameValue(add(2, 3), 5);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: recursive function" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function factorial(n) {
      #|  if (n <= 1) {
      #|    return 1;
      #|  }
      #|  return n * factorial(n - 1);
      #|}
      #|function main() {
      #|  assert.sameValue(factorial(5), 120);
      #|}
    ),
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: closure" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function makeCounter() {
    #|  let count = 0;
    #|  function increment() {
    #|    count = count + 1;
    #|    return count;
    #|  }
    #|  return increment;
    #|}
    #|function main() {
    #|  let counter = makeCounter();
    #|  assert.sameValue(counter(), 1);
    #|  assert.sameValue(counter(), 2);
    #|  assert.sameValue(counter(), 3);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

// ============================================
// test262: Built-in Objects / Array
// ============================================

///|
test "test262: array length" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  let arr = [1, 2, 3, 4, 5];
    #|  assert.sameValue(arr.length, 5);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: array indexing" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  let arr = [10, 20, 30];
    #|  assert.sameValue(arr[0], 10);
    #|  assert.sameValue(arr[1], 20);
    #|  assert.sameValue(arr[2], 30);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: array push" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  let arr = [1, 2];
    #|  arr.push(3);
    #|  assert.sameValue(arr.length, 3);
    #|  assert.sameValue(arr[2], 3);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

// ============================================
// test262: Built-in Objects / String
// ============================================

///|
test "test262: string length" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  let s = "hello";
    #|  assert.sameValue(s.length, 5);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: string charAt" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  let s = "hello";
    #|  assert.sameValue(s.charAt(0), "h");
    #|  assert.sameValue(s.charAt(4), "o");
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: string concat" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  let s = "hello";
    #|  assert.sameValue(s.concat(" world"), "hello world");
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

// ============================================
// test262: Built-in Objects / Math
// ============================================

///|
test "test262: Math.floor" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(Math.floor(3.7), 3);
    #|  assert.sameValue(Math.floor(3.2), 3);
    #|  assert.sameValue(Math.floor(3), 3);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: Math.ceil" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(Math.ceil(3.2), 4);
    #|  assert.sameValue(Math.ceil(3.7), 4);
    #|  assert.sameValue(Math.ceil(3), 3);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: Math.abs" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(Math.abs(5), 5);
    #|  assert.sameValue(Math.abs(-5), 5);
    #|  assert.sameValue(Math.abs(0), 0);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: Math.min" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(Math.min(1, 2, 3), 1);
    #|  assert.sameValue(Math.min(3, 1, 2), 1);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
test "test262: Math.max" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    #|function main() {
    #|  assert.sameValue(Math.max(1, 2, 3), 3);
    #|  assert.sameValue(Math.max(3, 1, 2), 3);
    #|}
  )
  match result {
    Object(_) => {
      let error = js_get_prop(result, "error")
      match error {
        JSValue::String(msg) => fail(msg)
        _ => ()
      }
    }
    _ => ()
  }
}
