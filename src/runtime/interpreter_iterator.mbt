///|
// / iterator helpers
fn JSInterpreter::get_iterator_ctor(self : JSInterpreter, this_arg : JSValue) -> JSValue {
  if self.is_constructor(this_arg) {
    return this_arg
  }
  self.global_env.get("Iterator")
}

///|
fn JSInterpreter::get_iterator_helper_proto(self : JSInterpreter, ctor : JSValue) -> JSValue {
  let proto = js_get_prop(ctor, "__helper_proto")
  match proto {
    Object(_) | Function(_) | Array(_) => proto
    _ => {
      let fallback_ctor = self.global_env.get("Iterator")
      let fallback = js_get_prop(fallback_ctor, "__helper_proto")
      match fallback {
        Object(_) | Function(_) | Array(_) => fallback
        _ => self.object_proto
      }
    }
  }
}

///|
fn JSInterpreter::error_or_undefined(self : JSInterpreter) -> JSValue {
  match self.peek_error() {
    Some(err) => err
    None => Undefined
  }
}

///|
///|
fn JSInterpreter::new_iterator_helper(
  self : JSInterpreter,
  ctor : JSValue,
  source : JSValue,
  kind : String,
) -> JSValue {
  let helper = self.new_object()
  let _ = js_set_prop(helper, "__iter_kind", String(kind))
  let _ = js_set_prop(helper, "__iter_source", source)
  let _ = js_set_prop(helper, "__iter_done", Bool(false))
  let helper_proto = self.get_iterator_helper_proto(ctor)
  let _ = js_set_prop(helper, "__proto__", helper_proto)
  helper
}

///|
fn JSInterpreter::ensure_iterator_object_with_next(
  self : JSInterpreter,
  value : JSValue,
) -> (JSValue, JSValue)? {
  match value {
    Object(_) | Function(_) | Array(_) => ()
    _ => {
      let _ = self.set_error_kind("TypeError", "Iterator helper called on non-object")
      return None
    }
  }
  let next = self.get_prop_value(value, "next")
  match self.peek_error() {
    Some(_) => return None
    None => ()
  }
  if self.is_callable(next) {
    return Some((value, next))
  }
  let iter_method = self.get_prop_value(value, "@@iterator")
  match self.peek_error() {
    Some(_) => return None
    None => ()
  }
  match iter_method {
    Undefined | Null => {
      let _ = self.set_error_kind("TypeError", "Iterator @@iterator is not callable")
      return None
    }
    _ => ()
  }
  if not(self.is_callable(iter_method)) {
    let _ = self.set_error_kind("TypeError", "Iterator @@iterator is not callable")
    return None
  }
  let iterator = self.call_function(iter_method, value, [])
  match self.peek_error() {
    Some(_) => return None
    None => ()
  }
  match iterator {
    Object(_) | Function(_) | Array(_) => ()
    _ => {
      let _ = self.set_error_kind("TypeError", "Iterator result is not an object")
      return None
    }
  }
  let next_method = self.get_prop_value(iterator, "next")
  match self.peek_error() {
    Some(_) => return None
    None => ()
  }
  if not(self.is_callable(next_method)) {
    let _ = self.set_error_kind("TypeError", "Iterator next is not callable")
    return None
  }
  Some((iterator, next_method))
}

///|
fn JSInterpreter::iterator_next_object(self : JSInterpreter, iterator : JSValue) -> JSValue? {
  let result = self.call_method(iterator, "next", [])
  match self.peek_error() {
    Some(_) => return None
    None => ()
  }
  match result {
    Object(_) | Function(_) | Array(_) => Some(result)
    _ => {
      let _ = self.set_error_kind("TypeError", "Iterator result is not an object")
      None
    }
  }
}

///|
fn JSInterpreter::iterator_next_object_with(
  self : JSInterpreter,
  iterator : JSValue,
  next_method : JSValue,
) -> JSValue? {
  let result = self.call_function(next_method, iterator, [])
  match self.peek_error() {
    Some(_) => return None
    None => ()
  }
  match result {
    Object(_) | Function(_) | Array(_) => Some(result)
    _ => {
      let _ = self.set_error_kind("TypeError", "Iterator result is not an object")
      None
    }
  }
}

