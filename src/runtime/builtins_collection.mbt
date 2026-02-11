///|
// SameValueZero comparison for Map/Set keys
fn same_value_zero(a : JSValue, b : JSValue) -> Bool {
  match (a, b) {
    (Number(x), Number(y)) =>
      if x.is_nan() && y.is_nan() {
        true
      } else if x == 0.0 && y == 0.0 {
        // +0 === -0 in SameValueZero
        true
      } else {
        x == y
      }
    (String(x), String(y)) => x == y
    (Bool(x), Bool(y)) => x == y
    (Undefined, Undefined) => true
    (Null, Null) => true
    // Reference equality for objects
    (Object(m1), Object(m2)) => m1.id == m2.id
    (JSValue::Array(a1), JSValue::Array(a2)) => a1.id == a2.id
    (Function(f1), Function(f2)) => f1.id == f2.id
    _ => false
  }
}

///|
fn JSInterpreter::map_get_entry(
  self : JSInterpreter,
  map_obj : JSValue,
  key : JSValue,
) -> JSValue {
  let _ = self
  match js_get_prop(map_obj, "__map_entries") {
    JSValue::Array(arr) => {
      for i = 0; i < arr.length; i = i + 1 {
        match arr.items[i] {
          JSValue::Array(pair) if pair.length >= 2 =>
            if same_value_zero(pair.items[0], key) {
              return pair.items[1]
            }
          _ => ()
        }
      }
      Undefined
    }
    _ => Undefined
  }
}

///|
fn JSInterpreter::map_set_entry(
  self : JSInterpreter,
  map_obj : JSValue,
  key : JSValue,
  value : JSValue,
) -> JSValue {
  let _ = self
  match js_get_prop(map_obj, "__map_entries") {
    JSValue::Array(arr) => {
      // Check if key exists
      for i = 0; i < arr.length; i = i + 1 {
        match arr.items[i] {
          JSValue::Array(pair) if pair.length >= 2 =>
            if same_value_zero(pair.items[0], key) {
              // Update existing entry
              let new_pair = js_new_array()
              let _ = js_array_push(new_pair, key)
              let _ = js_array_push(new_pair, value)
              arr.items[i] = new_pair
              return value
            }
          _ => ()
        }
      }
      // Add new entry
      let new_pair = js_new_array()
      let _ = js_array_push(new_pair, key)
      let _ = js_array_push(new_pair, value)
      let _ = js_array_push(JSValue::Array(arr), new_pair)
    }
    _ => ()
  }
  value
}

///|
fn JSInterpreter::map_has_entry(
  self : JSInterpreter,
  map_obj : JSValue,
  key : JSValue,
) -> Bool {
  let _ = self
  match js_get_prop(map_obj, "__map_entries") {
    JSValue::Array(arr) => {
      for i = 0; i < arr.length; i = i + 1 {
        match arr.items[i] {
          JSValue::Array(pair) if pair.length >= 2 =>
            if same_value_zero(pair.items[0], key) {
              return true
            }
          _ => ()
        }
      }
      false
    }
    _ => false
  }
}

///|
fn JSInterpreter::map_delete_entry(
  self : JSInterpreter,
  map_obj : JSValue,
  key : JSValue,
) -> Bool {
  let _ = self
  match js_get_prop(map_obj, "__map_entries") {
    JSValue::Array(arr) => {
      for i = 0; i < arr.length; i = i + 1 {
        match arr.items[i] {
          JSValue::Array(pair) if pair.length >= 2 =>
            if same_value_zero(pair.items[0], key) {
              let _ = arr.items.remove(i)
              arr.length = arr.length - 1
              return true
            }
          _ => ()
        }
      }
      false
    }
    _ => false
  }
}

///|
fn JSInterpreter::set_add_entry(
  self : JSInterpreter,
  set_obj : JSValue,
  value : JSValue,
) -> JSValue {
  let _ = self
  match js_get_prop(set_obj, "__set_entries") {
    JSValue::Array(arr) => {
      // Check if value exists
      for i = 0; i < arr.length; i = i + 1 {
        if same_value_zero(arr.items[i], value) {
          return value
        }
      }
      // Add new entry
      let _ = js_array_push(JSValue::Array(arr), value)
    }
    _ => ()
  }
  value
}

