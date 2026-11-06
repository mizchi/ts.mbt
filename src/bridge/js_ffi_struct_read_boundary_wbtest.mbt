///|
test "struct read pass: returns of a listed struct go through its converter" {
  let src =
    #|pub extern "js" fn Program::diagnostics(self : Program) -> FixedArray[Diagnostic] =
    #|  #| (self) => self.getDiagnostics()
    #|
    #|pub extern "js" fn first(xs : JSValue) -> Diagnostic? = "__ts_mbt_first"
    #|
    #|pub extern "js" fn plain(x : String) -> Diagnostic = "__ts_mbt_plain"
    #|
    #|pub extern "js" fn other(x : String) -> String = "__ts_mbt_other"
    #|
    #|// __ts_mbt_read_structs: Diagnostic Unused
  let out = migrate_js_ffi_struct_reads(src)
  // The marker is consumed.
  assert_false(out.contains("__ts_mbt_read_structs"))
  // A FixedArray return maps each element through the converter; the JS
  // body stays on the now-private extern.
  assert_true(
    out.contains(
      "extern \"js\" fn __ts_mbt_rs_Program__diagnostics(receiver : Program) -> FixedArray[Diagnostic] =\n  #| (self) => self.getDiagnostics()",
    ),
  )
  assert_true(
    out.contains(
      "pub fn Program::diagnostics(self : Program) -> FixedArray[Diagnostic] {\n  __ts_mbt_rs_Program__diagnostics(self).map(fn(r0) { __ts_mbt_read_cast(__ts_mbt_read_struct__Diagnostic(__ts_mbt_read_cast(r0))) })\n}",
    ),
  )
  // Optional and bare returns.
  assert_true(
    out.contains(
      "pub fn first(xs : JSValue) -> Diagnostic? {\n  __ts_mbt_rs_first(xs).map(fn(r0) {",
    ),
  )
  assert_true(
    out.contains(
      "pub fn plain(x : String) -> Diagnostic {\n  __ts_mbt_read_cast(__ts_mbt_read_struct__Diagnostic(__ts_mbt_read_cast(__ts_mbt_rs_plain(x))))\n}",
    ),
  )
  // A return that holds no listed struct is left exactly as written.
  assert_true(
    out.contains(
      "pub extern \"js\" fn other(x : String) -> String = \"__ts_mbt_other\"",
    ),
  )
  // One helper per struct a wrapper USED: `Unused` is listed and gets none.
  assert_eq(out.split("fn __ts_mbt_read_struct__Diagnostic(").count(), 2)
  assert_false(out.contains("__ts_mbt_read_struct__Unused"))
  assert_true(
    out.contains(
      "extern \"js\" fn __ts_mbt_read_struct__Diagnostic(value : TsMbtStructRef) -> TsMbtStructRef = \"__ts_mbt_read_struct_diagnostic\"",
    ),
  )
  assert_eq(out.split("fn[A, B] __ts_mbt_read_cast(").count(), 2)
}

///|
test "struct read pass: a Promise return converts through Promise::map" {
  let src =
    #|pub fn[T, U] Promise::map(self : Promise[T], f : (T) -> U) -> Promise[U] {
    #|  unsafeCast(_promise_map_extern_js(unsafeCast(self), unsafeCast(f)))
    #|}
    #|
    #|pub extern "js" fn load() -> Promise[Diagnostic] = "__ts_mbt_load"
    #|
    #|// __ts_mbt_read_structs: Diagnostic
  let out = migrate_js_ffi_struct_reads(src)
  assert_true(
    out.contains(
      "pub fn load() -> Promise[Diagnostic] {\n  __ts_mbt_rs_load().map(fn(r0) { __ts_mbt_read_cast(__ts_mbt_read_struct__Diagnostic(__ts_mbt_read_cast(r0))) })\n}",
    ),
  )
}

///|
test "struct read pass: no marker, no change" {
  let src =
    #|pub extern "js" fn plain(x : String) -> Diagnostic = "__ts_mbt_plain"
  assert_eq(migrate_js_ffi_struct_reads(src), src)
}
