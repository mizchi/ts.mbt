///|
test "js ffi array boundary: param, return, optional and nested arrays get a FixedArray extern and a wrapper" {
  let src =
    #|#module("@tsmbt-bridge/dist")
    #|pub extern "js" fn WebSocketHandlers::getFiles(self : WebSocketHandlers) -> Array[File] =
    #|  #| (self) => self.getFiles()
    #|
    #|extern "js" fn pairs(keys : Array[String], values : Array[JSValue]?) -> JSValue = "__ts_mbt_pairs"
    #|
    #|pub extern "js" fn[T] grid(rows : Array[Array[T]]) -> Array[Array[T]]? =
    #|  #| (rows) => rows
  inspect(
    migrate_js_ffi_array_boundaries(src),
    content=(
      #|#module("@tsmbt-bridge/dist")
      #|extern "js" fn __ts_mbt_ffi_WebSocketHandlers__getFiles(receiver : WebSocketHandlers) -> FixedArray[File] =
      #|  #| (self) => self.getFiles()
      #|
      #|pub fn WebSocketHandlers::getFiles(self : WebSocketHandlers) -> Array[File] {
      #|  Array::from_fixed_array(__ts_mbt_ffi_WebSocketHandlers__getFiles(self))
      #|}
      #|
      #|extern "js" fn __ts_mbt_ffi_pairs(keys : FixedArray[String], values : FixedArray[JSValue]?) -> JSValue = "__ts_mbt_pairs"
      #|
      #|fn pairs(keys : Array[String], values : Array[JSValue]?) -> JSValue {
      #|  __ts_mbt_ffi_pairs(FixedArray::from_array(keys), values.map(fn(v0) { FixedArray::from_array(v0) }))
      #|}
      #|
      #|extern "js" fn[T] __ts_mbt_ffi_grid(rows : FixedArray[FixedArray[T]]) -> FixedArray[FixedArray[T]]? =
      #|  #| (rows) => rows
      #|
      #|pub fn[T] grid(rows : Array[Array[T]]) -> Array[Array[T]]? {
      #|  __ts_mbt_ffi_grid(FixedArray::from_array(rows.map(fn(v0) { FixedArray::from_array(v0) }))).map(fn(v0) { Array::from_fixed_array(v0).map(fn(v1) { Array::from_fixed_array(v1) }) })
      #|}
    ),
  )
}

///|
test "js ffi array boundary: shapes with no boundary conversion are left alone" {
  let src =
    #|pub extern "js" fn run(self : Provider) -> Promise[Array[Result]] =
    #|  #| (self) => self.run()
    #|
    #|pub extern "js" fn on(cb : (String) -> Bool) -> Unit = "on"
    #|
    #|pub extern "js" fn on_err(cb : (Array[String]) -> Unit raise) -> Unit = "on_err"
    #|
    #|pub extern "js" fn plain(x : String?) -> FixedArray[Int] = "plain"
    #|
    #|#alias("_[_]")
    #|pub extern "js" fn Bag::get(self : Bag, i : Int) -> Array[Int] = "get"
    #|
    #|fn not_an_extern(x : Array[Int]) -> Array[Int] { x }
  inspect(migrate_js_ffi_array_boundaries(src) == src, content="true")
}

///|
test "js ffi array boundary: Promise[Array] converts through the package's Promise::map" {
  let src =
    #|pub fn[T, U] Promise::map(self : Promise[T], f : (T) -> U) -> Promise[U] {
    #|  unsafeCast(_promise_map_extern_js(unsafeCast(self), unsafeCast(f)))
    #|}
    #|
    #|pub extern "js" fn BenchmarkProvider::run(self : BenchmarkProvider, arg0 : BenchmarkGroup) -> Promise[Array[BenchResult]] =
    #|  #| (self, arg0) => self.run(arg0)
  inspect(
    migrate_js_ffi_array_boundaries(src),
    content=(
      #|pub fn[T, U] Promise::map(self : Promise[T], f : (T) -> U) -> Promise[U] {
      #|  unsafeCast(_promise_map_extern_js(unsafeCast(self), unsafeCast(f)))
      #|}
      #|
      #|extern "js" fn __ts_mbt_ffi_BenchmarkProvider__run(receiver : BenchmarkProvider, arg0 : BenchmarkGroup) -> Promise[FixedArray[BenchResult]] =
      #|  #| (self, arg0) => self.run(arg0)
      #|
      #|pub fn BenchmarkProvider::run(self : BenchmarkProvider, arg0 : BenchmarkGroup) -> Promise[Array[BenchResult]] {
      #|  __ts_mbt_ffi_BenchmarkProvider__run(self, arg0).map(fn(v0) { Array::from_fixed_array(v0) })
      #|}
    ),
  )
}