///|
fn JSInterpreter::to_iterator_limit(self : JSInterpreter, value : JSValue) -> Int? {
  match value {
    String(s) =>
      if s.has_prefix("Symbol(") {
        let _ = self.set_error_kind("TypeError", "Cannot convert Symbol to number")
        return None
      }
    Object(_) | Function(_) | Array(_) => {
      let class_tag = js_get_prop(value, "__class")
      match class_tag {
        String("BigInt") => {
          let _ = self.set_error_kind("TypeError", "Cannot convert BigInt to number")
          return None
        }
        _ => ()
      }
      if js_has_prop(value, "@@toPrimitive") {
        let _ = self.set_error_kind("TypeError", "Cannot convert object to number")
        return None
      }
    }
    _ => ()
  }
  let num = value.to_number()
  if num.is_nan() {
    let _ = self.set_error_kind("RangeError", "Iterator limit must be a non-negative integer")
    return None
  }
  let truncated =
    if num >= 0.0 {
      @math.floor(num)
    } else {
      @math.ceil(num)
    }
  if truncated < 0.0 {
    let _ = self.set_error_kind("RangeError", "Iterator limit must be a non-negative integer")
    return None
  }
  Some(truncated.to_int())
}

///|
pub fn JSInterpreter::iterator_from(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let input = if args.length() > 0 { args[0] } else { Undefined }
  match input {
    Undefined | Null =>
      return self.set_error_kind("TypeError", "Iterator.from called on null or undefined")
    _ => ()
  }
  match input {
    Object(_) | Function(_) | Array(_) => ()
    _ =>
      return self.set_error_kind("TypeError", "Iterator.from called on non-object")
  }
  let ctor = self.get_iterator_ctor(this_arg)
  let iter_method = self.get_prop_value(input, "@@iterator")
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  let mut iterator = input
  match iter_method {
    Undefined | Null => ()
    _ => {
      if not(self.is_callable(iter_method)) {
        return self.set_error_kind("TypeError", "Iterator.from @@iterator is not callable")
      }
      iterator = self.call_function(iter_method, input, [])
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
    }
  }
  match iterator {
    Object(_) | Function(_) | Array(_) => ()
    _ =>
      return self.set_error_kind("TypeError", "Iterator.from result is not an object")
  }
  let next_method = self.get_prop_value(iterator, "next")
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  if not(self.is_callable(next_method)) {
    return self.set_error_kind("TypeError", "Iterator next is not callable")
  }
  if self.ordinary_has_instance(ctor, iterator) {
    return iterator
  }
  let helper = self.new_iterator_helper(ctor, iterator, "wrap")
  let _ = js_set_prop(helper, "__iter_next", next_method)
  helper
}

///|
pub fn JSInterpreter::iterator_map(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let mapper = if args.length() > 0 { args[0] } else { Undefined }
  if not(self.is_callable(mapper)) {
    return self.set_error_kind("TypeError", "mapper is not callable")
  }
  let (iter, next_method) =
    match self.ensure_iterator_object_with_next(this_arg) {
      Some(pair) => pair
      None => return self.error_or_undefined()
    }
  let ctor = self.get_iterator_ctor(Undefined)
  let helper = self.new_iterator_helper(ctor, iter, "map")
  let _ = js_set_prop(helper, "__iter_mapper", mapper)
  let _ = js_set_prop(helper, "__iter_index", Number(0.0))
  let _ = js_set_prop(helper, "__iter_next", next_method)
  helper
}

///|
pub fn JSInterpreter::iterator_filter(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let predicate = if args.length() > 0 { args[0] } else { Undefined }
  if not(self.is_callable(predicate)) {
    return self.set_error_kind("TypeError", "predicate is not callable")
  }
  let (iter, next_method) =
    match self.ensure_iterator_object_with_next(this_arg) {
      Some(pair) => pair
      None => return self.error_or_undefined()
    }
  let ctor = self.get_iterator_ctor(Undefined)
  let helper = self.new_iterator_helper(ctor, iter, "filter")
  let _ = js_set_prop(helper, "__iter_predicate", predicate)
  let _ = js_set_prop(helper, "__iter_index", Number(0.0))
  let _ = js_set_prop(helper, "__iter_next", next_method)
  helper
}

