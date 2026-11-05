///|
pub suberror LoadError {
  MissingKey(String)
}

///|
pub(all) struct CallbackBox[T] {
  current : T
  on_change : ((T) -> Unit)?
  meta : Map[String, Array[Bool]]
}

///|
pub fn[T] CallbackBox::tap(
  self : Self[T],
  effect : (Self[T]) -> Unit,
) -> Self[T] {
  effect(self)
  self
}

///|
pub fn[T, U] CallbackBox::map(
  self : Self[T],
  mapper : (T) -> U,
) -> CallbackBox[U] {
  { current: mapper(self.current), on_change: None, meta: self.meta, }
}

///|
pub enum Status {
  Ready(Int32)
  Failed(LoadError)
}

///|
pub fn ready(count : Int32) -> Status {
  Ready(count)
}

///|
pub fn failed(key : String) -> Status {
  Failed(LoadError::MissingKey(key))
}

///|
pub type Task[T] = async () -> Result[T, LoadError]

///|
pub type MaybeHandler[T] = ((T) -> Unit)?

///|
pub fn make_string_box(value : String) -> CallbackBox[String] {
  { current: value, on_change: None, meta: Map::new(), }
}

///|
pub fn consume_callbacks(
  handler : (String, Int32) -> Unit,
  on_error? : (LoadError) -> Unit,
  required : FixedArray[String],
) -> Unit {
  handler("required", required.length())
  match on_error {
    Some(callback) => callback(LoadError::MissingKey("optional"))
    None => ()
  }
}

///|
#warnings("-unused_async")
pub async fn load_all(
  keys : FixedArray[String],
) -> Result[Array[(String, Int32)], LoadError] raise LoadError {
  if keys.length() == 0 {
    raise LoadError::MissingKey("keys")
  }
  Ok(Array::from_fixed_array(keys).map(fn(key) { (key, key.length()) }))
}

///|
pub fn borrow_bytes(data : BytesView) -> Bytes {
  data.to_bytes()
}

///|
pub fn update_ref(
  state : Ref[FixedArray[Int64]],
  next : ArrayView[UInt64],
) -> Set[String] {
  state.val = FixedArray::from_array(
    next.map(fn(value) { value.reinterpret_as_int64() }),
  )
  Set::from_array(["updated", state.val.length().to_string()])
}
