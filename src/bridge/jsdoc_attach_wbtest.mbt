///|
test "jsdoc attach: items, methods, struct fields and keyword names" {
  let docs : Map[String, Array[String]] = Map([
    ("Options", ["Options for the client."]),
    ("Options.baseUrl", ["Base URL.", "", "Deprecated."]),
    ("Options.method", ["Keyword-named member."]),
    ("nanoid", ["Make an id."]),
    ("Client.send", ["Send it."]),
    ("extend", ["Keyword-named function."]),
  ])
  let src =
    #|#warnings("-9")
    #|pub(all) struct Options {
    #|  baseUrl : String
    #|  method_ : String
    #|  other : Bool
    #|}
    #|
    #|#module("@tsmbt-bridge/out")
    #|pub extern "js" fn nanoid(size : Double?) -> String = "__ts_mbt_nanoid"
    #|
    #|pub fn Client::send(self : Client, body : String) -> Unit {
    #|  ()
    #|}
    #|
    #|pub extern "js" fn extend_(x : Options) -> Options = "__ts_mbt_extend"
  inspect(
    attach_jsdoc_to_bridge_mbt(src, docs),
    content=(
      #|/// Options for the client.
      #|#warnings("-9")
      #|pub(all) struct Options {
      #|  /// Base URL.
      #|  ///
      #|  /// Deprecated.
      #|  baseUrl : String
      #|  /// Keyword-named member.
      #|  method_ : String
      #|  other : Bool
      #|}
      #|
      #|/// Make an id.
      #|#module("@tsmbt-bridge/out")
      #|pub extern "js" fn nanoid(size : Double?) -> String = "__ts_mbt_nanoid"
      #|
      #|/// Send it.
      #|pub fn Client::send(self : Client, body : String) -> Unit {
      #|  ()
      #|}
      #|
      #|/// Keyword-named function.
      #|pub extern "js" fn extend_(x : Options) -> Options = "__ts_mbt_extend"
    ),
  )
}

///|
test "jsdoc attach: a renamed item gets no doc rather than a wrong one" {
  // `pick_number` is an overload variant of `pick` and `get_size` a getter
  // for `size`: neither name maps back, so neither borrows a doc. A private
  // extern is never documented.
  let docs : Map[String, Array[String]] = Map([
    ("pick", ["First overload."]),
    ("size", ["The size."]),
    ("__ts_mbt_ffi_pick", ["Never attached."]),
  ])
  let src =
    #|pub fn pick_number(a : Double) -> Double = "pick"
    #|
    #|pub fn get_size() -> Double = "size"
    #|
    #|extern "js" fn __ts_mbt_ffi_pick(a : String) -> String = "pick"
  inspect(attach_jsdoc_to_bridge_mbt(src, docs) == src, content="true")
}

///|
test "jsdoc attach: class member aliases follow the generator's names" {
  let docs : Map[String, Array[String]] = Map([
    ("HttpClient.constructor", ["Create one."]),
    ("HttpClient.baseUrl", ["The base URL."]),
    ("HttpClient.create", ["A factory."]),
    // A real declaration that happens to share an alias's spelling keeps
    // its own doc.
    ("http_client_create", ["A real top-level function."]),
  ])
  jsdoc_add_member_aliases(docs)
  assert_eq(docs.get("new_http_client"), Some(["Create one."]))
  assert_eq(
    docs.get("HttpClient.get_http_client_base_url"),
    Some(["The base URL."]),
  )
  assert_eq(
    docs.get("HttpClient.set_http_client_base_url"),
    Some(["The base URL."]),
  )
  assert_eq(
    docs.get("http_client_create"),
    Some(["A real top-level function."]),
  )
}