///|
pub fn JSInterpreter::iterator_take(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let count_val = if args.length() > 0 { args[0] } else { Number(0.0) }
  let count =
    match self.to_iterator_limit(count_val) {
      Some(n) => n
      None => return self.error_or_undefined()
    }
  let (iter, next_method) =
    match self.ensure_iterator_object_with_next(this_arg) {
      Some(pair) => pair
      None => return self.error_or_undefined()
    }
  let ctor = self.get_iterator_ctor(Undefined)
  let helper = self.new_iterator_helper(ctor, iter, "take")
  let _ = js_set_prop(helper, "__iter_limit", Number(count.to_double()))
  let _ = js_set_prop(helper, "__iter_count", Number(0.0))
  let _ = js_set_prop(helper, "__iter_next", next_method)
  helper
}

///|
pub fn JSInterpreter::iterator_drop(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let count_val = if args.length() > 0 { args[0] } else { Number(0.0) }
  let count =
    match self.to_iterator_limit(count_val) {
      Some(n) => n
      None => return self.error_or_undefined()
    }
  let (iter, next_method) =
    match self.ensure_iterator_object_with_next(this_arg) {
      Some(pair) => pair
      None => return self.error_or_undefined()
    }
  let ctor = self.get_iterator_ctor(Undefined)
  let helper = self.new_iterator_helper(ctor, iter, "drop")
  let _ = js_set_prop(helper, "__iter_limit", Number(count.to_double()))
  let _ = js_set_prop(helper, "__iter_dropped", Number(0.0))
  let _ = js_set_prop(helper, "__iter_next", next_method)
  helper
}

///|
pub fn JSInterpreter::iterator_flat_map(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let mapper = if args.length() > 0 { args[0] } else { Undefined }
  if not(self.is_callable(mapper)) {
    return self.set_error_kind("TypeError", "mapper is not callable")
  }
  let (iter, next_method) =
    match self.ensure_iterator_object_with_next(this_arg) {
      Some(pair) => pair
      None => return self.error_or_undefined()
    }
  let ctor = self.get_iterator_ctor(Undefined)
  let helper = self.new_iterator_helper(ctor, iter, "flatMap")
  let _ = js_set_prop(helper, "__iter_mapper", mapper)
  let _ = js_set_prop(helper, "__iter_index", Number(0.0))
  let _ = js_set_prop(helper, "__iter_inner", Undefined)
  let _ = js_set_prop(helper, "__iter_next", next_method)
  helper
}

///|
pub fn JSInterpreter::iterator_for_each(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let callback = if args.length() > 0 { args[0] } else { Undefined }
  if not(self.is_callable(callback)) {
    self.iterator_close(this_arg)
    return self.set_error_kind("TypeError", "callback is not callable")
  }
  let (iter, next_method) =
    match self.ensure_iterator_object_with_next(this_arg) {
      Some(pair) => pair
      None => return self.error_or_undefined()
    }
  let mut idx = 0
  while true {
    let result =
        match self.iterator_next_object_with(iter, next_method) {
          Some(res) => res
          None => return self.error_or_undefined()
        }
    let done = self.get_prop_value(result, "done").to_boolean()
    if done {
      return Undefined
    }
    let value = self.get_prop_value(result, "value")
    let _ = self.call_function(callback, Undefined, [value, Number(idx.to_double())])
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iter)
        return err
      }
      None => ()
    }
    idx += 1
  }
  Undefined
}

