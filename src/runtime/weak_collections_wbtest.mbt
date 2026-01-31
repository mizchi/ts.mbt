// WeakMap, WeakSet, WeakRef, FinalizationRegistry tests

///|
test "weakmap: basic get/set/has/delete" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let wm = new WeakMap();
    #|  let obj = { x: 1 };
    #|  wm.set(obj, "value1");
    #|  let results = [];
    #|  results.push(wm.has(obj));  // true
    #|  results.push(wm.get(obj));  // "value1"
    #|  wm.set(obj, "value2");      // update
    #|  results.push(wm.get(obj));  // "value2"
    #|  results.push(wm.delete(obj)); // true
    #|  results.push(wm.has(obj));  // false
    #|  results.push(wm.get(obj));  // undefined
    #|  return results;
    #|}
  let result = interp.run(src)
  match result {
    JSValue::Array(arr) => {
      assert_true(arr.items[0] is Bool(true))
      assert_true(arr.items[1] is String("value1"))
      assert_true(arr.items[2] is String("value2"))
      assert_true(arr.items[3] is Bool(true))
      assert_true(arr.items[4] is Bool(false))
      assert_true(arr.items[5] is Undefined)
    }
    _ => panic()
  }
}

///|
test "weakmap: multiple keys" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let wm = new WeakMap();
    #|  let obj1 = { a: 1 };
    #|  let obj2 = { b: 2 };
    #|  let arr = [1, 2, 3];
    #|  wm.set(obj1, "one");
    #|  wm.set(obj2, "two");
    #|  wm.set(arr, "array");
    #|  return [wm.get(obj1), wm.get(obj2), wm.get(arr)];
    #|}
  let result = interp.run(src)
  match result {
    JSValue::Array(arr) => {
      assert_true(arr.items[0] is String("one"))
      assert_true(arr.items[1] is String("two"))
      assert_true(arr.items[2] is String("array"))
    }
    _ => panic()
  }
}

///|
test "weakmap: function as key" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let wm = new WeakMap();
    #|  function fn() { return 42; }
    #|  wm.set(fn, "function value");
    #|  return [wm.has(fn), wm.get(fn)];
    #|}
  let result = interp.run(src)
  match result {
    JSValue::Array(arr) => {
      assert_true(arr.items[0] is Bool(true))
      assert_true(arr.items[1] is String("function value"))
    }
    _ => panic()
  }
}

///|
test "weakmap: primitive keys return undefined" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let wm = new WeakMap();
    #|  // Primitive keys should be silently ignored
    #|  wm.set(1, "number");
    #|  wm.set("str", "string");
    #|  return [wm.has(1), wm.has("str"), wm.get(1), wm.get("str")];
    #|}
  let result = interp.run(src)
  match result {
    JSValue::Array(arr) => {
      // Primitives can't be WeakMap keys - has returns false, get returns undefined
      assert_true(arr.items[0] is Bool(false))
      assert_true(arr.items[1] is Bool(false))
      assert_true(arr.items[2] is Undefined)
      assert_true(arr.items[3] is Undefined)
    }
    _ => panic()
  }
}

///|
test "weakset: basic add/has/delete" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let ws = new WeakSet();
    #|  let obj = { x: 1 };
    #|  ws.add(obj);
    #|  let results = [];
    #|  results.push(ws.has(obj));  // true
    #|  results.push(ws.delete(obj)); // true
    #|  results.push(ws.has(obj));  // false
    #|  results.push(ws.delete(obj)); // false (already deleted)
    #|  return results;
    #|}
  let result = interp.run(src)
  match result {
    JSValue::Array(arr) => {
      assert_true(arr.items[0] is Bool(true))
      assert_true(arr.items[1] is Bool(true))
      assert_true(arr.items[2] is Bool(false))
      assert_true(arr.items[3] is Bool(false))
    }
    _ => panic()
  }
}

///|
test "weakset: multiple values" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let ws = new WeakSet();
    #|  let obj1 = { a: 1 };
    #|  let obj2 = { b: 2 };
    #|  let arr = [1, 2];
    #|  ws.add(obj1);
    #|  ws.add(obj2);
    #|  ws.add(arr);
    #|  return [ws.has(obj1), ws.has(obj2), ws.has(arr)];
    #|}
  let result = interp.run(src)
  match result {
    JSValue::Array(arr) => {
      assert_true(arr.items[0] is Bool(true))
      assert_true(arr.items[1] is Bool(true))
      assert_true(arr.items[2] is Bool(true))
    }
    _ => panic()
  }
}

///|
test "weakset: add returns the set" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let ws = new WeakSet();
    #|  let obj = {};
    #|  let result = ws.add(obj);
    #|  return result === ws;
    #|}
  let result = interp.run(src)
  assert_true(result is Bool(true))
}

