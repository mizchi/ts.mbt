// TypedArray and ArrayBuffer tests

///|
test "ArrayBuffer: constructor and byteLength" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ab = new ArrayBuffer(16);
      #|  return ab.byteLength;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 16.0)
    _ => fail("expected Number, got \{result}")
  }
}

///|
test "ArrayBuffer: slice" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ab = new ArrayBuffer(16);
      #|  const sliced = ab.slice(4, 12);
      #|  return sliced.byteLength;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 8.0)
    _ => fail("expected Number, got \{result}")
  }
}

///|
test "ArrayBuffer.isView" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ab = new ArrayBuffer(16);
      #|  const ta = new Uint8Array(ab);
      #|  return ArrayBuffer.isView(ta) && !ArrayBuffer.isView(ab) && !ArrayBuffer.isView({});
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "Uint8Array: constructor with length" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array(10);
      #|  return ta.length;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 10.0)
    _ => fail("expected Number, got \{result}")
  }
}

///|
test "Uint8Array: index access" {
  let interp = JSInterpreter::new()
  // First test: simple read
  let result1 = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array(3);
      #|  return ta.length;
      #|}
    ),
  )
  match result1 {
    Number(n) => assert_eq(n, 3.0)
    _ => fail("expected Number for length, got \{result1}")
  }
  // Test that index returns 0 for initialized array
  let result2 = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array(3);
      #|  return ta[0];
      #|}
    ),
  )
  match result2 {
    Number(n) => assert_eq(n, 0.0)
    _ => fail("expected Number(0) for ta[0], got \{result2}")
  }
  // Test write and read
  let result3 = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array(3);
      #|  ta[0] = 42;
      #|  return ta[0];
      #|}
    ),
  )
  match result3 {
    Number(n) => assert_eq(n, 42.0)
    _ => fail("expected Number(42) for ta[0], got \{result3}")
  }
}

///|
test "Uint8Array: properties" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array(10);
      #|  return ta.length === 10 &&
      #|         ta.byteLength === 10 &&
      #|         ta.byteOffset === 0 &&
      #|         ta.BYTES_PER_ELEMENT === 1;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "Uint8Array: from ArrayBuffer" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ab = new ArrayBuffer(16);
      #|  const ta = new Uint8Array(ab, 4, 8);
      #|  return ta.length === 8 && ta.byteOffset === 4 && ta.byteLength === 8;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "Uint8Array: from array" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([1, 2, 3, 4, 5]);
      #|  return ta.length === 5 && ta[0] === 1 && ta[4] === 5;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "Int8Array: signed values" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Int8Array(2);
      #|  ta[0] = 127;
      #|  ta[1] = 128; // wraps to -128
      #|  return ta[0] === 127 && ta[1] === -128;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "Uint8ClampedArray: clamping" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8ClampedArray(3);
      #|  ta[0] = 300;  // clamps to 255
      #|  ta[1] = -10;  // clamps to 0
      #|  ta[2] = 128;
      #|  return ta[0] === 255 && ta[1] === 0 && ta[2] === 128;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "Int16Array: 16-bit values" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Int16Array(2);
      #|  ta[0] = 32767;
      #|  ta[1] = 32768; // wraps to -32768
      #|  return ta[0] === 32767 && ta[1] === -32768;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "Float32Array: float values" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Float32Array(2);
      #|  ta[0] = 3.14;
      #|  ta[1] = -2.5;
      #|  return Math.abs(ta[0] - 3.14) < 0.001 && ta[1] === -2.5;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "Float64Array: double values" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Float64Array(2);
      #|  ta[0] = 3.141592653589793;
      #|  ta[1] = -1e100;
      #|  return ta[0] === 3.141592653589793 && ta[1] === -1e100;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: fill" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array(5);
      #|  ta.fill(42);
      #|  return ta[0] === 42 && ta[4] === 42;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: slice" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([1, 2, 3, 4, 5]);
      #|  const sliced = ta.slice(1, 4);
      #|  return sliced.length === 3 && sliced[0] === 2 && sliced[2] === 4;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: subarray" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([1, 2, 3, 4, 5]);
      #|  const sub = ta.subarray(1, 4);
      #|  sub[0] = 100;  // Modifies original buffer
      #|  return sub.length === 3 && ta[1] === 100;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: set" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array(5);
      #|  ta.set([10, 20, 30], 1);
      #|  return ta[0] === 0 && ta[1] === 10 && ta[2] === 20 && ta[3] === 30 && ta[4] === 0;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: copyWithin" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([1, 2, 3, 4, 5]);
      #|  ta.copyWithin(0, 3);
      #|  return ta[0] === 4 && ta[1] === 5 && ta[2] === 3;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: map" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([1, 2, 3]);
      #|  const mapped = ta.map(x => x * 2);
      #|  return mapped[0] === 2 && mapped[1] === 4 && mapped[2] === 6;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: filter" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([1, 2, 3, 4, 5]);
      #|  const filtered = ta.filter(x => x % 2 === 0);
      #|  return filtered.length === 2 && filtered[0] === 2 && filtered[1] === 4;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: reduce" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([1, 2, 3, 4, 5]);
      #|  const sum = ta.reduce((acc, x) => acc + x, 0);
      #|  return sum;
      #|}
    ),
  )
  match result {
    Number(n) => assert_eq(n, 15.0)
    _ => fail("expected Number, got \{result}")
  }
}