///|
pub fn JSInterpreter::iterator_to_array(
  self : JSInterpreter,
  this_arg : JSValue,
  _args : Array[JSValue],
) -> JSValue {
  let (iter, next_method) =
    match self.ensure_iterator_object_with_next(this_arg) {
      Some(pair) => pair
      None => return self.error_or_undefined()
    }
  let items : Array[JSValue] = []
  while true {
    let result =
        match self.iterator_next_object_with(iter, next_method) {
          Some(res) => res
          None => return self.error_or_undefined()
        }
    let done = self.get_prop_value(result, "done").to_boolean()
    if done {
      return js_array_from(items)
    }
    let value = self.get_prop_value(result, "value")
    items.push(value)
  }
  js_array_from(items)
}

///|
pub fn JSInterpreter::iterator_reduce(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let reducer = if args.length() > 0 { args[0] } else { Undefined }
  if not(self.is_callable(reducer)) {
    self.iterator_close(this_arg)
    return self.set_error_kind("TypeError", "reducer is not callable")
  }
  let (iter, next_method) =
    match self.ensure_iterator_object_with_next(this_arg) {
      Some(pair) => pair
      None => return self.error_or_undefined()
    }
  let mut idx = 0
  let mut acc : JSValue = Undefined
  let mut has_acc = args.length() > 1
  if has_acc {
    acc = args[1]
  }
  while true {
    let result =
        match self.iterator_next_object_with(iter, next_method) {
          Some(res) => res
          None => return self.error_or_undefined()
        }
    let done = self.get_prop_value(result, "done").to_boolean()
    if done {
      if not(has_acc) {
        return self.set_error_kind("TypeError", "Reduce of empty iterator with no initial value")
      }
      return acc
    }
    let value = self.get_prop_value(result, "value")
    if not(has_acc) {
      acc = value
      has_acc = true
      idx += 1
      continue
    }
    let next_acc = self.call_function(reducer, Undefined, [acc, value, Number(idx.to_double())])
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iter)
        return err
      }
      None => ()
    }
    acc = next_acc
    idx += 1
  }
  acc
}

///|
pub fn JSInterpreter::iterator_every(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let predicate = if args.length() > 0 { args[0] } else { Undefined }
  if not(self.is_callable(predicate)) {
    self.iterator_close(this_arg)
    return self.set_error_kind("TypeError", "predicate is not callable")
  }
  let (iter, next_method) =
    match self.ensure_iterator_object_with_next(this_arg) {
      Some(pair) => pair
      None => return self.error_or_undefined()
    }
  let mut idx = 0
  while true {
    let result =
        match self.iterator_next_object_with(iter, next_method) {
          Some(res) => res
          None => return self.error_or_undefined()
        }
    let done = self.get_prop_value(result, "done").to_boolean()
    if done {
      return Bool(true)
    }
    let value = self.get_prop_value(result, "value")
    let passed = self.call_function(predicate, Undefined, [value, Number(idx.to_double())])
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iter)
        return err
      }
      None => ()
    }
    if not(passed.to_boolean()) {
      self.iterator_close(iter)
      return Bool(false)
    }
    idx += 1
  }
  Bool(true)
}

///|
pub fn JSInterpreter::iterator_some(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let predicate = if args.length() > 0 { args[0] } else { Undefined }
  if not(self.is_callable(predicate)) {
    self.iterator_close(this_arg)
    return self.set_error_kind("TypeError", "predicate is not callable")
  }
  let (iter, next_method) =
    match self.ensure_iterator_object_with_next(this_arg) {
      Some(pair) => pair
      None => return self.error_or_undefined()
    }
  let mut idx = 0
  while true {
    let result =
        match self.iterator_next_object_with(iter, next_method) {
          Some(res) => res
          None => return self.error_or_undefined()
        }
    let done = self.get_prop_value(result, "done").to_boolean()
    if done {
      return Bool(false)
    }
    let value = self.get_prop_value(result, "value")
    let passed = self.call_function(predicate, Undefined, [value, Number(idx.to_double())])
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iter)
        return err
      }
      None => ()
    }
    if passed.to_boolean() {
      self.iterator_close(iter)
      return Bool(true)
    }
    idx += 1
  }
  Bool(false)
}

