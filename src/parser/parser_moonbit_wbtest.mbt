///|
test "parser: emit MoonBit declarations from interface and declare function" {
  let src =
    #|interface Point {
    #|  x: number;
    #|  y: number;
    #|}
    #|
    #|declare function draw(point: Point, labels: string[]): void;
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let expected =
    #|///|
    #|/// Generated from TypeScript declarations by mizchi/ts/parser.
    #|/// Complex or unsupported TypeScript types are widened to JSValue.
    #|
    #|///|
    #|/// TS interface Point
    #|/// x : Double
    #|/// y : Double
    #|declare pub type Point
    #|
    #|///|
    #|declare pub fn draw(point : Point, labels : Array[String]) -> Unit
  assert_eq(actual, expected)
}

///|
test "parser: emit MoonBit declarations widens interface type parameters locally" {
  let src =
    #|interface Box<T> {
    #|  value: T;
    #|  map(value: T): T;
    #|}
    #|
    #|declare function consume(box: Box<string>): void;
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(actual.contains("/// value : JSValue"))
  assert_true(actual.contains("/// map : (JSValue) -> JSValue"))
  assert_true(actual.contains("declare pub type JSValue"))
  assert_true(actual.contains("declare pub type Box"))
  assert_true(actual.contains("declare pub fn consume(box : Box) -> Unit"))
  assert_false(actual.contains("declare pub type T"))
}

///|
test "parser: emit MoonBit declarations widens discarded function type parameters" {
  let src =
    #|declare function identity<T>(value: T): T;
    #|declare function pair<K, V>(key: K, value: V): void;
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(
    actual.contains("declare pub fn identity(value : JSValue) -> JSValue"),
  )
  assert_true(
    actual.contains(
      "declare pub fn pair(key : JSValue, value : JSValue) -> Unit",
    ),
  )
  assert_false(actual.contains("declare pub type T"))
  assert_false(actual.contains("declare pub type K"))
  assert_false(actual.contains("declare pub type V"))
}

///|
test "parser: emit MoonBit declarations widens callbacks and preserves Promise payloads" {
  let src =
    #|declare function later(
    #|  callback: (value: number) => void,
    #|  promise: Promise<string>,
    #|): Promise<number>;
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let expected =
    #|///|
    #|/// Generated from TypeScript declarations by mizchi/ts/parser.
    #|/// Complex or unsupported TypeScript types are widened to JSValue.
    #|
    #|///|
    #|declare pub type JSValue
    #|
    #|///|
    #|declare pub fn later(callback : JSValue, promise : @js.Promise[String]) -> @js.Promise[Double]
  assert_eq(actual, expected)
}

///|
test "parser: emit MoonBit declarations collapses named option intersections" {
  let src =
    #|interface StatOptions {
    #|  bigint?: boolean;
    #|}
    #|declare function stat(
    #|  path: string,
    #|  options?: StatOptions & { bigint?: false | undefined },
    #|): void;
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(actual.contains("declare pub type StatOptions"))
  assert_true(
    actual.contains(
      "declare pub fn stat(path : String, options : StatOptions?) -> Unit",
    ),
  )
  assert_false(actual.contains("options : JSValue"))
}

///|
test "parser: emit MoonBit declarations preserves optional complex unions when widened" {
  let src =
    #|interface StringParams {
    #|  message?: string;
    #|}
    #|declare function string(params?: string | StringParams): Schema;
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(actual.contains("declare pub type JSValue"))
  assert_true(
    actual.contains("declare pub fn string(params : JSValue?) -> Schema"),
  )
  assert_false(actual.contains("params : JSValue)"))
}

///|
test "parser: emit MoonBit declarations sanitizes parameter names" {
  let src = "declare function useKeywords(in: string, type: number): void;"
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(
    actual.contains(
      "declare pub fn useKeywords(in_ : String, type_ : Double) -> Unit",
    ),
  )
}

///|
test "parser: emit MoonBit declarations sanitizes future reserved parameter names" {
  let src =
    #|interface RuntimeOptions {
    #|  override: boolean;
    #|  method: string;
    #|}
    #|declare function move(constructor: unknown): void;
    #|declare function final(): void;
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(actual.contains("/// override : Bool"))
  assert_true(actual.contains("/// method : String"))
  assert_true(
    actual.contains("declare pub fn move_(constructor_ : JSValue) -> Unit"),
  )
  assert_true(actual.contains("declare pub fn final_() -> Unit"))
}

///|
test "parser: emit MoonBit declarations for ambient enum" {
  let src =
    #|declare enum Mode {
    #|  Read = "read",
    #|  Write = "write",
    #|}
    #|declare function setMode(mode: Mode): Mode;
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(actual.contains("pub(all) enum Mode {"))
  assert_true(actual.contains("  Read"))
  assert_true(actual.contains("  Write"))
  assert_true(actual.contains("declare pub fn setMode(mode : Mode) -> Mode"))
  assert_false(actual.contains("declare pub type Mode"))
}

///|
test "parser: emit MoonBit declaration type names with leading underscores" {
  let src = "interface _ZodType { value: string; }"
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(actual.contains("declare pub type UnderscoreZodType"))
}

///|
test "parser: emit MoonBit declarations keeps generic intersections with empty object opaque" {
  let src =
    #|declare function isPast(date: DateArg<Date> & {}): boolean;
    #|declare function isEqual(leftDate: DateArg<Date> & {}, rightDate: DateArg<Date> & {}): boolean;
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(actual.contains("declare pub type DateArg"))
  assert_true(actual.contains("declare pub fn isPast(date : DateArg) -> Bool"))
  assert_true(
    actual.contains(
      "declare pub fn isEqual(leftDate : DateArg, rightDate : DateArg) -> Bool",
    ),
  )
  assert_false(actual.contains("date : JSValue"))
}