///|
test "weakset: duplicate add is idempotent" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let ws = new WeakSet();
    #|  let obj = {};
    #|  ws.add(obj);
    #|  ws.add(obj);
    #|  ws.add(obj);
    #|  return ws.has(obj);
    #|}
  let result = interp.run(src)
  assert_true(result is Bool(true))
}

///|
test "weakref: basic deref" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let obj = { value: 42 };
    #|  let wr = new WeakRef(obj);
    #|  let derefed = wr.deref();
    #|  return [derefed === obj, derefed.value];
    #|}
  let result = interp.run(src)
  match result {
    JSValue::Array(arr) => {
      assert_true(arr.items[0] is Bool(true))
      match arr.items[1] {
        Number(n) => assert_eq(n, 42.0)
        _ => panic()
      }
    }
    _ => panic()
  }
}

///|
test "weakref: deref returns target" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let arr = [1, 2, 3];
    #|  let wr = new WeakRef(arr);
    #|  return wr.deref().length;
    #|}
  let result = interp.run(src)
  match result {
    Number(n) => assert_eq(n, 3.0)
    _ => panic()
  }
}

///|
test "finalization_registry: register and unregister" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let cleanupCalled = false;
    #|  let fr = new FinalizationRegistry((heldValue) => {
    #|    cleanupCalled = true;
    #|  });
    #|  let obj = {};
    #|  let token = {};
    #|  fr.register(obj, "held", token);
    #|  let unregResult = fr.unregister(token);
    #|  // Unregister again should return false
    #|  let unregResult2 = fr.unregister(token);
    #|  return [unregResult, unregResult2];
    #|}
  let result = interp.run(src)
  match result {
    JSValue::Array(arr) => {
      assert_true(arr.items[0] is Bool(true))
      assert_true(arr.items[1] is Bool(false))
    }
    _ => panic()
  }
}

///|
test "finalization_registry: multiple registrations with same token" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let fr = new FinalizationRegistry(() => {});
    #|  let obj1 = {};
    #|  let obj2 = {};
    #|  let token = {};
    #|  fr.register(obj1, "one", token);
    #|  fr.register(obj2, "two", token);
    #|  // Unregister should remove both
    #|  let result = fr.unregister(token);
    #|  return result;
    #|}
  let result = interp.run(src)
  assert_true(result is Bool(true))
}

///|
test "finalization_registry: cleanupSome exists" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let fr = new FinalizationRegistry(() => {});
    #|  return typeof fr.cleanupSome;
    #|}
  let result = interp.run(src)
  assert_true(result is String("function"))
}

///|
test "weakmap: set returns the map" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let wm = new WeakMap();
    #|  let obj = {};
    #|  let result = wm.set(obj, 1);
    #|  return result === wm;
    #|}
  let result = interp.run(src)
  assert_true(result is Bool(true))
}

// === VM GC Tests ===

///|
test "vm_gc: gc function exists" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  return typeof gc;
    #|}
  let result = interp.run(src)
  assert_true(result is String("function"))
}

///|
test "vm_gc: gc returns number" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let result = gc();
    #|  return typeof result;
    #|}
  let result = interp.run(src)
  assert_true(result is String("number"))
}

///|
test "vm_gc: basic gc run" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  // Run GC - should not crash
    #|  gc();
    #|  return 42;
    #|}
  let result = interp.run(src)
  match result {
    Number(n) => assert_eq(n, 42.0)
    _ => panic()
  }
}

///|
test "vm_gc: gc with weakmap" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let wm = new WeakMap();
    #|  let obj = { x: 1 };
    #|  wm.set(obj, "value");
    #|  gc();
    #|  // obj is still reachable
    #|  return wm.has(obj);
    #|}
  let result = interp.run(src)
  assert_true(result is Bool(true))
}

///|
test "vm_gc: gc with weakset" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let ws = new WeakSet();
    #|  let obj = { x: 1 };
    #|  ws.add(obj);
    #|  gc();
    #|  // obj is still reachable
    #|  return ws.has(obj);
    #|}
  let result = interp.run(src)
  assert_true(result is Bool(true))
}

///|
test "vm_gc: gc with weakref" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let obj = { x: 42 };
    #|  let wr = new WeakRef(obj);
    #|  gc();
    #|  // obj is still reachable
    #|  return wr.deref().x;
    #|}
  let result = interp.run(src)
  match result {
    Number(n) => assert_eq(n, 42.0)
    _ => panic()
  }
}

///|
test "vm_gc: finalization registry basic" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let fr = new FinalizationRegistry((val) => {});
    #|  let obj = {};
    #|  fr.register(obj, "held");
    #|  gc();
    #|  return true;
    #|}
  let result = interp.run(src)
  assert_true(result is Bool(true))
}

// === GC Integration Tests ===