///|
pub fn JSInterpreter::iterator_find(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let predicate = if args.length() > 0 { args[0] } else { Undefined }
  if not(self.is_callable(predicate)) {
    self.iterator_close(this_arg)
    return self.set_error_kind("TypeError", "predicate is not callable")
  }
  let (iter, next_method) =
    match self.ensure_iterator_object_with_next(this_arg) {
      Some(pair) => pair
      None => return self.error_or_undefined()
    }
  let mut idx = 0
  while true {
    let result =
        match self.iterator_next_object_with(iter, next_method) {
          Some(res) => res
          None => return self.error_or_undefined()
        }
    let done = self.get_prop_value(result, "done").to_boolean()
    if done {
      return Undefined
    }
    let value = self.get_prop_value(result, "value")
    let passed = self.call_function(predicate, Undefined, [value, Number(idx.to_double())])
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iter)
        return err
      }
      None => ()
    }
    if passed.to_boolean() {
      self.iterator_close(iter)
      return value
    }
    idx += 1
  }
  Undefined
}

///|
fn JSInterpreter::iterator_helper_next_inner(
  self : JSInterpreter,
  this_arg : JSValue,
  source : JSValue,
) -> JSValue {
  let kind_val = js_get_prop(this_arg, "__iter_kind")
  let kind =
    match kind_val {
      String(s) => s
      _ => ""
    }
  let cached_next = js_get_prop(this_arg, "__iter_next")
  let use_cached_next = self.is_callable(cached_next)
  match kind {
    "wrap" => {
      let cached_next = js_get_prop(this_arg, "__iter_next")
      let next_method = match cached_next {
        Undefined | Null => self.get_prop_value(source, "next")
        _ => cached_next
      }
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      let result = self.call_function(next_method, source, [])
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      match result {
        Object(_) | Function(_) | Array(_) => {
          let is_done = self.get_prop_value(result, "done").to_boolean()
          if is_done {
            let _ = js_set_prop(this_arg, "__iter_done", Bool(true))
          }
        }
        _ => ()
      }
      result
    }
    "map" => {
      let mapper = js_get_prop(this_arg, "__iter_mapper")
      let idx_val = js_get_prop(this_arg, "__iter_index")
      let mut idx = idx_val.to_number().to_int()
      let result =
        match (if use_cached_next {
            self.iterator_next_object_with(source, cached_next)
          } else {
            self.iterator_next_object(source)
          }) {
          Some(res) => res
          None => return self.error_or_undefined()
        }
      let is_done = self.get_prop_value(result, "done").to_boolean()
      if is_done {
        let _ = js_set_prop(this_arg, "__iter_done", Bool(true))
        return self.make_iter_result(Undefined, true)
      }
      let value = self.get_prop_value(result, "value")
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      let mapped = self.call_function(mapper, Undefined, [value, Number(idx.to_double())])
      match self.peek_error() {
        Some(err) => {
          self.iterator_close_on_error(source)
          return err
        }
        None => ()
      }
      idx += 1
      let _ = js_set_prop(this_arg, "__iter_index", Number(idx.to_double()))
      self.make_iter_result(mapped, false)
    }
    "filter" => {
      let predicate = js_get_prop(this_arg, "__iter_predicate")
      let idx_val = js_get_prop(this_arg, "__iter_index")
      let mut idx = idx_val.to_number().to_int()
      while true {
        let result =
          match (if use_cached_next {
              self.iterator_next_object_with(source, cached_next)
            } else {
              self.iterator_next_object(source)
            }) {
            Some(res) => res
            None => return self.error_or_undefined()
          }
        let is_done = self.get_prop_value(result, "done").to_boolean()
        if is_done {
          let _ = js_set_prop(this_arg, "__iter_done", Bool(true))
          return self.make_iter_result(Undefined, true)
        }
        let value = self.get_prop_value(result, "value")
        match self.peek_error() {
          Some(err) => return err
          None => ()
        }
        let passed = self.call_function(predicate, Undefined, [value, Number(idx.to_double())])
        match self.peek_error() {
          Some(err) => {
            self.iterator_close_on_error(source)
            return err
          }
          None => ()
        }
        idx += 1
        let _ = js_set_prop(this_arg, "__iter_index", Number(idx.to_double()))
        if passed.to_boolean() {
          return self.make_iter_result(value, false)
        }
      }
      self.make_iter_result(Undefined, true)
    }
    "take" => {
      let limit_val = js_get_prop(this_arg, "__iter_limit")
      let count_val = js_get_prop(this_arg, "__iter_count")
      let limit = limit_val.to_number().to_int()
      let mut count = count_val.to_number().to_int()
      if count >= limit {
        let _ = js_set_prop(this_arg, "__iter_done", Bool(true))
        self.iterator_close(source)
        return self.make_iter_result(Undefined, true)
      }
      let result =
        match (if use_cached_next {
            self.iterator_next_object_with(source, cached_next)
          } else {
            self.iterator_next_object(source)
          }) {
          Some(res) => res
          None => return self.error_or_undefined()
        }
      let is_done = self.get_prop_value(result, "done").to_boolean()
      if is_done {
        let _ = js_set_prop(this_arg, "__iter_done", Bool(true))
        return self.make_iter_result(Undefined, true)
      }
      let value = self.get_prop_value(result, "value")
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      count += 1
      let _ = js_set_prop(this_arg, "__iter_count", Number(count.to_double()))
      self.make_iter_result(value, false)
    }
    "drop" => {
      let limit_val = js_get_prop(this_arg, "__iter_limit")
      let dropped_val = js_get_prop(this_arg, "__iter_dropped")
      let limit = limit_val.to_number().to_int()
      let mut dropped = dropped_val.to_number().to_int()
      while dropped < limit {
        let result =
          match (if use_cached_next {
              self.iterator_next_object_with(source, cached_next)
            } else {
              self.iterator_next_object(source)
            }) {
            Some(res) => res
            None => return self.error_or_undefined()
          }
        let is_done = self.get_prop_value(result, "done").to_boolean()
        if is_done {
          let _ = js_set_prop(this_arg, "__iter_done", Bool(true))
          return self.make_iter_result(Undefined, true)
        }
        dropped += 1
      }
      let _ = js_set_prop(this_arg, "__iter_dropped", Number(dropped.to_double()))
      let result =
        match (if use_cached_next {
            self.iterator_next_object_with(source, cached_next)
          } else {
            self.iterator_next_object(source)
          }) {
          Some(res) => res
          None => return self.error_or_undefined()
        }
      let is_done = self.get_prop_value(result, "done").to_boolean()
      if is_done {
        let _ = js_set_prop(this_arg, "__iter_done", Bool(true))
        return self.make_iter_result(Undefined, true)
      }
      let value = self.get_prop_value(result, "value")
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      self.make_iter_result(value, false)
    }
    "flatMap" => {
      let mapper = js_get_prop(this_arg, "__iter_mapper")
      let idx_val = js_get_prop(this_arg, "__iter_index")
      let mut idx = idx_val.to_number().to_int()
      while true {
        let inner = js_get_prop(this_arg, "__iter_inner")
        match inner {
          Object(_) | Function(_) | Array(_) => {
            let inner_result =
              match self.iterator_next_object(inner) {
                Some(res) => res
                None => {
                  self.iterator_close_on_error(source)
                  return self.error_or_undefined()
                }
              }
            let inner_done_val = self.get_prop_value(inner_result, "done")
            match self.peek_error() {
              Some(err) => {
                self.iterator_close_on_error(source)
                return err
              }
              None => ()
            }
            let inner_done = inner_done_val.to_boolean()
            if inner_done {
              let _ = js_set_prop(this_arg, "__iter_inner", Undefined)
              continue
            }
            let value = self.get_prop_value(inner_result, "value")
            match self.peek_error() {
              Some(err) => {
                self.iterator_close_on_error(source)
                return err
              }
              None => ()
            }
            return self.make_iter_result(value, false)
          }
          _ => ()
        }

        let outer_result =
          match (if use_cached_next {
              self.iterator_next_object_with(source, cached_next)
            } else {
              self.iterator_next_object(source)
            }) {
            Some(res) => res
            None => return self.error_or_undefined()
          }
        let outer_done = self.get_prop_value(outer_result, "done").to_boolean()
        if outer_done {
          let _ = js_set_prop(this_arg, "__iter_done", Bool(true))
          return self.make_iter_result(Undefined, true)
        }
        let outer_val = self.get_prop_value(outer_result, "value")
        match self.peek_error() {
          Some(err) => return err
          None => ()
        }
        let mapped = self.call_function(mapper, Undefined, [outer_val, Number(idx.to_double())])
        match self.peek_error() {
          Some(err) => {
            self.iterator_close_on_error(source)
            return err
          }
          None => ()
        }
        idx += 1
        let _ = js_set_prop(this_arg, "__iter_index", Number(idx.to_double()))
        let inner_iter =
          match self.get_iterator(mapped) {
            Some(it) => it
            None => {
              let _ = self.set_error_kind("TypeError", "flatMap value is not iterable")
              self.iterator_close_on_error(source)
              return self.error_or_undefined()
            }
          }
        let _ = js_set_prop(this_arg, "__iter_inner", inner_iter)
      }
      self.make_iter_result(Undefined, true)
    }
    _ => self.set_error_kind("TypeError", "Unknown iterator helper kind")
  }
}

