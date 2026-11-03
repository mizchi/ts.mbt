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
    #|pub extern "js" fn on(cb : (Array[String]) -> Bool) -> Unit = "on"
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
test "js ffi array boundary: a callback is never wrapped, in either direction" {
  // Wrapping would hand JS a new function per call, and `off(cb)` finds a
  // listener by identity. `(A) -> B?` is a function returning `B?`, not an
  // optional callback, and must not be read as one.
  let src =
    #|pub fn[T, U] Promise::map(self : Promise[T], f : (T) -> U) -> Promise[U] { abort("") }
    #|
    #|pub extern "js" fn Server::off(self : Server, arg0 : String, arg1 : (Array[String]) -> Unit) -> Server =
    #|  #| (self, arg0, arg1) => self.off(arg0, arg1)
    #|
    #|pub extern "js" fn get_tags() -> (Array[String]) -> Bool = "__ts_mbt_get_tags"
    #|
    #|pub extern "js" fn get_pick() -> (String) -> Array[String]? = "__ts_mbt_get_pick"
    #|
    #|pub extern "js" fn get_cb() -> ((Array[String]) -> Unit)? = "__ts_mbt_get_cb"
    #|
    #|pub extern "js" fn read() -> Promise[ReadResult[Array[Buffer]]] = "__ts_mbt_read"
  inspect(migrate_js_ffi_array_boundaries(src) == src, content="true")
}