///|
test "gc: weakmap allocation tracking" {
  gc_stats_reset()
  let interp = JSInterpreter::new()
  let (_, _, _, env_before) = gc_stats_snapshot()
  let src =
    #|function main() {
    #|  let wm = new WeakMap();
    #|  for (let i = 0; i < 10; i++) {
    #|    let obj = { id: i };
    #|    wm.set(obj, i * 2);
    #|  }
    #|  return 42;
    #|}
  let _ = interp.run(src)
  let (obj_after, _, _, env_after) = gc_stats_snapshot()
  // WeakMap should have allocated objects
  assert_true(obj_after > 0)
  // Loop with let creates new envs
  assert_true(env_after > env_before)
}

///|
test "gc: weakset allocation tracking" {
  gc_stats_reset()
  let interp = JSInterpreter::new()
  let (obj_before, _, _, _) = gc_stats_snapshot()
  let src =
    #|function main() {
    #|  let ws = new WeakSet();
    #|  for (let i = 0; i < 10; i++) {
    #|    ws.add({ id: i });
    #|  }
    #|  return 42;
    #|}
  let _ = interp.run(src)
  let (obj_after, _, _, _) = gc_stats_snapshot()
  // Should have allocated objects for WeakSet entries
  assert_true(obj_after > obj_before)
}

///|
test "gc: weakref allocation tracking" {
  gc_stats_reset()
  let interp = JSInterpreter::new()
  let (obj_before, _, _, _) = gc_stats_snapshot()
  let src =
    #|function main() {
    #|  let refs = [];
    #|  for (let i = 0; i < 5; i++) {
    #|    refs.push(new WeakRef({ value: i }));
    #|  }
    #|  return refs.length;
    #|}
  let _ = interp.run(src)
  let (obj_after, _, _, _) = gc_stats_snapshot()
  // Should have allocated WeakRef and target objects
  assert_true(obj_after > obj_before)
}

///|
test "gc: finalization_registry allocation tracking" {
  gc_stats_reset()
  let interp = JSInterpreter::new()
  let (obj_before, _, _, _) = gc_stats_snapshot()
  let src =
    #|function main() {
    #|  let count = 0;
    #|  let fr = new FinalizationRegistry(() => { count++; });
    #|  for (let i = 0; i < 5; i++) {
    #|    let obj = {};
    #|    fr.register(obj, i, obj);
    #|  }
    #|  return 42;
    #|}
  let _ = interp.run(src)
  let (obj_after, _, _, _) = gc_stats_snapshot()
  // Should have allocated FinalizationRegistry and registration arrays
  assert_true(obj_after > obj_before)
}

// === Perceus GC Tests ===

///|
test "perceus: scope functions exist" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  return [typeof $enterScope, typeof $exitScope, typeof $markEscaped];
    #|}
  let result = interp.run(src)
  match result {
    JSValue::Array(arr) => {
      assert_true(arr.items[0] is String("function"))
      assert_true(arr.items[1] is String("function"))
      assert_true(arr.items[2] is String("function"))
    }
    _ => panic()
  }
}

///|
test "perceus: enter and exit scope" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let scope1 = $enterScope();
    #|  let scope2 = $enterScope();
    #|  let cleanup2 = $exitScope();
    #|  let cleanup1 = $exitScope();
    #|  return [scope1 > 0, scope2 > scope1, cleanup2, cleanup1];
    #|}
  let result = interp.run(src)
  match result {
    JSValue::Array(arr) => {
      // scope IDs should be positive and increasing
      assert_true(arr.items[0] is Bool(true))
      assert_true(arr.items[1] is Bool(true))
      // cleanup counts should be numbers
      match arr.items[2] {
        Number(_) => ()
        _ => panic()
      }
      match arr.items[3] {
        Number(_) => ()
        _ => panic()
      }
    }
    _ => panic()
  }
}

///|
test "perceus: mark escaped prevents cleanup" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let obj = { x: 42 };
    #|  let scope = $enterScope();
    #|  // Mark obj as escaped - it should not be cleaned up
    #|  $markEscaped(obj);
    #|  let cleanup = $exitScope();
    #|  return [scope > 0, obj.x];
    #|}
  let result = interp.run(src)
  match result {
    JSValue::Array(arr) => {
      assert_true(arr.items[0] is Bool(true))
      match arr.items[1] {
        Number(n) => assert_eq(n, 42.0)
        _ => panic()
      }
    }
    _ => panic()
  }
}

///|
test "perceus: nested scopes" {
  let interp = JSInterpreter::new()
  let src =
    #|function main() {
    #|  let results = [];
    #|  let outer = $enterScope();
    #|  results.push(outer);
    #|  let inner = $enterScope();
    #|  results.push(inner);
    #|  results.push($exitScope()); // exit inner
    #|  results.push($exitScope()); // exit outer
    #|  return results;
    #|}
  let result = interp.run(src)
  match result {
    JSValue::Array(arr) =>
      // All results should be numbers
      for item in arr.items {
        match item {
          Number(_) => ()
          _ => panic()
        }
      }
    _ => panic()
  }
}
