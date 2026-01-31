// interpretertest

///|
test "interpreter: simple arithmetic" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  return 1 + 2 * 3;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 7.0)
    _ => fail("expected Number, got \{result}")
  }
}

///|
test "interpreter: variable" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let x = 10;
      #|  let y = 20;
      #|  return x + y;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 30.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: if statement" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let x = 10;
      #|  if (x > 5) {
      #|    return 1;
      #|  } else {
      #|    return 0;
      #|  }
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 1.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: while loop" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let sum = 0;
      #|  let i = 1;
      #|  while (i <= 5) {
      #|    sum = sum + i;
      #|    i = i + 1;
      #|  }
      #|  return sum;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 15.0) // 1+2+3+4+5
    _ => fail("expected Number")
  }
}

///|
test "interpreter: function call" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function add(a, b) {
      #|  return a + b;
      #|}
      #|function main() {
      #|  return add(3, 4);
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 7.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: recursive factorial" {
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
      #|  return factorial(5);
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 120.0) // 5! = 120
    _ => fail("expected Number")
  }
}

///|
test "interpreter: string concat" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let a = "hello";
      #|  let b = " world";
      #|  return a + b;
      #|}
    ),
  )
  match result {
    String(s) => assert_eq(s, "hello world")
    _ => fail("expected String")
  }
}

///|
test "interpreter: string and number" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  return "value: " + 42;
      #|}
    ),
  )
  match result {
    String(s) => assert_eq(s, "value: 42")
    _ => fail("expected String")
  }
}

///|
test "interpreter: array literal" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let arr = [1, 2, 3];
      #|  return arr[1];
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 2.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: array length" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let arr = [10, 20, 30, 40];
      #|  return arr.length;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 4.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: object literal" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let obj = { x: 10, y: 20 };
      #|  return obj.x + obj.y;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 30.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: type coercion" {
  let interp = JSInterpreter::new()

  // == with coercion
  let result = interp.run(
    (
      #|function main() {
      #|  if (1 == "1") {
      #|    return 1;
      #|  }
      #|  return 0;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 1.0) // 1 == "1" is true in JS
    _ => fail("expected Number")
  }
}

///|
test "interpreter: strict equality" {
  let interp = JSInterpreter::new()

  // === without coercion
  let result = interp.run(
    (
      #|function main() {
      #|  if (1 === "1") {
      #|    return 1;
      #|  }
      #|  return 0;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 0.0) // 1 === "1" is false
    _ => fail("expected Number")
  }
}

///|
test "interpreter: logical and" {
  let interp = JSInterpreter::new()

  // && short-circuit
  let result1 = interp.run(
    (
      #|function main() {
      #|  return 0 && 42;
      #|}
    ),
  )
  match result1 {
    Number(n) => assert_eq(n, 0.0) // 0 is falsy, returns 0
    _ => fail("expected Number")
  }
}

///|
test "interpreter: logical or" {
  let interp = JSInterpreter::new()

  // || short-circuit: 0falsy42
  let result = interp.run(
    (
      #|function main() {
      #|  return 0 || 42;
      #|}
    ),
  )
  // check
  println("Result: \{result}")
  match result {
    Number(n) => assert_eq(n, 42.0)
    _ => fail("expected Number, got: \{result}")
  }
}

///|
test "interpreter: ternary operator" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let x = 10;
      #|  return x > 5 ? "big" : "small";
      #|}
    ),
  )
  match result {
    String(s) => assert_eq(s, "big")
    _ => fail("expected String")
  }
}

///|
test "interpreter: for loop" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let sum = 0;
      #|  for (let i: int = 1; i <= 5; i = i + 1) {
      #|    sum = sum + i;
      #|  }
      #|  return sum;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 15.0) // 1+2+3+4+5
    _ => fail("expected Number")
  }
}

///|
test "interpreter: fibonacci" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function fib(n) {
      #|  if (n <= 1) {
      #|    return n;
      #|  }
      #|  return fib(n - 1) + fib(n - 2);
      #|}
      #|function main() {
      #|  return fib(10);
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 55.0) // fib(10) = 55
    _ => fail("expected Number")
  }
}

///|
test "interpreter: closure" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function makeCounter() {
      #|  let count = 0;
      #|  function inc() {
      #|    count = count + 1;
      #|    return count;
      #|  }
      #|  return inc;
      #|}
      #|function main() {
      #|  let counter = makeCounter();
      #|  counter();
      #|  counter();
      #|  return counter();
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 3.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: string methods" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let s = "hello world";
      #|  return s.substring(0, 5);
      #|}
    ),
  )
  match result {
    String(s) => assert_eq(s, "hello")
    _ => fail("expected String")
  }
}

///|
test "interpreter: array methods" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let arr = [1, 2, 3];
      #|  arr.push(4);
      #|  return arr.join("-");
      #|}
    ),
  )
  match result {
    String(s) => assert_eq(s, "1-2-3-4")
    _ => fail("expected String")
  }
}

///|
test "interpreter: arrow function expression" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let add = (a, b) => a + b;
      #|  return add(3, 4);
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 7.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: arrow function block" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let square = (x) => {
      #|    return x * x;
      #|  };
      #|  return square(5);
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 25.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: arrow function no params" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let getVal = () => 42;
      #|  return getVal();
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 42.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: for loop without type annotation" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let sum = 0;
      #|  for (let i = 1; i <= 5; i = i + 1) {
      #|    sum = sum + i;
      #|  }
      #|  return sum;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 15.0) // 1+2+3+4+5
    _ => fail("expected Number")
  }
}