///|
pub fn JSInterpreter::iterator_helper_next(
  self : JSInterpreter,
  this_arg : JSValue,
  _args : Array[JSValue],
) -> JSValue {
  let source = js_get_prop(this_arg, "__iter_source")
  match source {
    Undefined =>
      return self.set_error_kind("TypeError", "Iterator helper called on incompatible receiver")
    _ => ()
  }
  let active_flag = js_get_prop(this_arg, "__iter_active")
  match active_flag {
    Bool(true) =>
      return self.set_error_kind("TypeError", "Iterator helper is already running")
    _ => ()
  }
  let _ = js_set_prop(this_arg, "__iter_active", Bool(true))
  let done_flag = js_get_prop(this_arg, "__iter_done")
  let done =
    match done_flag {
      Bool(b) => b
      _ => false
    }
  if done {
    let result = self.make_iter_result(Undefined, true)
    let _ = js_set_prop(this_arg, "__iter_active", Bool(false))
    return result
  }
  let result = self.iterator_helper_next_inner(this_arg, source)
  let _ = js_set_prop(this_arg, "__iter_active", Bool(false))
  result
}

///|
pub fn JSInterpreter::iterator_helper_return(
  self : JSInterpreter,
  this_arg : JSValue,
  _args : Array[JSValue],
) -> JSValue {
  let source = js_get_prop(this_arg, "__iter_source")
  match source {
    Undefined =>
      return self.set_error_kind("TypeError", "Iterator helper called on incompatible receiver")
    _ => ()
  }
  let kind_val = js_get_prop(this_arg, "__iter_kind")
  let kind =
    match kind_val {
      String(s) => s
      _ => ""
    }
  match kind {
    "wrap" => {
      let _ = js_set_prop(this_arg, "__iter_done", Bool(true))
      let ret = self.get_prop_value(source, "return")
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      match ret {
        Undefined | Null => self.make_iter_result(Undefined, true)
        _ => {
          let result = self.call_function(ret, source, [])
          match self.peek_error() {
            Some(err) => err
            None => result
          }
        }
      }
    }
    _ => {
      let done_flag = js_get_prop(this_arg, "__iter_done")
      match done_flag {
        Bool(true) => return self.make_iter_result(Undefined, true)
        _ => ()
      }
      let _ = js_set_prop(this_arg, "__iter_done", Bool(true))
      self.iterator_close(source)
      self.make_iter_result(Undefined, true)
    }
  }
}

///|
pub fn JSInterpreter::iterator_helper_throw(
  self : JSInterpreter,
  this_arg : JSValue,
  _args : Array[JSValue],
) -> JSValue {
  let source = js_get_prop(this_arg, "__iter_source")
  match source {
    Undefined =>
      return self.set_error_kind("TypeError", "Iterator helper called on incompatible receiver")
    _ => ()
  }
  self.set_error_kind("TypeError", "Iterator helper throw is not supported")
}
