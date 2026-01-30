///|
fn JSInterpreter::call_iterator_native(
  self : JSInterpreter,
  name : String,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue? {
  match name {
    "Iterator.prototype[@@iterator]" => Some(this_arg)
    "Iterator.from" => Some(self.iterator_from(this_arg, args))
    "Iterator.prototype.map" => Some(self.iterator_map(this_arg, args))
    "Iterator.prototype.filter" => Some(self.iterator_filter(this_arg, args))
    "Iterator.prototype.take" => Some(self.iterator_take(this_arg, args))
    "Iterator.prototype.drop" => Some(self.iterator_drop(this_arg, args))
    "Iterator.prototype.flatMap" => Some(self.iterator_flat_map(this_arg, args))
    "Iterator.prototype.forEach" =>
      Some(self.iterator_for_each(this_arg, args))
    "Iterator.prototype.toArray" =>
      Some(self.iterator_to_array(this_arg, args))
    "Iterator.prototype.reduce" => Some(self.iterator_reduce(this_arg, args))
    "Iterator.prototype.every" => Some(self.iterator_every(this_arg, args))
    "Iterator.prototype.some" => Some(self.iterator_some(this_arg, args))
    "Iterator.prototype.find" => Some(self.iterator_find(this_arg, args))
    "IteratorHelper.prototype.next" =>
      Some(self.iterator_helper_next(this_arg, args))
    "IteratorHelper.prototype.return" =>
      Some(self.iterator_helper_return(this_arg, args))
    "IteratorHelper.prototype.throw" =>
      Some(self.iterator_helper_throw(this_arg, args))
    "ArrayIterator.prototype.next" =>
      Some(self.array_iterator_next(this_arg))
    "StringIterator.prototype.next" =>
      Some(self.string_iterator_next(this_arg))
    "Generator.prototype.next" =>
      Some(self.generator_prototype_next(this_arg, args))
    "Generator.prototype.return" =>
      Some(self.generator_prototype_return(this_arg, args))
    "Generator.prototype.throw" =>
      Some(self.generator_prototype_throw(this_arg, args))
    "MapIterator.next" => Some(self.map_iterator_next(this_arg))
    "SetIterator.next" => Some(self.set_iterator_next(this_arg))
    "Iterator.self" => Some(this_arg)
    _ => None
  }
}

///|
fn JSInterpreter::array_iterator_next(
  self : JSInterpreter,
  this_arg : JSValue,
) -> JSValue {
  let target = js_get_prop(this_arg, "__iter_target")
  let idx_val = js_get_prop(this_arg, "__iter_index")
  let idx = idx_val.to_number().to_int()
  let len = self.array_like_length(target)
  if idx >= len {
    let _ = js_set_prop(this_arg, "__iter_index", Number(len.to_double()))
    self.make_iter_result(Undefined, true)
  } else {
    let value = self.get_prop_value(target, idx.to_string())
    let _ = js_set_prop(
      this_arg,
      "__iter_index",
      Number((idx + 1).to_double()),
    )
    self.make_iter_result(value, false)
  }
}

///|
fn JSInterpreter::string_iterator_next(
  self : JSInterpreter,
  this_arg : JSValue,
) -> JSValue {
  let str_val = js_get_prop(this_arg, "__iter_string")
  let s = match str_val {
    String(value) => value
    _ => ""
  }
  let idx_val = js_get_prop(this_arg, "__iter_index")
  let idx = idx_val.to_number().to_int()
  if idx >= s.length() {
    let _ = js_set_prop(
      this_arg,
      "__iter_index",
      Number(s.length().to_double()),
    )
    self.make_iter_result(Undefined, true)
  } else {
    let cu1 = s[idx]
    let (next_idx, chunk) = if cu1.is_leading_surrogate() &&
      idx + 1 < s.length() {
      let cu2 = s[idx + 1]
      if cu2.is_trailing_surrogate() {
        let str = s[idx:idx + 2].to_string() catch { _ => "" }
        (idx + 2, str)
      } else {
        let str = s[idx:idx + 1].to_string() catch { _ => "" }
        (idx + 1, str)
      }
    } else {
      let str = s[idx:idx + 1].to_string() catch { _ => "" }
      (idx + 1, str)
    }
    let _ = js_set_prop(
      this_arg,
      "__iter_index",
      Number(next_idx.to_double()),
    )
    self.make_iter_result(JSValue::String(chunk), false)
  }
}

///|
fn JSInterpreter::generator_prototype_next(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match self.get_generator_id(this_arg) {
    Some(gen_id) => {
      let sent = if args.length() > 0 { args[0] } else { Undefined }
      let result = self.generator_next(gen_id, sent)
      // For async generators, wrap result in a Promise
      match js_get_prop(this_arg, "__is_async") {
        Bool(true) => {
          let promise_ctor = self.global_env.get("Promise")
          self.promise_static_resolve_with_ctor(promise_ctor, result)
        }
        _ => result
      }
    }
    None =>
      self.set_error_kind(
        "TypeError",
        "Generator.prototype.next called on non-generator",
      )
  }
}

///|
fn JSInterpreter::generator_prototype_return(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match self.get_generator_id(this_arg) {
    Some(gen_id) => {
      let sent = if args.length() > 0 { args[0] } else { Undefined }
      let result = self.generator_return(gen_id, sent)
      // For async generators, wrap result in a Promise
      match js_get_prop(this_arg, "__is_async") {
        Bool(true) => {
          let promise_ctor = self.global_env.get("Promise")
          self.promise_static_resolve_with_ctor(promise_ctor, result)
        }
        _ => result
      }
    }
    None =>
      self.set_error_kind(
        "TypeError",
        "Generator.prototype.return called on non-generator",
      )
  }
}

///|
fn JSInterpreter::generator_prototype_throw(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match self.get_generator_id(this_arg) {
    Some(gen_id) => {
      let sent = if args.length() > 0 { args[0] } else { Undefined }
      let result = self.generator_throw(gen_id, sent)
      // For async generators, wrap result in a Promise
      match js_get_prop(this_arg, "__is_async") {
        Bool(true) => {
          let promise_ctor = self.global_env.get("Promise")
          self.promise_static_resolve_with_ctor(promise_ctor, result)
        }
        _ => result
      }
    }
    None =>
      self.set_error_kind(
        "TypeError",
        "Generator.prototype.throw called on non-generator",
      )
  }
}

///|
fn JSInterpreter::map_iterator_next(
  self : JSInterpreter,
  this_arg : JSValue,
) -> JSValue {
  let map_ref = js_get_prop(this_arg, "__map_ref")
  let index_val = js_get_prop(this_arg, "__iter_index")
  let kind_val = js_get_prop(this_arg, "__iter_kind")
  match (js_get_prop(map_ref, "__map_entries"), index_val, kind_val) {
    (JSValue::Array(arr), Number(index), String(kind)) => {
      let idx = index.to_int()
      if idx >= arr.length {
        let result = self.new_object()
        let _ = js_set_prop(result, "done", Bool(true))
        let _ = js_set_prop(result, "value", Undefined)
        result
      } else {
        let _ = js_set_prop(this_arg, "__iter_index", Number(index + 1.0))
        let entry = arr.items[idx]
        let value = match (entry, kind) {
          (JSValue::Array(pair), "key") if pair.length >= 2 => pair.items[0]
          (JSValue::Array(pair), "value") if pair.length >= 2 => pair.items[1]
          (JSValue::Array(pair), _) if pair.length >= 2 => {
            let result = js_new_array()
            let _ = js_array_push(result, pair.items[0])
            let _ = js_array_push(result, pair.items[1])
            result
          }
          _ => Undefined
        }
        let result = self.new_object()
        let _ = js_set_prop(result, "done", Bool(false))
        let _ = js_set_prop(result, "value", value)
        result
      }
    }
    _ => {
      let result = self.new_object()
      let _ = js_set_prop(result, "done", Bool(true))
      let _ = js_set_prop(result, "value", Undefined)
      result
    }
  }
}

///|
fn JSInterpreter::set_iterator_next(
  self : JSInterpreter,
  this_arg : JSValue,
) -> JSValue {
  let set_ref = js_get_prop(this_arg, "__set_ref")
  let index_val = js_get_prop(this_arg, "__iter_index")
  let kind_val = js_get_prop(this_arg, "__iter_kind")
  match (js_get_prop(set_ref, "__set_entries"), index_val, kind_val) {
    (JSValue::Array(arr), Number(index), String(kind)) => {
      let idx = index.to_int()
      if idx >= arr.length {
        let result = self.new_object()
        let _ = js_set_prop(result, "done", Bool(true))
        let _ = js_set_prop(result, "value", Undefined)
        result
      } else {
        let _ = js_set_prop(this_arg, "__iter_index", Number(index + 1.0))
        let entry = arr.items[idx]
        let value = match kind {
          "entry" => {
            let result = js_new_array()
            let _ = js_array_push(result, entry)
            let _ = js_array_push(result, entry)
            result
          }
          _ => entry
        }
        let result = self.new_object()
        let _ = js_set_prop(result, "done", Bool(false))
        let _ = js_set_prop(result, "value", value)
        result
      }
    }
    _ => {
      let result = self.new_object()
      let _ = js_set_prop(result, "done", Bool(true))
      let _ = js_set_prop(result, "value", Undefined)
      result
    }
  }
}