///|
test "interpreter: pre-increment" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let x = 5;
      #|  let y = ++x;
      #|  return x + y;  // x=6, y=6, result=12
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 12.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: post-increment" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let x = 5;
      #|  let y = x++;
      #|  return x + y;  // x=6, y=5, result=11
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 11.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: for loop with i++" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let sum = 0;
      #|  for (let i = 1; i <= 5; i++) {
      #|    sum = sum + i;
      #|  }
      #|  return sum;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 15.0) // 1+2+3+4+5
    _ => fail("expected Number")
  }
}

///|
test "interpreter: compound assignment +=" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let x = 10;
      #|  x += 5;
      #|  return x;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 15.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: compound assignment -=" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let x = 10;
      #|  x -= 3;
      #|  return x;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 7.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: array index assignment" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let arr = [1, 2, 3];
      #|  arr[1] = 10;
      #|  return arr[1];
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 10.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: object prop assignment" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let obj = { x: 1 };
      #|  obj.x = 42;
      #|  return obj.x;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 42.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: break in while loop" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let sum = 0;
      #|  let i = 0;
      #|  while (true) {
      #|    i++;
      #|    sum += i;
      #|    if (i >= 5) {
      #|      break;
      #|    }
      #|  }
      #|  return sum;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 15.0) // 1+2+3+4+5
    _ => fail("expected Number")
  }
}

///|
test "interpreter: continue in for loop" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let sum = 0;
      #|  for (let i = 1; i <= 10; i++) {
      #|    if (i % 2 == 0) {
      #|      continue;
      #|    }
      #|    sum += i;
      #|  }
      #|  return sum;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 25.0) // 1+3+5+7+9 = 25
    _ => fail("expected Number")
  }
}

///|
test "interpreter: break in for loop" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let sum = 0;
      #|  for (let i = 1; i <= 100; i++) {
      #|    sum += i;
      #|    if (sum > 10) {
      #|      break;
      #|    }
      #|  }
      #|  return sum;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 15.0) // 1+2+3+4+5=15 > 10
    _ => fail("expected Number")
  }
}

///|
test "interpreter: for...of loop array" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let arr = [10, 20, 30];
      #|  let sum = 0;
      #|  for (let x of arr) {
      #|    sum += x;
      #|  }
      #|  return sum;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 60.0) // 10+20+30
    _ => fail("expected Number")
  }
}

///|
test "interpreter: for...of with break" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let arr = [1, 2, 3, 4, 5];
      #|  let sum = 0;
      #|  for (let x of arr) {
      #|    sum += x;
      #|    if (sum >= 6) {
      #|      break;
      #|    }
      #|  }
      #|  return sum;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 6.0) // 1+2+3=6
    _ => fail("expected Number")
  }
}

///|
test "interpreter: labeled break in nested loops" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let sum = 0;
      #|  outer: for (let i = 0; i < 3; i++) {
      #|    for (let j = 0; j < 3; j++) {
      #|      sum += 1;
      #|      break outer;
      #|    }
      #|  }
      #|  return sum;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 1.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: labeled continue in nested loops" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let sum = 0;
      #|  outer: for (let i = 0; i < 3; i++) {
      #|    for (let j = 0; j < 3; j++) {
      #|      if (j == 1) {
      #|        continue outer;
      #|      }
      #|      sum += 1;
      #|    }
      #|  }
      #|  return sum;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 3.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: with statement resolves object properties" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let obj = { a: 1, b: 2 };
      #|  let sum = 0;
      #|  with (obj) {
      #|    sum = a + b;
      #|    b = 3;
      #|  }
      #|  return sum + obj.b;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 6.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: debugger is no-op" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  debugger;
      #|  return 1;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 1.0)
    _ => fail("expected Number")
  }
}

///|
test "interpreter: eval for completion value - no iteration" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  return eval('1; for (var run = false; run; ) { }');
      #|}
    ),
  )
  inspect(result, content="Undefined")
}

///|
test "eval: for completion value - iteration with body" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  return eval('2; for (var runB = true; runB; runB = false) { 3; }');
      #|}
    ),
  )
  inspect(result, content="Number(3)")
}

///|
test "eval: for completion value - iteration without body" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  return eval('1; for (var runA = true; runA; runA = false) { }');
      #|}
    ),
  )
  inspect(result, content="Undefined")
}

///|
test "interpreter: for loop let scope basic" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  let x = 'outside';
      #|  let captured;
      #|  for (let x = 'inside'; true; ) {
      #|    captured = function() { return x; };
      #|    break;
      #|  }
      #|  return captured();
      #|}
    ),
  )
  inspect(result, content="String(\"inside\")")
}

///|
test "interpreter: nullish coalescing with null" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  var a = null ?? "default";
      #|  return a;
      #|}
    ),
  )
  inspect(result, content="String(\"default\")")
}

///|
test "interpreter: nullish coalescing with undefined" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  var a = undefined ?? "fallback";
      #|  return a;
      #|}
    ),
  )
  inspect(result, content="String(\"fallback\")")
}

///|
test "interpreter: nullish coalescing preserves zero" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  return 0 ?? "unused";
      #|}
    ),
  )
  // 0 should NOT trigger default value (unlike ||)
  inspect(result, content="Number(0)")
}

///|
test "interpreter: nullish coalescing preserves empty string" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  return "" ?? "unused";
      #|}
    ),
  )
  // "" should NOT trigger default value (unlike ||)
  inspect(result, content="String(\"\")")
}

///|
test "interpreter: nullish coalescing preserves false" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  return false ?? "unused";
      #|}
    ),
  )
  // false should NOT trigger default value (unlike ||)
  inspect(result, content="Bool(false)")
}