///|
test "js ffi array boundary: a callback converts through one memoized wrapper" {
  // A wrapper made per call would break `off(cb)`, which finds a listener
  // by function identity, so both directions go through
  // `__ts_mbt_cb_memo`, and the helpers are emitted once per package.
  let src =
    #|pub extern "js" fn Server::off(self : Server, arg0 : String, arg1 : (Array[String]) -> Unit) -> Server =
    #|  #| (self, arg0, arg1) => self.off(arg0, arg1)
    #|
    #|pub extern "js" fn get_tags() -> (Array[String]) -> Bool = "__ts_mbt_get_tags"
  let out = migrate_js_ffi_array_boundaries(src)
  assert_true(
    out.contains(
      "pub fn Server::off(self : Server, arg0 : String, arg1 : (Array[String]) -> Unit) -> Server {\n  __ts_mbt_ffi_Server__off(self, arg0, { let f0 = arg1; __ts_mbt_cb_cast(__ts_mbt_cb_memo(__ts_mbt_cb_cast(f0), fn() { __ts_mbt_cb_cast(fn(a0_0 : FixedArray[String]) -> Unit { f0(Array::from_fixed_array(a0_0)) }) })) })\n}",
    ),
  )
  // The returned JS function is wrapped the other way: MoonBit calls it
  // with an `Array`, and it hands JS a `FixedArray`.
  assert_true(
    out.contains(
      "{ let f0 = __ts_mbt_ffi_get_tags(); __ts_mbt_cb_cast(__ts_mbt_cb_memo(__ts_mbt_cb_cast(f0), fn() { __ts_mbt_cb_cast(fn(a0_0 : Array[String]) -> Bool { f0(FixedArray::from_array(a0_0)) }) })) }",
    ),
  )
  // Helpers once, even with two converted callbacks.
  assert_eq(out.split("fn __ts_mbt_cb_memo(").count(), 2)
}

///|
test "js ffi array boundary: a function returning an optional is not an optional callback" {
  // `(A) -> B?` returns `B?`; `((A) -> B)?` is an optional callback.
  let src =
    #|pub extern "js" fn get_pick() -> (String) -> Array[String]? = "__ts_mbt_get_pick"
    #|
    #|pub extern "js" fn get_cb() -> ((Array[String]) -> Unit)? = "__ts_mbt_get_cb"
  let out = migrate_js_ffi_array_boundaries(src)
  assert_true(
    out.contains(
      "extern \"js\" fn __ts_mbt_ffi_get_pick() -> (String) -> FixedArray[String]? = \"__ts_mbt_get_pick\"",
    ),
  )
  assert_true(
    out.contains(
      "extern \"js\" fn __ts_mbt_ffi_get_cb() -> ((FixedArray[String]) -> Unit)? = \"__ts_mbt_get_cb\"",
    ),
  )
  assert_true(out.contains("__ts_mbt_ffi_get_cb().map(fn(v0) {"))
}

///|
test "js ffi array boundary: a declared generic's Array argument becomes FixedArray" {
  let decls =
    #|pub(all) struct ReadVResult[T] {
    #|  buffers : FixedArray[NodeJS_ArrayBufferView]
    #|}
    #|pub(all) struct Box[T] {
    #|  v : T
    #|}
    #|#external
    #|pub type Promise[T]
  let text =
    #|/// 非 ASCII の doc がずれないこと
    #|pub fn readv() -> Promise[ReadVResult[Array[NodeJS_ArrayBufferView]]] {
    #|pub fn nested() -> Box[ReadVResult[Array[Int]]]
    #|pub fn untouched(a : Promise[Array[Int]], b : NodeArray[Array[Int]], c : MyBox[Array[Int]]) -> Map[String, Array[Int]]
  inspect(
    migrate_generic_type_arg_arrays(text, decls),
    content=(
      #|/// 非 ASCII の doc がずれないこと
      #|pub fn readv() -> Promise[ReadVResult[FixedArray[NodeJS_ArrayBufferView]]] {
      #|pub fn nested() -> Box[ReadVResult[FixedArray[Int]]]
      #|pub fn untouched(a : Promise[Array[Int]], b : NodeArray[Array[Int]], c : MyBox[Array[Int]]) -> Map[String, Array[Int]]
    ),
  )
}