///|
fn JSInterpreter::set_has_entry(
  self : JSInterpreter,
  set_obj : JSValue,
  value : JSValue,
) -> Bool {
  let _ = self
  match js_get_prop(set_obj, "__set_entries") {
    JSValue::Array(arr) => {
      for i = 0; i < arr.length; i = i + 1 {
        if same_value_zero(arr.items[i], value) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn JSInterpreter::set_delete_entry(
  self : JSInterpreter,
  set_obj : JSValue,
  value : JSValue,
) -> Bool {
  let _ = self
  match js_get_prop(set_obj, "__set_entries") {
    JSValue::Array(arr) => {
      for i = 0; i < arr.length; i = i + 1 {
        if same_value_zero(arr.items[i], value) {
          let _ = arr.items.remove(i)
          arr.length = arr.length - 1
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn JSInterpreter::new_map_key_iterator(
  self : JSInterpreter,
  map_obj : JSValue,
) -> JSValue {
  let iter = self.new_object()
  let _ = js_set_prop(iter, "__map_ref", map_obj)
  let _ = js_set_prop(iter, "__iter_index", Number(0.0))
  let _ = js_set_prop(iter, "__iter_kind", String("key"))
  let next_fn = self.make_native("MapIterator.next")
  let _ = js_set_prop(iter, "next", next_fn)
  let iter_self_fn = self.make_native("Iterator.self")
  let _ = js_set_prop(iter, "@@iterator", iter_self_fn)
  iter
}

///|
fn JSInterpreter::new_map_value_iterator(
  self : JSInterpreter,
  map_obj : JSValue,
) -> JSValue {
  let iter = self.new_object()
  let _ = js_set_prop(iter, "__map_ref", map_obj)
  let _ = js_set_prop(iter, "__iter_index", Number(0.0))
  let _ = js_set_prop(iter, "__iter_kind", String("value"))
  let next_fn = self.make_native("MapIterator.next")
  let _ = js_set_prop(iter, "next", next_fn)
  let iter_self_fn = self.make_native("Iterator.self")
  let _ = js_set_prop(iter, "@@iterator", iter_self_fn)
  iter
}

///|
fn JSInterpreter::new_map_entry_iterator(
  self : JSInterpreter,
  map_obj : JSValue,
) -> JSValue {
  let iter = self.new_object()
  let _ = js_set_prop(iter, "__map_ref", map_obj)
  let _ = js_set_prop(iter, "__iter_index", Number(0.0))
  let _ = js_set_prop(iter, "__iter_kind", String("entry"))
  let next_fn = self.make_native("MapIterator.next")
  let _ = js_set_prop(iter, "next", next_fn)
  let iter_self_fn = self.make_native("Iterator.self")
  let _ = js_set_prop(iter, "@@iterator", iter_self_fn)
  iter
}

///|
fn JSInterpreter::new_set_value_iterator(
  self : JSInterpreter,
  set_obj : JSValue,
) -> JSValue {
  let iter = self.new_object()
  let _ = js_set_prop(iter, "__set_ref", set_obj)
  let _ = js_set_prop(iter, "__iter_index", Number(0.0))
  let _ = js_set_prop(iter, "__iter_kind", String("value"))
  let next_fn = self.make_native("SetIterator.next")
  let _ = js_set_prop(iter, "next", next_fn)
  let iter_self_fn = self.make_native("Iterator.self")
  let _ = js_set_prop(iter, "@@iterator", iter_self_fn)
  iter
}

///|
fn JSInterpreter::new_set_entry_iterator(
  self : JSInterpreter,
  set_obj : JSValue,
) -> JSValue {
  let iter = self.new_object()
  let _ = js_set_prop(iter, "__set_ref", set_obj)
  let _ = js_set_prop(iter, "__iter_index", Number(0.0))
  let _ = js_set_prop(iter, "__iter_kind", String("entry"))
  let next_fn = self.make_native("SetIterator.next")
  let _ = js_set_prop(iter, "next", next_fn)
  let iter_self_fn = self.make_native("Iterator.self")
  let _ = js_set_prop(iter, "@@iterator", iter_self_fn)
  iter
}

// === WeakMap helpers ===

///|
/// Check if a value can be a WeakMap/WeakSet key (must be object-like)
fn is_weak_key(val : JSValue) -> Bool {
  match val {
    Object(_) | JSValue::Array(_) | Function(_) => true
    _ => false
  }
}

///|
/// Get the object ID for a weak key
fn get_weak_key_id(val : JSValue) -> Int {
  match val {
    Object(map) => map.id
    JSValue::Array(arr) => arr.id
    Function(f) => f.id
    _ => -1
  }
}

///|
fn JSInterpreter::weakmap_get_entry(
  self : JSInterpreter,
  wm_obj : JSValue,
  key : JSValue,
) -> JSValue {
  let _ = self
  if not(is_weak_key(key)) {
    return Undefined
  }
  let key_id = get_weak_key_id(key)
  match js_get_prop(wm_obj, "__weakmap_entries") {
    JSValue::Array(arr) => {
      for i = 0; i < arr.length; i = i + 1 {
        match arr.items[i] {
          JSValue::Array(pair) if pair.length >= 2 =>
            match pair.items[0] {
              Number(id) if id.to_int() == key_id => return pair.items[1]
              _ => ()
            }
          _ => ()
        }
      }
      Undefined
    }
    _ => Undefined
  }
}

///|
fn JSInterpreter::weakmap_set_entry(
  self : JSInterpreter,
  wm_obj : JSValue,
  key : JSValue,
  value : JSValue,
) -> JSValue {
  let _ = self
  if not(is_weak_key(key)) {
    return Undefined
  }
  let key_id = get_weak_key_id(key)
  match js_get_prop(wm_obj, "__weakmap_entries") {
    JSValue::Array(arr) => {
      // Check if key exists
      for i = 0; i < arr.length; i = i + 1 {
        match arr.items[i] {
          JSValue::Array(pair) if pair.length >= 2 =>
            match pair.items[0] {
              Number(id) if id.to_int() == key_id => {
                // Update existing entry
                let new_pair = js_new_array()
                let _ = js_array_push(new_pair, Number(key_id.to_double()))
                let _ = js_array_push(new_pair, value)
                arr.items[i] = new_pair
                return wm_obj
              }
              _ => ()
            }
          _ => ()
        }
      }
      // Add new entry
      let new_pair = js_new_array()
      let _ = js_array_push(new_pair, Number(key_id.to_double()))
      let _ = js_array_push(new_pair, value)
      let _ = js_array_push(JSValue::Array(arr), new_pair)
    }
    _ => ()
  }
  wm_obj
}

///|
fn JSInterpreter::weakmap_has_entry(
  self : JSInterpreter,
  wm_obj : JSValue,
  key : JSValue,
) -> Bool {
  let _ = self
  if not(is_weak_key(key)) {
    return false
  }
  let key_id = get_weak_key_id(key)
  match js_get_prop(wm_obj, "__weakmap_entries") {
    JSValue::Array(arr) => {
      for i = 0; i < arr.length; i = i + 1 {
        match arr.items[i] {
          JSValue::Array(pair) if pair.length >= 2 =>
            match pair.items[0] {
              Number(id) if id.to_int() == key_id => return true
              _ => ()
            }
          _ => ()
        }
      }
      false
    }
    _ => false
  }
}

///|
fn JSInterpreter::weakmap_delete_entry(
  self : JSInterpreter,
  wm_obj : JSValue,
  key : JSValue,
) -> Bool {
  let _ = self
  if not(is_weak_key(key)) {
    return false
  }
  let key_id = get_weak_key_id(key)
  match js_get_prop(wm_obj, "__weakmap_entries") {
    JSValue::Array(arr) => {
      for i = 0; i < arr.length; i = i + 1 {
        match arr.items[i] {
          JSValue::Array(pair) if pair.length >= 2 =>
            match pair.items[0] {
              Number(id) if id.to_int() == key_id => {
                let _ = arr.items.remove(i)
                arr.length = arr.length - 1
                return true
              }
              _ => ()
            }
          _ => ()
        }
      }
      false
    }
    _ => false
  }
}

// === WeakSet helpers ===

///|
fn JSInterpreter::weakset_add_entry(
  self : JSInterpreter,
  ws_obj : JSValue,
  value : JSValue,
) -> JSValue {
  let _ = self
  if not(is_weak_key(value)) {
    return ws_obj
  }
  let val_id = get_weak_key_id(value)
  match js_get_prop(ws_obj, "__weakset_entries") {
    JSValue::Array(arr) => {
      // Check if value exists
      for i = 0; i < arr.length; i = i + 1 {
        match arr.items[i] {
          Number(id) if id.to_int() == val_id => return ws_obj
          _ => ()
        }
      }
      // Add new entry
      let _ = js_array_push(JSValue::Array(arr), Number(val_id.to_double()))
    }
    _ => ()
  }
  ws_obj
}

///|
fn JSInterpreter::weakset_has_entry(
  self : JSInterpreter,
  ws_obj : JSValue,
  value : JSValue,
) -> Bool {
  let _ = self
  if not(is_weak_key(value)) {
    return false
  }
  let val_id = get_weak_key_id(value)
  match js_get_prop(ws_obj, "__weakset_entries") {
    JSValue::Array(arr) => {
      for i = 0; i < arr.length; i = i + 1 {
        match arr.items[i] {
          Number(id) if id.to_int() == val_id => return true
          _ => ()
        }
      }
      false
    }
    _ => false
  }
}

///|
fn JSInterpreter::weakset_delete_entry(
  self : JSInterpreter,
  ws_obj : JSValue,
  value : JSValue,
) -> Bool {
  let _ = self
  if not(is_weak_key(value)) {
    return false
  }
  let val_id = get_weak_key_id(value)
  match js_get_prop(ws_obj, "__weakset_entries") {
    JSValue::Array(arr) => {
      for i = 0; i < arr.length; i = i + 1 {
        match arr.items[i] {
          Number(id) if id.to_int() == val_id => {
            let _ = arr.items.remove(i)
            arr.length = arr.length - 1
            return true
          }
          _ => ()
        }
      }
      false
    }
    _ => false
  }
}

// === FinalizationRegistry helpers ===

///|
fn JSInterpreter::fr_register(
  self : JSInterpreter,
  fr_obj : JSValue,
  target : JSValue,
  held_value : JSValue,
  unregister_token : JSValue,
) -> Unit {
  let _ = self
  if not(is_weak_key(target)) {
    return
  }
  let target_id = get_weak_key_id(target)
  let token_id = if is_weak_key(unregister_token) {
    get_weak_key_id(unregister_token)
  } else {
    -1
  }
  match js_get_prop(fr_obj, "__fr_registrations") {
    JSValue::Array(arr) => {
      // Create registration entry: [targetId, heldValue, tokenId]
      let entry = js_new_array()
      let _ = js_array_push(entry, Number(target_id.to_double()))
      let _ = js_array_push(entry, held_value)
      let _ = js_array_push(entry, Number(token_id.to_double()))
      let _ = js_array_push(JSValue::Array(arr), entry)
    }
    _ => ()
  }
}

///|
fn JSInterpreter::fr_unregister(
  self : JSInterpreter,
  fr_obj : JSValue,
  unregister_token : JSValue,
) -> Bool {
  let _ = self
  if not(is_weak_key(unregister_token)) {
    return false
  }
  let token_id = get_weak_key_id(unregister_token)
  let mut removed = false
  match js_get_prop(fr_obj, "__fr_registrations") {
    JSValue::Array(arr) => {
      let mut i = 0
      while i < arr.length {
        match arr.items[i] {
          JSValue::Array(entry) if entry.length >= 3 =>
            match entry.items[2] {
              Number(tid) if tid.to_int() == token_id => {
                let _ = arr.items.remove(i)
                arr.length = arr.length - 1
                removed = true
                continue // Don't increment i
              }
              _ => ()
            }
          _ => ()
        }
        i = i + 1
      }
    }
    _ => ()
  }
  removed
}
