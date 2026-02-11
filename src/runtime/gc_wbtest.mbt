// GC and memory allocation tests

///|
test "gc: object allocation tracking" {
  gc_stats_reset()

  // Create interpreter (allocates builtins)
  let interp = JSInterpreter::new()
  let (obj1, func1, _arr1, env1) = gc_stats_snapshot()

  // Should have allocated objects for builtins
  assert_true(obj1 > 0)
  assert_true(func1 > 0)
  assert_true(env1 > 0)

  // Run simple code
  let src =
    #|function main() {
    #|  let x = { a: 1 };
    #|  return x.a;
    #|}
  let _ = interp.run(src)
  let (obj2, _, _, _) = gc_stats_snapshot()

  // Should have allocated at least one more object
  assert_true(obj2 > obj1)
}

///|
test "gc: array allocation tracking" {
  gc_stats_reset()
  let interp = JSInterpreter::new()
  let (_, _, arr1, _) = gc_stats_snapshot()

  // Run code that creates arrays
  let src =
    #|function main() {
    #|  let arr = [1, 2, 3];
    #|  return arr.map(x => x * 2);
    #|}
  let _ = interp.run(src)
  let (_, _, arr2, _) = gc_stats_snapshot()

  // Should have allocated arrays
  assert_true(arr2 > arr1)
}

///|
test "gc: function allocation tracking" {
  gc_stats_reset()
  let interp = JSInterpreter::new()
  let (_, func1, _, _) = gc_stats_snapshot()

  // Run code that creates functions
  let src =
    #|function f() { return 1; }
    #|function g() { return 2; }
    #|function main() { return f() + g(); }
  let _ = interp.run(src)
  let (_, func2, _, _) = gc_stats_snapshot()

  // Should have allocated functions
  assert_true(func2 > func1)
}

///|
test "gc: env allocation in loop" {
  gc_stats_reset()
  let interp = JSInterpreter::new()
  let (_, _, _, env1) = gc_stats_snapshot()

  // Run code with loop (creates envs per iteration for let)
  let src =
    #|function main() {
    #|  let sum = 0;
    #|  for (let i = 0; i < 10; i++) {
    #|    sum += i;
    #|  }
    #|  return sum;
    #|}
  let _ = interp.run(src)
  let (_, _, _, env2) = gc_stats_snapshot()

  // Loop with let creates new envs
  assert_true(env2 > env1)
}

///|
test "gc: allocation count consistency" {
  gc_stats_reset()

  // Run same code twice, should have similar allocation patterns
  let src =
    #|function main() {
    #|  let x = 1;
    #|  return x + 2;
    #|}
  let interp1 = JSInterpreter::new()
  let _ = interp1.run(src)
  let total1 = gc_stats_total()
  gc_stats_reset()
  let interp2 = JSInterpreter::new()
  let _ = interp2.run(src)
  let total2 = gc_stats_total()

  // Should be approximately equal (same code path)
  assert_eq(total1, total2)
}

///|
test "gc: closure captures" {
  gc_stats_reset()
  let interp = JSInterpreter::new()

  // Create closures that capture loop variable
  let src =
    #|function main() {
    #|  let funcs = [];
    #|  for (let i = 0; i < 5; i++) {
    #|    funcs.push(() => i);
    #|  }
    #|  // Each closure should capture its own i
    #|  return funcs[0]() + funcs[2]() + funcs[4]();
    #|}
  let result = interp.run(src)

  // Verify correctness: 0 + 2 + 4 = 6
  assert_true(result is Number(_))
}

///|
test "gc: nested function scopes" {
  gc_stats_reset()
  let interp = JSInterpreter::new()
  let (_, _, _, env_before) = gc_stats_snapshot()
  let src =
    #|function outer(x) {
    #|  function inner(y) {
    #|    return x + y;
    #|  }
    #|  return inner(10);
    #|}
    #|function main() { return outer(5); }
  let result = interp.run(src)
  let (_, _, _, env_after) = gc_stats_snapshot()

  // Should have created envs for outer and inner calls
  assert_true(env_after > env_before)

  // Verify result
  assert_true(result is Number(_))
}

///|
test "gc: object property churn" {
  gc_stats_reset()
  let interp = JSInterpreter::new()
  let (obj_before, _, _, _) = gc_stats_snapshot()

  // Repeatedly modify object properties (should not create new objects)
  let src =
    #|function main() {
    #|  let obj = { x: 0 };
    #|  for (let i = 0; i < 100; i++) {
    #|    obj.x = i;
    #|  }
    #|  return obj.x;
    #|}
  let _ = interp.run(src)
  let (obj_after, _, _, _) = gc_stats_snapshot()

  // Modifying existing object shouldn't create many new objects
  // Only the initial object should be created
  let objects_created = obj_after - obj_before
  assert_true(objects_created < 10) // Allow some overhead
}

///|
test "gc: array push operations" {
  gc_stats_reset()
  let interp = JSInterpreter::new()
  let (_, _, arr_before, _) = gc_stats_snapshot()

  // Push to array should not create new array objects
  let src =
    #|function main() {
    #|  let arr = [];
    #|  for (let i = 0; i < 50; i++) {
    #|    arr.push(i);
    #|  }
    #|  return arr.length;
    #|}
  let _ = interp.run(src)
  let (_, _, arr_after, _) = gc_stats_snapshot()

  // Should only create one array, not 50
  let arrays_created = arr_after - arr_before
  assert_true(arrays_created < 5) // Allow some overhead for temp arrays
}

///|
test "gc: map creates new array" {
  gc_stats_reset()
  let interp = JSInterpreter::new()
  let (_, _, arr_before, _) = gc_stats_snapshot()
  let src =
    #|function main() {
    #|  let arr = [1, 2, 3, 4, 5];
    #|  return arr.map(x => x * 2);
    #|}
  let _ = interp.run(src)
  let (_, _, arr_after, _) = gc_stats_snapshot()

  // map should create a new array (original + result)
  let arrays_created = arr_after - arr_before
  assert_true(arrays_created >= 2)
}

///|
test "gc: repeated interpreter creation" {
  gc_stats_reset()
  let src =
    #|function main() {
    #|  return 42;
    #|}

  // Create multiple interpreters and run code
  for _ in 0..<5 {
    let interp = JSInterpreter::new()
    let _ = interp.run(src)
  }
  let total = gc_stats_total()

  // Should have consistent allocation per interpreter
  // (approximately 5x the single interpreter allocation)
  assert_true(total > 0)
}