///|
test "TypedArray: every and some" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([2, 4, 6, 8]);
      #|  const allEven = ta.every(x => x % 2 === 0);
      #|  const hasOdd = ta.some(x => x % 2 === 1);
      #|  return allEven === true && hasOdd === false;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: find and findIndex" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([1, 2, 3, 4, 5]);
      #|  const found = ta.find(x => x > 3);
      #|  const index = ta.findIndex(x => x > 3);
      #|  return found === 4 && index === 3;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: indexOf and includes" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([1, 2, 3, 4, 5]);
      #|  return ta.indexOf(3) === 2 && ta.includes(3) && !ta.includes(10);
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: reverse" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([1, 2, 3, 4, 5]);
      #|  ta.reverse();
      #|  return ta[0] === 5 && ta[4] === 1;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: sort" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([5, 2, 8, 1, 9]);
      #|  ta.sort();
      #|  return ta[0] === 1 && ta[1] === 2 && ta[4] === 9;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "TypedArray: join" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([1, 2, 3]);
      #|  return ta.join("-");
      #|}
    ),
  )
  match result {
    String(s) => assert_eq(s, "1-2-3")
    _ => fail("expected String, got \{result}")
  }
}

///|
test "TypedArray: at" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ta = new Uint8Array([1, 2, 3, 4, 5]);
      #|  return ta.at(0) === 1 && ta.at(-1) === 5 && ta.at(-2) === 4;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "DataView: basic getters and setters" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ab = new ArrayBuffer(8);
      #|  const dv = new DataView(ab);
      #|  dv.setInt8(0, 127);
      #|  dv.setUint8(1, 255);
      #|  dv.setInt16(2, 1000, true);  // little-endian
      #|  dv.setInt32(4, 123456, true);
      #|  return dv.getInt8(0) === 127 &&
      #|         dv.getUint8(1) === 255 &&
      #|         dv.getInt16(2, true) === 1000 &&
      #|         dv.getInt32(4, true) === 123456;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "DataView: endianness" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ab = new ArrayBuffer(4);
      #|  const dv = new DataView(ab);
      #|  dv.setInt16(0, 0x1234, true);  // little-endian: 34 12
      #|  dv.setInt16(2, 0x1234, false); // big-endian: 12 34
      #|  const u8 = new Uint8Array(ab);
      #|  return u8[0] === 0x34 && u8[1] === 0x12 && u8[2] === 0x12 && u8[3] === 0x34;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}

///|
test "DataView: float values" {
  let interp = JSInterpreter::new()
  let result = interp.run(
    (
      #|function main() {
      #|  const ab = new ArrayBuffer(12);
      #|  const dv = new DataView(ab);
      #|  dv.setFloat32(0, 3.14, true);
      #|  dv.setFloat64(4, 2.718281828, true);
      #|  const f32 = dv.getFloat32(0, true);
      #|  const f64 = dv.getFloat64(4, true);
      #|  return Math.abs(f32 - 3.14) < 0.001 && Math.abs(f64 - 2.718281828) < 0.0000001;
      #|}
    ),
  )
  match result {
    Bool(b) => assert_true(b)
    _ => fail("expected Bool, got \{result}")
  }
}
