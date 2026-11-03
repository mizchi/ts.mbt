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
